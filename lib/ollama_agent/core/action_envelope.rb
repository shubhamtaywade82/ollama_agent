# frozen_string_literal: true

module OllamaAgent
  module Core
    # Wraps every structured response from the planner.
    # Enforces a fixed contract so the runner stays deterministic.
    #
    # Types:
    #   :tool_call        — execute a tool with args
    #   :final            — model is done; surface content to the user
    #   :ask_clarification— model needs more info before proceeding
    #   :error            — unrecoverable error in the action
    #   :handoff          — delegate to another agent
    class ActionEnvelope
      VALID_TYPES = %i[tool_call final ask_clarification error handoff].freeze

      attr_reader :type, :payload, :confidence, :envelope_id

      def initialize(type:, payload:, confidence: nil, envelope_id: nil)
        raise ArgumentError, "Unknown action type: #{type}" unless VALID_TYPES.include?(type.to_sym)

        @type        = type.to_sym
        @payload     = payload
        @confidence  = confidence
        @envelope_id = envelope_id || generate_id
      end

      # --- Factory constructors ---

      def self.tool_call(tool:, args:, confidence: nil)
        new(type: :tool_call, payload: { tool: tool.to_s, args: args || {} }, confidence: confidence)
      end

      def self.final(content:)
        new(type: :final, payload: { content: content.to_s })
      end

      def self.ask_clarification(question:)
        new(type: :ask_clarification, payload: { question: question.to_s })
      end

      def self.error(message:, cause: nil)
        new(type: :error, payload: { message: message.to_s, cause: cause })
      end

      def self.handoff(agent:, query:)
        new(type: :handoff, payload: { agent: agent.to_s, query: query.to_s })
      end

      # --- Predicate helpers ---

      def tool_call?        = @type == :tool_call
      def final?            = @type == :final
      def ask_clarification? = @type == :ask_clarification
      def error?            = @type == :error
      def handoff?          = @type == :handoff

      # --- Accessors for common payload fields ---

      def tool    = @payload[:tool]
      def args    = @payload[:args] || {}
      def content = @payload[:content]
      def question = @payload[:question]
      def message = @payload[:message]

      def to_h
        { type: @type, payload: @payload, confidence: @confidence, envelope_id: @envelope_id }
      end

      def to_s
        "#<ActionEnvelope type=#{@type} id=#{@envelope_id}>"
      end

      private

      def generate_id
        require "securerandom"
        "env_#{SecureRandom.hex(6)}"
      end
    end
  end
end
