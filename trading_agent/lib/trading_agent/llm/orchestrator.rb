# frozen_string_literal: true

module TradingAgent
  module Llm
    class Orchestrator
      def initialize(state, exchange, model: "qwen2.5:14b")
        ToolRegistry.register_all(state, exchange)
        @agent = OllamaAgent::Runner.build(
          model: model,
          system_prompt: system_prompt,
          read_only: true
        )
      end

      def analyze_and_plan(market_context)
        prompt = "Current Market Context: #{market_context.to_json}\n\nAnalyze and provide a trade intent in JSON format."
        
        last_response = nil
        @agent.hooks.on(:on_complete) do |payload|
          last_response = payload[:messages]&.last
        end

        @agent.run(prompt)
        
        return nil if last_response.nil?

        content = last_response[:content] || last_response["content"]
        return nil if content.to_s.strip.empty?

        begin
          # Parse and return symbolized intent
          OllamaAgent::Skills::JsonExtractor.parse(content)
        rescue OllamaAgent::Skills::JsonExtractor::ExtractionError => e
          TradingAgent.logger.error("Failed to extract JSON from LLM response", error: e.message, response: content)
          nil
        rescue JSON::ParserError => e
          TradingAgent.logger.error("Failed to parse LLM response as JSON", error: e.message, response: content)
          nil
        end
      end

      private

      def system_prompt
        <<~PROMPT
          You are an expert crypto trading agent.
          Your goal is to analyze market data and provide structured trade intents.
          Use the custom trading tools provided to inspect current prices, technical indicators, open positions, and account balances before making decisions.
          
          OUTPUT FORMAT:
          You MUST respond with a JSON object containing:
          - action: "BUY", "SELL", or "HOLD"
          - symbol: string (e.g., "BTCUSDT")
          - leverage: integer
          - risk_percent: float
          - stop_loss: float
          - take_profit: float
          - reasoning: array of strings
          
          Example:
          {
            "action": "BUY",
            "symbol": "BTCUSDT",
            "leverage": 3,
            "risk_percent": 1.0,
            "stop_loss": 95000.0,
            "take_profit": 105000.0,
            "reasoning": ["Bullish structure on 4H", "RSI reclaim"]
          }
        PROMPT
      end
    end
  end
end
