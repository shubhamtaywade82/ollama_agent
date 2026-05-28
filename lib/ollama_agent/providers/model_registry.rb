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
                caps = [:chat]
                caps << :tools if name.include?("qwen") || name.include?("llama3") || name.include?("mistral")
                caps << :reasoning if name.include?("deepseek-r1")
                list << ModelDescriptor.new(
                  name: name,
                  provider: "local",
                  context_size: name.include?("qwen2.5-coder") ? 128_000 : 32_768,
                  capabilities: caps,
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

              caps = [:chat]
              caps << :tools if name.include?("qwen") || name.include?("llama") || name.include?("mistral")
              caps << :reasoning if name.include?("deepseek-r1")

              # Heuristic: models with -pro suffix or very large parameter sizes (inferred from name)
              # or known Level 4 models often require a subscription.
              sub = name.downcase.include?("-pro") ||
                    name.downcase.include?(":671b") ||
                    name.downcase.include?(":1t") ||
                    name.downcase.include?(":405b")

              list << ModelDescriptor.new(
                name: name,
                provider: "ollama_cloud",
                context_size: 128_000,
                capabilities: caps,
                status: "available",
                subscription_required: sub
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

          caps = [:chat]
          family = details["family"].to_s.downcase
          caps << :tools if m_name.include?("qwen") || m_name.include?("llama3") || m_name.include?("mistral")
          caps << :vision if family.include?("mllm") || m_name.include?("llava") || m_name.include?("vision")
          caps << :reasoning if m_name.include?("deepseek-r1")

          status = loaded_names.include?(m_name) ? "loaded" : "unloaded"

          ModelDescriptor.new(
            name: m_name,
            provider: "local",
            context_size: m_name.include?("qwen2.5-coder") ? 128_000 : 32_768,
            capabilities: caps,
            size_gb: size_gb,
            status: status
          )
        end
      rescue StandardError
        []
      end
    end
  end
end
