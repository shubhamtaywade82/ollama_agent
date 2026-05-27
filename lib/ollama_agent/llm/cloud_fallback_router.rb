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
        cost_ledger: nil,
        max_escalation_depth: 1,
        cost_cap_usd: 5.00,
        time_cap_seconds: 600,
        clock_provider: -> { Time.now.to_i }
      )
        @client = anthropic_client
        @reentry_packet_builder = reentry_packet_builder
        @cost_ledger = cost_ledger
        @max_escalation_depth = Integer(max_escalation_depth)
        @cost_cap_usd = cost_cap_usd.to_f
        @time_cap_seconds = Integer(time_cap_seconds)
        @clock = clock_provider
      end
      # rubocop:enable Metrics/ParameterLists

      # @return [Hash] +:result+, +:depth+, +:cost_usd+, +:halted_reason+
      def escalate(packet:, depth:, accumulated_cost_usd:, started_at:, manifest_id: nil)
        mid = (manifest_id || packet.workspace_fingerprint).to_s
        prior_cost = resolved_prior_cost(mid, accumulated_cost_usd.to_f)
        halted = breaker_halt(depth, prior_cost, started_at)
        return halted if halted

        invoke_anthropic(packet, Integer(depth), prior_cost, mid)
      end

      private

      def resolved_prior_cost(manifest_id, accumulated_cost_usd)
        return accumulated_cost_usd unless @cost_ledger

        @cost_ledger.total_for_manifest(manifest_id: manifest_id)
      end

      def breaker_halt(depth, cost, started_at)
        return breaker(:depth_limit_exceeded, "max_escalation_depth", depth, cost) if depth >= @max_escalation_depth
        return breaker(:cost_cap_exceeded, "cost_cap", depth, cost) if cost >= @cost_cap_usd
        return breaker(:time_cap_exceeded, "time_cap", depth, cost) if timed_out?(started_at)

        nil
      end

      def invoke_anthropic(packet, depth, prior_cost, manifest_id)
        response = @client.chat(messages: anthropic_messages(packet))
        delta = usage_cost_usd(response[:usage])
        record_cost_if_needed!(manifest_id: manifest_id, response: response, cost_usd: delta)
        escalation_result(response, depth, prior_cost, delta, manifest_id)
      end

      def anthropic_messages(packet)
        [{ "role" => "user", "content" => packet.to_h.to_json }]
      end

      def escalation_result(response, depth, prior_cost, delta, manifest_id)
        total = @cost_ledger ? @cost_ledger.total_for_manifest(manifest_id: manifest_id) : prior_cost + delta
        { result: response[:content], depth: depth + 1, cost_usd: total, halted_reason: nil }
      end

      def record_cost_if_needed!(manifest_id:, response:, cost_usd:)
        return unless @cost_ledger

        u = response[:usage] || {}
        @cost_ledger.record(
          manifest_id: manifest_id,
          model: @client.model,
          input_tokens: (u[:input_tokens] || u["input_tokens"]).to_i,
          output_tokens: (u[:output_tokens] || u["output_tokens"]).to_i,
          cost_usd: cost_usd,
          current_epoch: @clock.call.to_i
        )
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
