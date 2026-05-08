# frozen_string_literal: true

module OllamaAgent
  module LLM
    # Cloud escalation with deterministic depth / cost / wall-clock circuit breakers.
    #
    # The +clock_provider+ default uses +Time.now.to_i+ **only** for breaker accounting (cost/time
    # caps). Do **not** use this clock for saga orchestration stamps, kernel leases, or logical epochs.
    class CloudFallbackRouter
      # Approximate public list pricing for +claude-opus-4-7+ (USD per million tokens).
      # Replace with live billing data when available.
      OPUS_47_INPUT_USD_PER_MILLION = 15.0
      OPUS_47_OUTPUT_USD_PER_MILLION = 75.0

      attr_reader :reentry_packet_builder

      # rubocop:disable Metrics/ParameterLists -- explicit breaker + client configuration
      def initialize(
        anthropic_client:,
        reentry_packet_builder:,
        max_escalation_depth: 1,
        cost_cap_usd: 5.00,
        time_cap_seconds: 600,
        clock_provider: -> { Time.now.to_i }
      )
        @client = anthropic_client
        @reentry_packet_builder = reentry_packet_builder
        @max_escalation_depth = Integer(max_escalation_depth)
        @cost_cap_usd = cost_cap_usd.to_f
        @time_cap_seconds = Integer(time_cap_seconds)
        @clock = clock_provider
      end
      # rubocop:enable Metrics/ParameterLists

      # @return [Hash] +:result+, +:depth+, +:cost_usd+, +:halted_reason+
      def escalate(packet:, depth:, accumulated_cost_usd:, started_at:)
        halted = breaker_halt(depth, accumulated_cost_usd.to_f, started_at)
        return halted if halted

        invoke_anthropic(packet, Integer(depth), accumulated_cost_usd.to_f)
      end

      private

      def breaker_halt(depth, cost, started_at)
        return breaker(:depth_limit_exceeded, "max_escalation_depth", depth, cost) if depth >= @max_escalation_depth
        return breaker(:cost_cap_exceeded, "cost_cap", depth, cost) if cost >= @cost_cap_usd
        return breaker(:time_cap_exceeded, "time_cap", depth, cost) if timed_out?(started_at)

        nil
      end

      def invoke_anthropic(packet, depth, cost)
        messages = [{ "role" => "user", "content" => packet.to_h.to_json }]
        response = @client.chat(messages: messages)
        delta = usage_cost_usd(response[:usage])
        {
          result: response[:content],
          depth: depth + 1,
          cost_usd: cost + delta,
          halted_reason: nil
        }
      end

      def timed_out?(started_at)
        @clock.call.to_i - Integer(started_at) >= @time_cap_seconds
      end

      def breaker(result, reason, depth, cost)
        { result: result, depth: depth, cost_usd: cost, halted_reason: reason }
      end

      def usage_cost_usd(usage)
        u = usage || {}
        in_tok = (u[:input_tokens] || u["input_tokens"]).to_i
        out_tok = (u[:output_tokens] || u["output_tokens"]).to_i
        in_cost = (in_tok / 1_000_000.0) * OPUS_47_INPUT_USD_PER_MILLION
        out_cost = (out_tok / 1_000_000.0) * OPUS_47_OUTPUT_USD_PER_MILLION
        in_cost + out_cost
      end
    end
  end
end
