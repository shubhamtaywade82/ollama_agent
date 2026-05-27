# frozen_string_literal: true

module TradingAgent
  class Runner
    attr_reader :exchange, :state, :risk_engine, :execution_manager, :llm_orchestrator, :symbols

    def initialize(exchange:, model: "qwen2.5:14b", symbols: ["BTCUSDT"])
      @exchange = exchange
      @symbols = symbols
      @state = Market::State.new
      @risk_engine = Risk::Engine.new
      @execution_manager = Execution::Manager.new(exchange)
      @llm_orchestrator = Llm::Orchestrator.new(@state, @exchange, model: model)
      
      setup_subscriptions
    end

    def start
      TradingAgent.logger.info("Starting Trading Agent", symbols: @symbols)
      
      Async do |task|
        # 1. Fetch initial state
        begin
          update_initial_state
        rescue StandardError => e
          TradingAgent.logger.error("Failed to fetch initial state", error: e.message)
        end
        
        # 2. Start polling loop
        loop do
          begin
            @symbols.each do |symbol|
              ticker = @exchange.fetch_ticker(symbol)
              @state.update_price(symbol, ticker[:price])
              
              # Fetch and cache 1h candles
              candles = @exchange.fetch_candles(symbol, "1h", limit: 100)
              @state.update_candles(symbol, "1h", candles)
            end
            
            # 3. Strategy / LLM Evaluation Loop
            run_evaluation_cycle
          rescue StandardError => e
            TradingAgent.logger.error("Error in evaluation cycle", error: e.message)
          end
          
          task.sleep 60 # Check every minute for now
        end
      end
    end

    private

    def setup_subscriptions
      EventBus.subscribe("market.tick") do |payload|
        # Log or react to tick if needed
      end
    end

    def update_initial_state
      @state.update_balances(@exchange.fetch_balances)
      
      begin
        positions = @exchange.fetch_positions
        positions.each do |pos|
          @state.update_position(pos[:symbol], pos)
        end
      rescue StandardError => e
        TradingAgent.logger.error("Failed to fetch initial positions", error: e.message)
      end
    end

    def run_evaluation_cycle
      market_context = {
        prices: @symbols.map { |s| [s, @state.get_price(s)] }.to_h,
        balances: @state.get_balances,
        drawdown: @state.current_drawdown_pct,
        positions: @symbols.map { |s| [s, @state.get_position(s)] }.to_h
      }
      
      intent = @llm_orchestrator.analyze_and_plan(market_context)
      return if intent.nil?
      
      EventBus.publish("llm.intent", intent: intent)
      return if intent[:action] == "HOLD"
      
      validation = @risk_engine.validate_intent(intent, @state)
      EventBus.publish("risk.validated", intent: intent, validation: validation)
      
      if validation[:success]
        @execution_manager.execute_intent(intent, @state)
        # Update local cache after order execution
        update_initial_state
      else
        TradingAgent.logger.warn("Trade intent rejected by Risk Engine", reason: validation[:reason])
      end
    end
  end
end
