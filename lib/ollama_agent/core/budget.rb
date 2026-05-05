# frozen_string_literal: true

module OllamaAgent
  module Core
    # Tracks and enforces token, step, and cost budgets for an agent run.
    # Instantiate once per run; call #record_step! after each model round-trip.
    class Budget
      DEFAULT_MAX_STEPS     = 64
      DEFAULT_MAX_TOKENS    = 32_768
      DEFAULT_MAX_COST_USD  = nil

      attr_reader :steps, :tokens_used, :cost_usd,
                  :max_steps, :max_tokens, :max_cost_usd

      def initialize(max_steps: nil, max_tokens: nil, max_cost_usd: nil)
        @max_steps    = max_steps    || env_int("OLLAMA_AGENT_MAX_TURNS", DEFAULT_MAX_STEPS)
        @max_tokens   = max_tokens   || env_int("OLLAMA_AGENT_MAX_TOKENS", DEFAULT_MAX_TOKENS)
        @max_cost_usd = max_cost_usd || env_float("OLLAMA_AGENT_MAX_COST_USD", DEFAULT_MAX_COST_USD)

        reset!
      end

      # Record one agent step. Call after each model response.
      # @param tokens [Integer] tokens consumed in this step (prompt + completion)
      # @param cost_usd [Float] estimated cost in USD (0.0 for local models)
      def record_step!(tokens: 0, cost_usd: 0.0)
        @steps       += 1
        @tokens_used += tokens.to_i
        @cost_usd    += cost_usd.to_f
        nil
      end

      def steps_exceeded?   = @steps >= @max_steps
      def tokens_exceeded?  = @tokens_used >= @max_tokens
      def cost_exceeded?    = !@max_cost_usd.nil? && @cost_usd >= @max_cost_usd

      # True when any limit has been hit.
      def exceeded?
        steps_exceeded? || tokens_exceeded? || cost_exceeded?
      end

      # Human-readable reason for the first exceeded limit, or nil if none.
      def exceeded_reason
        return "step limit (#{@max_steps})" if steps_exceeded?
        return "token limit (#{@max_tokens})"       if tokens_exceeded?
        return "cost limit ($#{@max_cost_usd})"     if cost_exceeded?

        nil
      end

      def reset!
        @steps       = 0
        @tokens_used = 0
        @cost_usd    = 0.0
      end

      def to_h
        {
          steps: @steps, max_steps: @max_steps,
          tokens_used: @tokens_used, max_tokens: @max_tokens,
          cost_usd: @cost_usd, max_cost_usd: @max_cost_usd
        }
      end

      def remaining_steps
        [@max_steps - @steps, 0].max
      end

      private

      def env_int(key, default)
        v = ENV.fetch(key, nil)
        return default if v.nil? || v.strip.empty?

        Integer(v)
      rescue ArgumentError, TypeError
        default
      end

      def env_float(key, default)
        v = ENV.fetch(key, nil)
        return default if v.nil? || v.strip.empty?

        Float(v)
      rescue ArgumentError, TypeError
        default
      end
    end
  end
end
