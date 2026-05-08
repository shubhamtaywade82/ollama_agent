# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "securerandom"

require_relative "../security/resource_guard"
require_relative "cas_guard"
require_relative "criticality_policy"

module OllamaAgent
  module Runtime
    # POSIX-oriented atomic write (temp → fsync → rename → parent fsync).
    #
    # Directory +fd fsync+ after +rename+ is required on Linux for crash-safe metadata durability.
    # When +File#fsync+ on a directory file descriptor is unsupported (+Errno::EINVAL+, +ENOTSUP+,
    # or +NotImplementedError+), the step is skipped (see +mutation_step+ payload +dir_fsync_status+).
    # rubocop:disable Metrics/ClassLength -- single orchestrator; helpers are private below
    class AtomicMutator
      def initialize(workspace_root:, ownership_index:, fencing_allocator:, wal:)
        @workspace_root = File.expand_path(workspace_root)
        @ownership_index = ownership_index
        @fencing_allocator = fencing_allocator
        @wal = wal
      end

      # Atomically replace +path+ under the configured workspace root.
      #
      # @param fencing_token [Integer] last value returned by {FencingAllocator#allocate} for this
      #   path scope (+absolute+ path string). The mutator calls {FencingAllocator#allocate} again
      #   internally to advance the fence; +fencing_token+ must equal +current_allocated - 1+ where
      #   +current_allocated+ is the value just produced by that internal allocate (i.e. the
      #   caller-held token is always exactly one behind the mutator's post-check token).
      # @return [:written, :duplicate, :forbidden, :stale_token, :precondition_failed, :inode_swapped]
      # rubocop:disable Metrics/ParameterLists -- public mutation envelope matches kernel contract
      def write(path:, content:, mode:, fencing_token:, expected_pre_hash:, intent_hash:, manifest_id:,
                logical_stamp:, owner_required: nil, supervisor_lease: false)
        outcome = guard_and_ownership(path, mode, manifest_id, logical_stamp, owner_required,
                                      supervisor_lease)
        return outcome if outcome

        absolute = expand_workspace_path(path.to_s)
        outcome = cas_and_wal(absolute, content, fencing_token, expected_pre_hash, intent_hash,
                              manifest_id, logical_stamp)
        return outcome if outcome != :continue

        persist_atomic_swap(absolute, content, manifest_id, logical_stamp)
      end
      # rubocop:enable Metrics/ParameterLists

      private

      # rubocop:disable Metrics/ParameterLists
      def guard_and_ownership(path, mode, manifest_id, logical_stamp, owner_required, supervisor_lease)
        guard = OllamaAgent::Security::ResourceGuard.new(root: @workspace_root)
        absolute = expand_workspace_path(path.to_s)
        return :forbidden unless guard.allow?(absolute)

        track_step(manifest_id, logical_stamp, "path_resolved", "absolute" => absolute)

        node = @ownership_index.lookup(absolute_path: absolute, workspace_root: @workspace_root)
        gate = ownership_gate_outcome(node, mode, owner_required, supervisor_lease)
        return gate if gate

        track_step(manifest_id, logical_stamp, "ownership_ok", "owner" => node.owner)
        nil
      end
      # rubocop:enable Metrics/ParameterLists

      # rubocop:disable Metrics/ParameterLists
      def cas_and_wal(absolute, content, fencing_token, expected_pre_hash, intent_hash, manifest_id,
                      logical_stamp)
        cas = fencing_and_precondition(absolute, fencing_token, expected_pre_hash)
        return cas if cas != :ok

        track_step(manifest_id, logical_stamp, "cas_ok")
        record_wal_intent(absolute, content, intent_hash, manifest_id, logical_stamp)
      end
      # rubocop:enable Metrics/ParameterLists

      def fencing_and_precondition(absolute, fencing_token, expected_pre_hash)
        prior = read_destination_bytes(absolute)
        allocated = @fencing_allocator.allocate(scope: absolute)
        CASGuard.check(
          current_content_or_nil: prior,
          expected_pre_hash: expected_pre_hash,
          fencing_token_provided: fencing_token,
          fencing_token_current: allocated
        )
      end

      def record_wal_intent(absolute, content, intent_hash, manifest_id, logical_stamp)
        wal_status = @wal.append_mutation(
          manifest_id: manifest_id,
          logical_stamp: logical_stamp,
          payload: atomic_write_payload(absolute, content),
          intent_hash: intent_hash
        )
        return :duplicate if wal_status == :duplicate

        track_step(manifest_id, logical_stamp, "wal_intent_inserted")
        :continue
      end

      def atomic_write_payload(absolute, content)
        JSON.generate(
          "op" => "atomic_write",
          "path" => relative_workspace_path(absolute),
          "bytes" => content.b.bytesize
        )
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- single try/rename/finally cleanup
      def persist_atomic_swap(absolute, content, manifest_id, logical_stamp)
        inode_before = inode_fingerprint(absolute)
        track_step(manifest_id, logical_stamp, "inode_before", "fingerprint" => inode_before.inspect)

        parent = File.dirname(absolute)
        FileUtils.mkdir_p(parent)

        temp = nil
        begin
          temp = write_exclusive_temp(parent, File.basename(absolute), content, manifest_id, logical_stamp)
          inode_after = inode_fingerprint(absolute)
          track_inode_after_and_check_swap(inode_before, inode_after, manifest_id, logical_stamp)
          return :inode_swapped if inode_swapped?(inode_before, inode_after)

          preserve_destination_mode_on_temp!(temp, absolute, manifest_id, logical_stamp)

          File.rename(temp, absolute)
          temp = nil
          track_step(manifest_id, logical_stamp, "renamed")

          fsync_parent_directory(manifest_id, logical_stamp, parent)
        ensure
          File.unlink(temp) if temp && File.exist?(temp)
        end

        track_step(manifest_id, logical_stamp, "complete")
        :written
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def track_inode_after_and_check_swap(inode_before, inode_after, manifest_id, logical_stamp)
        track_step(manifest_id, logical_stamp, "inode_after_write", "fingerprint" => inode_after.inspect)
        return unless inode_swapped?(inode_before, inode_after)

        track_step(manifest_id, logical_stamp, "inode_swapped_abort")
      end

      def expand_workspace_path(path)
        File.expand_path(path, @workspace_root)
      end

      def relative_workspace_path(absolute)
        Pathname.new(absolute).relative_path_from(Pathname.new(@workspace_root)).to_s
      end

      def ownership_gate_outcome(node, mode, owner_required, supervisor_lease)
        return :forbidden if node.nil?
        return :forbidden if owner_required && node.owner != owner_required

        decision = CriticalityPolicy.gate(node, mode: mode)
        return :forbidden if decision == :reject
        return :forbidden if decision == :require_supervisor_lease && !supervisor_lease

        nil
      end

      def read_destination_bytes(absolute)
        return nil unless File.exist?(absolute)
        return nil unless File.file?(absolute)

        File.binread(absolute)
      end

      def inode_fingerprint(absolute)
        return nil unless File.exist?(absolute)

        st = File.lstat(absolute)
        [st.dev, st.ino]
      end

      def inode_swapped?(before_fp, after_fp)
        before_fp != after_fp
      end

      def preserve_destination_mode_on_temp!(temp, absolute, manifest_id, logical_stamp)
        return unless File.exist?(absolute) && File.file?(absolute)

        mode_bits = File.stat(absolute).mode & 0o7777
        File.chmod(mode_bits, temp)
        track_step(manifest_id, logical_stamp, "temp_mode_preserved", "mode" => mode_bits)
      end

      def write_exclusive_temp(parent, basename, content, manifest_id, logical_stamp)
        10.times do |attempt|
          candidate = File.join(parent, "#{basename}.#{Process.pid}.#{attempt}#{SecureRandom.hex(4)}.tmp")
          written = try_write_exclusive_temp(candidate, content)
          next unless written

          track_step(manifest_id, logical_stamp, "temp_created", "temp" => candidate)
          track_step(manifest_id, logical_stamp, "temp_fsynced")
          return candidate
        end

        raise Errno::EEXIST, "could not allocate temp file in #{parent}"
      end

      def try_write_exclusive_temp(candidate, content)
        File.open(candidate, File::WRONLY | File::CREAT | File::EXCL | File::BINARY, 0o600) do |io|
          io.write(content.b)
          io.fsync
        end
        true
      rescue Errno::EEXIST
        false
      end

      def fsync_parent_directory(manifest_id, logical_stamp, parent_dir)
        File.open(parent_dir, File::RDONLY, &:fsync)
        track_step(manifest_id, logical_stamp, "parent_fsync", "dir_fsync_status" => "ok")
      rescue Errno::EINVAL, Errno::ENOTSUP, NotImplementedError
        track_step(manifest_id, logical_stamp, "parent_fsync", "dir_fsync_status" => "skipped")
      end

      def track_step(manifest_id, logical_stamp, step, data = {})
        @wal.append_mutation_step(manifest_id: manifest_id, logical_stamp: logical_stamp, step: step,
                                  data: data)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
