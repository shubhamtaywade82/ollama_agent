# frozen_string_literal: true

require_relative "base"

module OllamaAgent
  module Tools
    # Safe filesystem inspection tool.
    #
    # Lists files and subdirectories inside the current workspace.
    # All path arguments are resolved relative to the project root and
    # rejected if they escape it, preventing directory traversal attacks.
    class FilesystemExplorer < Base
      tool_name        "list_directory_contents"
      tool_description "Inspect files and folders inside the current workspace. " \
                       "Use this to see what actually exists before answering questions about local files."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      path: {
                        type: "string",
                        description: "Relative path inside the workspace, e.g. '.', 'lib', or 'spec/unit'. " \
                                     "Defaults to the workspace root."
                      }
                    },
                    required: []
                  })

      def call(args, context: {})
        root     = context[:root] || ENV.fetch("OLLAMA_AGENT_ROOT", Dir.pwd)
        base_dir = File.expand_path(root)
        path     = args["path"].to_s
        path     = "." if path.strip.empty?

        requested = File.expand_path(path, base_dir)

        return access_denied(path, base_dir) unless allowed_path?(base_dir, requested)
        return "Error: Path #{path.inspect} does not exist." unless File.exist?(requested)
        return "Error: Path #{path.inspect} is not a directory." unless File.directory?(requested)

        entries = Dir.children(requested).sort
        return "The directory #{path.inspect} is empty." if entries.empty?

        lines = ["Contents of #{path.inspect} (#{entries.size} item(s)):"]
        entries.each do |name|
          full = File.join(requested, name)
          if File.directory?(full)
            lines << "  [DIR]  #{name}/"
          else
            size = (File.size(full) rescue nil)
            lines << (size ? "  [FILE] #{name} (#{size} bytes)" : "  [FILE] #{name}")
          end
        end

        lines.join("\n")
      rescue StandardError => e
        "Error: #{e.message}"
      end

      private

      def allowed_path?(base_dir, requested)
        requested == base_dir || requested.start_with?(base_dir + File::SEPARATOR)
      end

      def access_denied(path, base_dir)
        "Error: Access denied. The path #{path.inspect} resolves outside the " \
          "permitted workspace (#{base_dir})."
      end
    end
  end
end
