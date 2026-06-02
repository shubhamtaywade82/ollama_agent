# frozen_string_literal: true

require "digest"
require "json"

require_relative "../security/resource_guard"
require_relative "cas_guard"

module OllamaAgent
  module Runtime
    # Maps Agent tool call payloads to {KernelPipeline} intent hashes (incl. +expected_pre_hash+).
    # rubocop:disable Metrics/ClassLength -- one module per tool family; kept explicit for review
    class IntentTranslator
      TOOL_TO_METHOD = {
        "write_file" => :translate_write_file,
        "edit_file" => :translate_edit_file,
        "apply_patch" => :translate_apply_patch,
        "delete_file" => :translate_delete_file,
        "rename_file" => :translate_rename_file,
        "move_file" => :translate_rename_file
      }.freeze

      def initialize(workspace_root:)
        @root = File.expand_path(workspace_root.to_s)
      end

      # @param tool_call [Hash] keys +name+ / +"name"+ and +arguments+ / +"arguments"+
      # @return [Hash] intent for {KernelPipeline#execute}
      def translate(tool_call:)
        tc = normalize_tool_call(tool_call)
        meth = TOOL_TO_METHOD[tc[:name]]
        raise ArgumentError, "IntentTranslator does not support tool #{tc[:name].inspect}" unless meth

        send(meth, tc[:arguments])
      end

      private

      def normalize_tool_call(tool_call)
        h = tool_call.to_h
        name = (h["name"] || h[:name]).to_s
        args = h["arguments"] || h[:arguments] || {}
        { name: name, arguments: args }
      end

      def translate_write_file(args)
        args = symbolize_arguments(args)
        path = args[:path].to_s
        content = args[:content]
        raise ArgumentError, "write_file requires content" if content.nil?

        expected = file_pre_hash(expand_path(path))
        merge_common(
          { kind: "atomic_write", path: path, content: content.to_s, expected_pre_hash: expected },
          args
        )
      end

      def translate_edit_file(args)
        args = symbolize_arguments(args)
        return translate_apply_patch(args) if args[:diff]

        edits = normalize_edits_from_args(args)
        path = args[:path].to_s
        raise ArgumentError, "edit_file requires path" if path.strip.empty?

        expected = file_pre_hash(expand_path(path))
        merge_common(
          { kind: "edit_file", path: path, edits: edits, expected_pre_hash: expected },
          args
        )
      end

      def translate_apply_patch(args)
        args = symbolize_arguments(args)
        patch, path = patch_and_path_for_apply(args)
        expected = file_pre_hash(expand_path(path))
        merge_common(
          { kind: "apply_patch", path: path, patch: patch.to_s, expected_pre_hash: expected },
          args
        )
      end

      def translate_delete_file(args)
        args = symbolize_arguments(args)
        path = args[:path].to_s
        raise ArgumentError, "delete_file requires path" if path.strip.empty?

        expected = file_pre_hash(expand_path(path))
        merge_common(
          { kind: "delete_file", path: path, expected_pre_hash: expected, scopes: [path] },
          args
        )
      end

      def translate_rename_file(args)
        args = symbolize_arguments(args)
        from_path, to_path = rename_endpoints(args)
        assert_rename_paths!(from_path, to_path)

        expected = file_pre_hash(expand_path(from_path))
        scopes = [from_path, to_path].sort
        merge_common(
          { kind: "rename_file", from_path: from_path, to_path: to_path, expected_pre_hash: expected,
            scopes: scopes },
          args
        )
      end

      def assert_rename_paths!(from_path, to_path)
        raise ArgumentError, "rename_file requires from and to paths" if from_path.strip.empty? || to_path.strip.empty?
      end

      def rename_endpoints(args)
        from = args[:from] || args[:from_path] || args[:old_path]
        to = args[:to] || args[:to_path] || args[:new_path]
        [from.to_s, to.to_s]
      end

      def patch_and_path_for_apply(args)
        patch = args[:patch] || args[:diff]
        raise ArgumentError, "apply_patch requires patch" if patch.nil? || patch.to_s.strip.empty?

        path = args[:path]&.to_s
        path = parse_path_from_patch(patch) if path.nil? || path.strip.empty?
        [patch, path]
      end

      def normalize_edits_from_args(args)
        return args[:edits].map { |e| normalize_edit_pair(e) } if args[:edits].is_a?(Array)
        return [{ search: args[:search].to_s, replace: args[:replace].to_s }] if args.key?(:search) && args.key?(:replace)

        raise ArgumentError, "edit_file requires diff, edits[], or search+replace"
      end

      def normalize_edit_pair(entry)
        e = symbolize_arguments(entry)
        {
          search: e.fetch(:search).to_s,
          replace: e.fetch(:replace).to_s
        }
      end

      def parse_path_from_patch(patch)
        patch.to_s.each_line do |line|
          line = line.chomp
          if (m = line.match(%r{\Adiff --git a/(.+?) b/(.+)}))
            return m[1].strip
          end

          next unless (m = line.match(%r{\A--- a/(.+)}))

          next if m[1].start_with?(File::NULL)

          return m[1].strip
        end
        raise ArgumentError, "apply_patch: could not parse path from patch headers"
      end

      def expand_path(path)
        File.expand_path(path.to_s, @root)
      end

      def file_pre_hash(absolute_path)
        guard = Security::ResourceGuard.new(root: @root)
        return CASGuard::NEW_FILE_SENTINEL unless guard.allow?(absolute_path)
        return CASGuard::NEW_FILE_SENTINEL unless File.file?(absolute_path)

        Digest::SHA256.hexdigest(File.binread(absolute_path).b)
      end

      def merge_common(intent, args)
        intent.merge(
          owner_required: args[:owner_required],
          post_conditions: Array(args[:post_conditions]),
          scopes: scopes_for_merge(intent, args)
        )
      end

      def scopes_for_merge(intent, args)
        arg_scopes = args[:scopes]
        return arg_scopes if arg_scopes.is_a?(Array) && !arg_scopes.empty?

        Array(intent[:scopes])
      end

      def symbolize_arguments(hash)
        hash.to_h.transform_keys { |k| k.respond_to?(:to_sym) ? k.to_sym : k }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
