# frozen_string_literal: true

module OllamaAgent
  module Providers
    # Aggregates health events emitted by the CredentialRouter and exposes
    # a live snapshot consumed by the TUI providers dashboard.
    #
    # Also emits :on_provider_switch and :on_credential_disabled events through
    # the agent's Streaming::Hooks bus when a hooks instance is injected.
    #
    # @example
    #   monitor = HealthMonitor.new(max_events: 50)
    #   monitor.record_success(credential, latency_ms: 240)
    #   monitor.record_failure(credential, OllamaAgent::RateLimitError.new("429"))
    #   monitor.routing_decisions(5)
    #   # => ["openai/key-1 → success (240ms)", "openai/key-1 → failure RateLimitError"]
    class HealthMonitor
      # Immutable event record
      Event = Data.define(
        :at, :credential_id, :provider,
        :kind,        # :success | :failure
        :error_class, # String class name or nil
        :latency_ms   # Integer or nil
      )

      def initialize(max_events: 100, hooks: nil)
        @max_events = max_events
        @hooks      = hooks
        @events     = []
        @mutex      = Mutex.new
      end

      # Record a successful response.
      # @param credential [Credential]
      # @param latency_ms [Integer, nil]
      def record_success(credential, latency_ms: nil)
        push Event.new(
          at: Time.now,
          credential_id: credential.id,
          provider: credential.provider,
          kind: :success,
          error_class: nil,
          latency_ms: latency_ms
        )
      end

      # Record a failed attempt.
      # @param credential [Credential]
      # @param error      [StandardError]
      def record_failure(credential, error)
        push Event.new(
          at: Time.now,
          credential_id: credential.id,
          provider: credential.provider,
          kind: :failure,
          error_class: error.class.name,
          latency_ms: nil
        )

        emit_hook(:on_credential_failure, credential, error) if error.is_a?(OllamaAgent::AuthenticationError)
      end

      # Record a provider switch (credential failover).
      # @param from [Credential]
      # @param to   [Credential]
      # @param reason [String]
      def record_switch(from, to, reason)
        push Event.new(
          at: Time.now,
          credential_id: "#{from.id}→#{to.id}",
          provider: from.provider,
          kind: :switch,
          error_class: reason,
          latency_ms: nil
        )

        emit_hook(:on_provider_switch, from, to, reason)
      end

      # Last N events as human-readable routing strings for the TUI panel.
      # @param n [Integer]
      # @return [Array<String>]
      def routing_decisions(n = 10)
        recent_events(n).map { |e| format_event(e) }
      end

      # @param n [Integer]
      # @return [Array<Event>]
      def recent_events(n = 20)
        @mutex.synchronize { @events.last(n).dup }
      end

      # Failure rate (0.0–1.0) over the last N events.
      # @return [Float]
      def recent_failure_rate(window: 20)
        events = recent_events(window)
        return 0.0 if events.empty?

        events.count { |e| e.kind == :failure }.to_f / events.size
      end

      private

      def push(event)
        @mutex.synchronize do
          @events << event
          @events.shift if @events.size > @max_events
        end
      end

      def format_event(event)
        label = "#{event.provider}/#{event.credential_id}"
        case event.kind
        when :success
          latency = event.latency_ms ? " (#{event.latency_ms}ms)" : ""
          "#{label} → ✅ success#{latency}"
        when :failure
          "#{label} → ❌ #{event.error_class}"
        when :switch
          "#{label} → ↩️  switch (#{event.error_class})"
        end
      end

      def emit_hook(event_name, *args)
        return unless @hooks

        @hooks.emit(event_name, { credential: args.first, args: args })
      rescue StandardError
        nil # hook errors must never crash the router
      end
    end
  end
end
