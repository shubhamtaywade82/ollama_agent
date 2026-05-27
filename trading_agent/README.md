# trading_agent

Event-driven autonomous trading runtime with an LLM reasoning layer, built on top of
[`ollama_agent`](https://github.com/shubhamtaywade82/ollama_agent).

> **Status: starter skeleton.** The architecture is wired and self-documenting; most
> trading-logic bodies are stubs (`raise NotImplementedError`) to be filled in by phase.
> See [`../docs/TRADING_AGENT_PLAN.md`](../docs/TRADING_AGENT_PLAN.md) for the full design.

## The one rule

**The deterministic Ruby runtime — not the LLM — is the source of truth.**
The LLM only reasons and emits a structured, schema-validated trade *intent*. It never touches
the exchange, sizes orders, sets leverage, or picks symbols off the whitelist.

## Architecture

```
WS stream ─► StateEngine (source of truth) ─► StrategyEngine ─► LLM TradeEvaluator
                                                                     │ structured intent
                                                                     ▼
                                              ResponseValidator ─► RiskEngine ─► OrderManager ─► Binance
```

## Quickstart (target API)

```ruby
require "trading_agent"

TradingAgent.configure do |c|
  c.exchange      = :binance_futures
  c.testnet       = true
  c.model         = "qwen3.5:14b"
  c.symbols       = %w[BTCUSDT ETHUSDT]
end

TradingAgent::Runner.new(strategy: TradingAgent::Strategies::SmcMomentum).start
```

## Development

```bash
bundle install
bundle exec rspec
```
