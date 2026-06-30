# frozen_string_literal: true

require "fileutils"
require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    class CopyFile < Base
      tool_name        "copy_file"
      tool_description "Copy a file within the sandbox. Useful for backup-before-edit workflows."
      tool_risk        :low
      tool_requires_approval false
      tool_read_only_safe false
      tool_schema({
                    type: "object",
                    properties: {
                      src: { type: "string", description: "Source file path relative to project root" },
                      dest: { type: "string", description: "Destination file path relative to project root" }
                    },
                    required: %w[src dest]
                  })

      def call(args, context: {})
        root = context[:root] || Dir.pwd
        src  = File.expand_path(args["src"], root)
        dest = File.expand_path(args["dest"], root)
        return "Error: source does not exist" unless File.exist?(src)

        FileUtils.cp(src, dest)
        "Copied: #{args["src"]} -> #{args["dest"]}"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end

    class DeleteFile < Base
      tool_name        "delete_file"
      tool_description "Move a file to .trash/ inside the sandbox instead of hard-deleting. Enables undo."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      path: { type: "string", description: "File path relative to project root" }
                    },
                    required: ["path"]
                  })

      def call(args, context: {})
        return "delete_file is disabled in read-only mode" if context[:read_only]

        root  = File.expand_path(context[:root] || Dir.pwd)
        path  = File.expand_path(args["path"], root)
        return "Error: path does not exist" unless File.exist?(path)

        trash = File.join(root, ".trash", Time.now.to_i.to_s)
        FileUtils.mkdir_p(trash)
        FileUtils.mv(path, trash)
        "Trashed: #{args["path"]}"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end

    class MoveFile < Base
      tool_name        "move_file"
      tool_description "Rename or move a file within the sandbox. Uses git mv if inside a git repo."
      tool_risk        :medium
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      src: { type: "string", description: "Source path" },
                      dest: { type: "string", description: "Destination path" }
                    },
                    required: %w[src dest]
                  })

      def call(args, context: {})
        return "move_file is disabled in read-only mode" if context[:read_only]

        root = context[:root] || Dir.pwd
        src  = File.expand_path(args["src"], root)
        dest = File.expand_path(args["dest"], root)
        return "Error: source does not exist" unless File.exist?(src)

        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.mv(src, dest)
        "Moved: #{args["src"]} -> #{args["dest"]}"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end

    EnhancedRegistry.register(CopyFile)
    EnhancedRegistry.register(DeleteFile)
    EnhancedRegistry.register(MoveFile)
  end
end
