# frozen_string_literal: true

module OllamaAgent
  class ModelManager
    attr_reader :model

    def initialize(client:, default_model:)
      @client = client
      @model = default_model
    end

    def assign_chat_model!(name)
      n = name.to_s.strip
      raise EmptyModelNameError, "Model name cannot be empty" if n.empty?

      @model = n
      n
    end

    def model_accessible?(name = nil)
      n = name || @model
      return true unless @client.respond_to?(:cloud?) && @client.cloud?
      return true unless @client.respond_to?(:subscription_required?)

      !@client.subscription_required?(n)
    rescue StandardError
      true
    end

    def list_local_model_names
      return [] unless @client.respond_to?(:list_model_names)

      @client.list_model_names
    rescue StandardError
      []
    end

    def list_cloud_model_names
      base_url = nil
      api_key = nil

      if @client.respond_to?(:client) && @client.client.respond_to?(:config)
        config = @client.client.config
        base_url = config.base_url
        api_key = config.api_key
      end

      base_url ||= ENV.fetch("OLLAMA_BASE_URL", nil)
      catalog_host = base_url ? "#{base_url.to_s.chomp("/")}/api/tags" : nil
      OllamaCloudCatalog.list_model_names(base_url: catalog_host, api_key: api_key)
    end
  end
end