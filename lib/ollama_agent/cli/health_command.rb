# frozen_string_literal: true

require "json"
require "thor"

module OllamaAgent
  class CLI
    # Thor subcommand group: +ollama_agent kernel health+.
    class KernelHealthCommand < Thor
      namespace "kernel"

      desc "health", "Print kernel health JSON (exit 1 unless status is ok)"
      method_option :root, type: :string, desc: "Project root (default OLLAMA_AGENT_ROOT or cwd)"
      def health
        root = expanded_root
        registry = Runtime::DatabaseRegistry.new(root_dir: root)
        blobs = Runtime::BlobStore.new(kernel_dir: registry.kernel_dir)
        payload = Runtime::KernelHealth.new(db_registry: registry, blob_store: blobs).check
        puts JSON.generate(symbolize_for_json(payload))
        exit(payload[:status] == :ok ? 0 : 1)
      end

      private

      def expanded_root
        raw = options[:root] || ENV.fetch("OLLAMA_AGENT_ROOT", nil)
        base = raw.to_s.strip.empty? ? Dir.pwd : raw
        File.expand_path(base)
      end

      def symbolize_for_json(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(k, v), acc|
            acc[k.to_s] = symbolize_for_json(v)
          end
        when Array
          obj.map { symbolize_for_json(_1) }
        else
          obj.is_a?(Symbol) ? obj.to_s : obj
        end
      end
    end
  end
end
