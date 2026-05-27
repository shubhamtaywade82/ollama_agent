# frozen_string_literal: true

require "fileutils"
require "securerandom"

module OllamaAgent
  module Runtime
    # Internal helper: binary temp write → fsync → rename → parent fsync (no WAL / ownership).
    module FileAtomicSwap
      class << self
        def write_bytes!(absolute_path, content)
          bytes = content.b
          parent = File.dirname(absolute_path)
          FileUtils.mkdir_p(parent)
          swap_bytes_into_path!(absolute_path, parent, File.basename(absolute_path), bytes)
        end

        private

        def swap_bytes_into_path!(absolute_path, parent, basename, bytes)
          temp = nil
          begin
            temp = allocate_temp!(parent, basename)
            commit_temp_to_path!(temp, absolute_path, parent, bytes)
            temp = nil
          ensure
            File.unlink(temp) if temp && File.exist?(temp)
          end
        end

        def commit_temp_to_path!(temp, absolute_path, parent, bytes)
          write_and_fsync_temp!(temp, bytes)
          preserve_destination_mode_on_temp!(temp, absolute_path)
          File.rename(temp, absolute_path)
          fsync_parent_best_effort(parent)
        end

        def allocate_temp!(parent, basename)
          10.times do |attempt|
            candidate = File.join(parent, ".#{basename}.#{Process.pid}.#{attempt}#{SecureRandom.hex(4)}.tmp")
            return candidate if try_exclusive_create(candidate)
          end

          raise Errno::EEXIST, "could not allocate temp in #{parent}"
        end

        def write_and_fsync_temp!(temp, bytes)
          File.open(temp, File::WRONLY | File::BINARY) do |io|
            io.write(bytes)
            io.fsync
          end
        end

        def try_exclusive_create(candidate)
          File.open(candidate, File::WRONLY | File::CREAT | File::EXCL | File::BINARY, 0o600, &:close)
          true
        rescue Errno::EEXIST
          false
        end

        def preserve_destination_mode_on_temp!(temp, absolute_path)
          return unless File.exist?(absolute_path) && File.file?(absolute_path)

          mode_bits = File.stat(absolute_path).mode & 0o7777
          File.chmod(mode_bits, temp)
        end

        def fsync_parent_best_effort(parent_dir)
          File.open(parent_dir, File::RDONLY, &:fsync)
        rescue Errno::EINVAL, Errno::ENOTSUP, NotImplementedError
          nil
        end
      end
    end
  end
end
