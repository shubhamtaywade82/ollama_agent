# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "session"

module OllamaAgent
  module Session
    # NDJSON-based session persistence under <root>/.ollama_agent/sessions/.
    # Each call to .save appends one JSON line — crash-safe by design.
    module Store
      module_function

      def sessions_dir(root)
        File.join(root, ".ollama_agent", "sessions")
      end

      # Append one message to a session file.
      def save(session_id:, root:, message:)
        dir = sessions_dir(root)
        FileUtils.mkdir_p(dir)
        path = session_path(dir, session_id)
        File.open(path, "a", encoding: Encoding::UTF_8) do |f|
          f.puts(JSON.generate(message.transform_keys(&:to_s)))
        end
      rescue StandardError
        nil # best-effort; never crash the agent
      end

      # Load all saved messages for a session.
      def load(session_id:, root:)
        path = session_path(sessions_dir(root), session_id)
        return [] unless File.file?(path)

        File.readlines(path, encoding: Encoding::UTF_8)
            .map(&:chomp)
            .reject(&:empty?)
            .map { |line| JSON.parse(line) }
      rescue StandardError
        []
      end

      # Load messages ready to seed Agent#run.
      def resume(session_id:, root:)
        load(session_id: session_id, root: root)
      end

      # List sessions for a root, newest first.
      def list(root:)
        dir = sessions_dir(root)
        return [] unless Dir.exist?(dir)

        Dir.glob(File.join(dir, "*.ndjson"))
           .sort_by { |f| -File.mtime(f).to_f }
           .map do |path|
             id    = File.basename(path, ".ndjson")
             mtime = File.mtime(path).utc.strftime("%Y-%m-%dT%H:%M:%SZ")
             SessionMeta.new(session_id: id, path: path, started_at: mtime)
           end
      end

      def session_path(dir, session_id)
        safe_id = session_id.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")
        File.join(dir, "#{safe_id}.ndjson")
      end
    end
  end
end
