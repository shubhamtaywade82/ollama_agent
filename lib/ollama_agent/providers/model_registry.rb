# frozen_string_literal: true

require_relative "model_descriptor"

module OllamaAgent
  module Providers
    module ModelRegistry
      KNOWN_MODELS = [
        # OpenAI
        ModelDescriptor.new(name: "gpt-4o", provider: "openai", context_size: 128_000, capabilities: [:chat, :tools, :vision], status: "available"),
        ModelDescriptor.new(name: "gpt-4o-mini", provider: "openai", context_size: 128_000, capabilities: [:chat, :tools, :vision], status: "available"),
        ModelDescriptor.new(name: "o1-mini", provider: "openai", context_size: 128_000, capabilities: [:chat, :tools, :reasoning], status: "available"),
        
        # Anthropic
        ModelDescriptor.new(name: "claude-3-5-sonnet-latest", provider: "anthropic", context_size: 200_000, capabilities: [:chat, :tools, :vision], status: "available"),
        ModelDescriptor.new(name: "claude-3-5-haiku-latest", provider: "anthropic", context_size: 200_000, capabilities: [:chat, :tools], status: "available"),
        
        # Groq
        ModelDescriptor.new(name: "llama-3.3-70b-versatile", provider: "groq", context_size: 128_000, capabilities: [:chat, :tools], status: "available"),
        ModelDescriptor.new(name: "mixtral-8x7b-32768", provider: "groq", context_size: 32_768, capabilities: [:chat, :tools], status: "available"),
        
        # OpenRouter
        ModelDescriptor.new(name: "deepseek-r1", provider: "openrouter", context_size: 163_840, capabilities: [:chat, :reasoning], status: "available")
      ].freeze

      module_function

      # List all known and dynamic models.
      # @param agent [Agent, nil]
      # @return [Array<ModelDescriptor>]
      def all(agent: nil)
        list = KNOWN_MODELS.dup

        if agent
          # Resolve local host from agent or environment
          host = ENV.fetch("OLLAMA_HOST", "http://localhost:11434")
          local_models = fetch_local_models(host)
          if local_models.empty?
            begin
              agent.list_local_model_names.each do |name|
                list << ModelDescriptor.new(
                  name: name,
                  provider: "local",
                  context_size: name.include?("qwen2.5-coder") ? 128_000 : 32_768,
                  capabilities: infer_capabilities(name),
                  status: "loaded"
                )
              end
            rescue StandardError
            end
          else
            list.concat(local_models)
          end

          # Fetch cloud models
          begin
            cloud_names = agent.list_cloud_model_names
            cloud_names.each do |name|
              # Avoid duplicating if already present
              next if list.any? { |m| m.name == name }

              list << ModelDescriptor.new(
                name: name,
                provider: "ollama_cloud",
                context_size: 128_000,
                capabilities: infer_capabilities(name),
                status: "available",
                subscription_required: subscription_required?(name)
              )
            end
          rescue StandardError
            # Silently ignore cloud fetch errors
          end
        end

        list.uniq(&:name)
      end

      # Find a model descriptor by name.
      # @param name [String]
      # @param agent [Agent, nil]
      # @return [ModelDescriptor, nil]
      def find(name, agent: nil)
        all(agent: agent).find { |m| m.name.to_s.casecmp(name.to_s).zero? }
      end

      # Fetch local models directly from Ollama tags & ps API.
      def fetch_local_models(host)
        require "net/http"
        require "json"

        # Normalize host URL
        base_url = host.to_s.strip
        base_url = "http://#{base_url}" unless base_url.start_with?("http://", "https://")
        base_url = base_url.chomp("/")

        # 1. Fetch tags
        uri = URI("#{base_url}/api/tags")
        req = Net::HTTP::Get.new(uri)
        res = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 3) { |h| h.request(req) }
        return [] unless res.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(res.body)
        models = parsed["models"] || []

        # 2. Fetch loaded models (ps)
        ps_uri = URI("#{base_url}/api/ps")
        ps_req = Net::HTTP::Get.new(ps_uri)
        ps_res = Net::HTTP.start(ps_uri.host, ps_uri.port, open_timeout: 2, read_timeout: 3) { |h| h.request(ps_req) }
        loaded_names = []
        if ps_res.is_a?(Net::HTTPSuccess)
          ps_parsed = JSON.parse(ps_res.body)
          loaded_names = (ps_parsed["models"] || []).map { |m| m["name"] }
        end

        models.map do |m|
          m_name = m["name"]
          details = m["details"] || {}
          size_bytes = m["size"] || 0
          size_gb = (size_bytes.to_f / 1_073_741_824).round(2)

          status = loaded_names.include?(m_name) ? "loaded" : "unloaded"

          ModelDescriptor.new(
            name: m_name,
            provider: "local",
            context_size: m_name.include?("qwen2.5-coder") ? 128_000 : 32_768,
            capabilities: infer_capabilities(m_name, details),
            size_gb: size_gb,
            status: status
          )
        end
      rescue StandardError
        []
      end

      def infer_capabilities(name, details = {})
        name = name.to_s.downcase
        caps = [:chat]

        # Tool calling capabilities
        if name.include?("qwen") || name.include?("llama") || name.include?("mistral") ||
           name.include?("mixtral") || name.include?("kimi") || name.include?("deepseek") ||
           name.include?("command-r") || name.include?("firefunction") || name.include?("hermes")
          caps << :tools
        end

        # Vision capabilities
        family = details["family"].to_s.downcase
        families = Array(details["families"]).map(&:to_s).map(&:downcase)
        if family.include?("mllm") || families.any? { |f| f.include?("mllm") } ||
           name.include?("llava") || name.include?("vision") || name.include?("moondream")
          caps << :vision
        end

        # Reasoning capabilities
        if name.include?("deepseek-r1") || name.include?("thinking") ||
           name.include?("reasoning") || name.match?(/\bo1\b/) || name.match?(/\bo3\b/)
          caps << :reasoning
        end

        caps.uniq
      end

      def subscription_required?(name)
        name = name.to_s.downcase
        # Heuristic: models with -pro suffix or very large parameter sizes (inferred from name)
        # or known high-end models often require a subscription on Ollama Cloud.
        name.include?("-pro") ||
          name.match?(/(?::|-)67[0-9]b/) || # 671b, 675b
          name.include?(":1t") ||
          name.include?(":405b") ||
          name.include?("mistral-large") ||
          name.include?("o1-") ||
          name.include?("o3-")
      end

      private_class_method :infer_capabilities, :subscription_required?
    end
  end
end
