# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "fileutils"

module OllamaAgent
  # Probes Ollama Cloud models for accessibility and caches results to
  # ~/.ollama_agent/cloud_model_access.json.
  #
  # A model is "accessible" if a minimal chat request returns 2xx.
  # Cache TTL defaults to 1 hour (OLLAMA_AGENT_CLOUD_PROBE_TTL_SECONDS).
  module CloudAccessibilityCache
    DEFAULT_TTL   = 3600
    PROBE_THREADS = 10
    PROBE_TIMEOUT = 15

    module_function

    def cache_file
      File.join(OllamaAgent.data_dir, "cloud_model_access.json")
    end

    # @return [Set<String>, nil] accessible model names, or nil if no valid cache
    def accessible_names
      data = load_cache
      return nil unless data

      Set.new(data["results"].select { |r| r["accessible"] }.map { |r| r["name"] })
    end

    # @return [Hash, nil] reason strings keyed by name, or nil if no valid cache
    def inaccessibility_reasons
      data = load_cache
      return nil unless data

      data["results"]
        .reject { |r| r["accessible"] }
        .to_h { |r| [r["name"], r["reason"]] }
    end

    # @return [Boolean]
    def fresh?
      data = load_cache
      !data.nil?
    end

    # Probe all cloud models and write cache. Blocking.
    # @param api_key [String]
    # @param base_url [String] e.g. "https://ollama.com"
    # @param model_names [Array<String>] models to probe
    # @param on_progress [Proc, nil] called with (done, total) after each probe
    # @return [Array<Hash>] sorted results
    def probe!(api_key:, base_url:, model_names:, on_progress: nil)
      results  = []
      mutex    = Mutex.new
      total    = model_names.size
      done     = 0

      workers = model_names.each_slice((total.to_f / PROBE_THREADS).ceil).map do |slice|
        Thread.new do
          slice.each do |name|
            sleep(rand * 0.2) # jitter
            result = probe_one(name, api_key: api_key, base_url: base_url)
            mutex.synchronize do
              results << result
              done += 1
              on_progress&.call(done, total)
            end
          end
        end
      end

      workers.each(&:join)

      sorted = results.sort_by { |r| r[:name].to_s }
      write_cache(sorted)
      sorted
    end

    private

    def load_cache
      path = cache_file
      return nil unless File.exist?(path)

      raw  = File.read(path, encoding: Encoding::UTF_8)
      data = JSON.parse(raw)
      ttl  = ENV.fetch("OLLAMA_AGENT_CLOUD_PROBE_TTL_SECONDS", DEFAULT_TTL).to_i
      probed_at = Time.parse(data["probed_at"])
      return nil if Time.now - probed_at > ttl

      data
    rescue StandardError
      nil
    end

    def write_cache(results)
      path = cache_file
      FileUtils.mkdir_p(File.dirname(path))
      payload = {
        "probed_at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "results" => results.map { |r| { "name" => r[:name], "accessible" => r[:accessible], "reason" => r[:reason] } }
      }
      File.write(path, JSON.generate(payload), encoding: Encoding::UTF_8)
    rescue StandardError
      # best-effort
    end

    def probe_one(name, api_key:, base_url:)
      uri = URI("#{base_url.to_s.chomp("/")}/api/chat")
      body = JSON.generate(
        model: name,
        messages: [{ role: "user", content: "ping" }],
        stream: false,
        options: { num_predict: 1 }
      )

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = PROBE_TIMEOUT
      http.read_timeout = PROBE_TIMEOUT

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"]  = "application/json"
      req["Authorization"] = "Bearer #{api_key}" unless api_key.to_s.strip.empty?
      req.body = body

      res = http.request(req)

      case res.code.to_i
      when 200..299
        { name: name, accessible: true, reason: nil }
      when 402
        { name: name, accessible: false, reason: "usage_limit" }
      when 403
        { name: name, accessible: false, reason: "plan_restricted" }
      when 429
        { name: name, accessible: false, reason: "rate_limited" }
      when 401
        { name: name, accessible: false, reason: "unauthorized" }
      else
        { name: name, accessible: false, reason: "http_#{res.code}" }
      end
    rescue Net::OpenTimeout, Net::ReadTimeout
      { name: name, accessible: false, reason: "timeout" }
    rescue StandardError => e
      { name: name, accessible: false, reason: "error:#{e.class}" }
    end

    module_function :load_cache, :write_cache, :probe_one
    private_class_method :load_cache, :write_cache, :probe_one
  end
end
