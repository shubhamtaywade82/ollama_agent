# frozen_string_literal: true

module OllamaAgent
  module TieredAgent
    # Builds Ollama inference options that force VRAM eviction between model loads.
    #
    # Setting keep_alive to a short window instructs the Ollama daemon to unload
    # the model from GPU memory shortly after the request completes, making room
    # for the next tier to load without OOM collisions.
    module VramOptions
      DEFAULT_KEEP_ALIVE  = "10s"
      DEFAULT_NUM_CTX     = 4096
      DEFAULT_TEMPERATURE = 0.0

      # @param keep_alive  [String]  Ollama keep_alive value ("0", "10s", "30s", etc.)
      # @param num_ctx     [Integer] hard context window cap — limits KV cache growth
      # @param temperature [Float]   sampling temperature; 0.0 = deterministic
      # @return [Hash] options hash suitable for the Ollama API `options` field
      def self.build(keep_alive: DEFAULT_KEEP_ALIVE, num_ctx: DEFAULT_NUM_CTX,
                     temperature: DEFAULT_TEMPERATURE)
        {
          "keep_alive" => keep_alive,
          "num_ctx" => num_ctx,
          "temperature" => temperature
        }
      end
    end
  end
end
