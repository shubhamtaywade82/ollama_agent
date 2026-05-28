# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module OllamaAgent
  # Fetches the public Ollama cloud model catalog (+/api/tags+ on ollama.com).
  #
  # See https://docs.ollama.com/cloud — list models with +curl https://ollama.com/api/tags+.
  # Optional +OLLAMA_API_KEY+ is sent as +Authorization: Bearer+ when set.
  module OllamaCloudCatalog
    DEFAULT_TAGS_URL = "https://ollama.com/api/tags"

    module_function

    # @param base_url [String, nil] override catalog host (default +ollama.com+ or +OLLAMA_AGENT_CLOUD_CATALOG_URL+)
    # @param api_key [String, nil] Bearer token (default +ENV["OLLAMA_API_KEY"]+)
    # @return [Array<String>] sorted unique model names, or empty on failure
    def list_model_names(base_url: nil, api_key: nil, open_timeout: 5, read_timeout: 20)
      uri = catalog_uri(base_url)
      return [] unless uri

      key = api_key_string(api_key)
      all_names = []
      page = 1
      max_pages = 10 # Safety limit

      loop do
        page_uri = uri.dup
        query = URI.decode_www_form(page_uri.query || "") << ["page", page]
        page_uri.query = URI.encode_www_form(query)

        res = http_get(page_uri, api_key: key, open_timeout: open_timeout, read_timeout: read_timeout)
        break unless res.is_a?(Net::HTTPSuccess)

        names = names_from_tags_json(res.body)
        break if names.empty? || (names - all_names).empty? # Stop if no new names

        all_names.concat(names)
        break if names.size < 10 # Heuristic: if less than full page (assuming page size > 10)
        
        page += 1
        break if page > max_pages
      end

      all_names.uniq.sort
    rescue StandardError
      all_names.uniq.sort
    end

    # @param body [String] raw JSON from +/api/tags+
    # @return [Array<String>]
    def names_from_tags_json(body)
      parsed = JSON.parse(body.to_s)
      models = parsed["models"] || []
      models.filter_map { |m| m["name"] }.uniq.sort
    end

    def catalog_uri(base_url)
      raw = base_url || ENV.fetch("OLLAMA_AGENT_CLOUD_CATALOG_URL", nil)
      raw = DEFAULT_TAGS_URL if raw.nil? || raw.to_s.strip.empty?
      URI(raw.to_s.strip)
    rescue URI::InvalidURIError
      nil
    end

    def api_key_string(api_key)
      k = api_key || ENV.fetch("OLLAMA_API_KEY", nil)
      k.to_s.strip
    end

    def http_get(uri, api_key:, open_timeout:, read_timeout:)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout

      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{api_key}" unless api_key.empty?

      http.request(req)
    end
  end
end
