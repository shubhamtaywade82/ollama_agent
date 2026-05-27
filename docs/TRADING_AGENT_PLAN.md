# `trading_agent` — Design & Architecture Plan

A production-grade autonomous crypto-trading framework, built as a **separate Ruby gem**
that layers on top of [`ollama_agent`](https://github.com/shubhamtaywade82/ollama_agent)
as its LLM-orchestration layer.

> Status: **design + starter skeleton**. The skeleton in [`/trading_agent`](../trading_agent)
> compiles and self-documents the architecture; trading-logic bodies are stubs to be filled in by phase.

---

## 1. Context & the one non-negotiable rule

We want an LLM (run locally via Ollama, with optional cloud fallback) to help make trading
decisions on Binance USD-M Futures. The danger with naive "prompt → place order" designs is that
the model eventually **hallucinates trades, violates leverage/risk limits, or deadlocks on
websocket state**. The architecture below exists to make that structurally impossible.

**The rule:**

> **The deterministic Ruby runtime — not the LLM — is the source of truth. The LLM only reasons.**

Concretely, the LLM may *analyze, plan, select read-only tools, and explain*. It **emits a
structured trade *intent*** and nothing more. It **never**:

- touches Binance directly,
- sizes orders or sets leverage,
- picks symbols outside the whitelist,
- holds authoritative position/balance state.

The Ruby runtime fetches market data, aggregates candles, runs deterministic strategies/indicators,
validates the LLM's intent, enforces risk caps, places/cancels orders, maintains state, and recovers
from websocket failures.

---

## 2. Architecture

Event-driven. A lightweight `EventBus` wires the stages; a `StateEngine` is the single source of truth.

```
Binance WS market stream ─┐
                          ├─► StateEngine (SOURCE OF TRUTH: positions/balances/orders/candles)
Binance WS user stream  ──┘            │
        │                              ▼
        └─► CandleStore ──► StrategyEngine (deterministic indicators / SMC)
            (local OHLCV)              │
                                       ▼  (only when a deterministic setup fires)
                         MarketContext (compressed struct for the LLM)
                                       ▼
                         LLM TradeEvaluator  ◄── OllamaAgent::Skills::Base + strict SCHEMA
                                       │ structured trade intent (JSON)
                                       ▼
                         ResponseValidator  ◄── OllamaAgent::Core::SchemaValidator
                                       ▼
                         RiskEngine  (sizing + leverage / exposure / liquidation / kill-switch)
                                       ▼
                         OrderManager (idempotency keys, execution locks, reconciliation)
                                       ▼
                         Exchanges::Binance::FuturesClient  ◄── binance-connector-ruby
```

**Layer responsibilities**

| Layer | Owns | Authority |
|---|---|---|
| `Exchanges::Binance` | REST (orders/positions/leverage/balances), market + user websocket streams | the *only* code that talks to Binance |
| `StateEngine` | in-memory positions/balances/orders/candles, reconciled against the user stream | source of truth |
| `CandleStore` / `IndicatorStore` | local OHLCV aggregation from ticks; EMA/RSI/VWAP/ATR | deterministic, no LLM |
| `StrategyEngine` | BOS/CHOCH/momentum/etc. → emits a `signal` or `nil` | decides *whether to even ask the LLM* |
| `MarketContext` | compresses state+indicators into a small struct | the only thing the LLM sees |
| `TradeEvaluator` (LLM) | reasons over context → emits structured intent | **no execution authority** |
| `ResponseValidator` | schema-validates the intent, rejects malformed output | gate |
| `RiskEngine` | sizing + every hard cap + kill-switch | veto power over every trade |
| `OrderManager` / `PositionManager` | order lifecycle, idempotency, reconciliation | executes only validated, risk-approved intents |

---

## 3. What we reuse from `ollama_agent` (do NOT rewrite)

The LLM-orchestration layer already exists in this repo. `trading_agent` *consumes* it.

| Need | Reuse | Path in `ollama_agent` |
|---|---|---|
| LLM emits **structured, schema-validated** output (never free text) | `Skills::Base` pipeline: `prompt → llm.generate → JsonExtractor.parse → SchemaValidator.validate!` + a `SCHEMA` constant | `lib/ollama_agent/skills/base.rb` |
| Single-shot, local-first JSON generation | `Skills::LlmClient` (defaults to Ollama, temperature 0.0, injectable in tests) | `lib/ollama_agent/skills/llm_client.rb` |
| Zero-dependency schema validation / reject malformed | `Core::SchemaValidator#validate!` (type/required/enum/min/max) | `lib/ollama_agent/core/schema_validator.rb` |
| Tool calling (read-only context fetchers) | `OllamaAgent::Tools.register(name, schema:, &handler)` | `lib/ollama_agent/tools/registry.rb` |
| Multi-provider LLM + cloud fallback | `Providers::Registry` / `Runner.build(provider:)` | `lib/ollama_agent/providers/registry.rb`, `runner.rb` |
| Agent loop, budget, loop detection | `Runner.build(...).run`, `Core::Budget`, `Core::LoopDetector` | `runner.rb`, `lib/ollama_agent/core/*` |
| Memory tiers / session persistence (for **audit/narration**, not trade truth) | `Memory::Manager`, `Session::Store` | `lib/ollama_agent/memory/manager.rb` |
| Hard guardrails on tool authority | `Runner.build(read_only:, permissions:)`, `Runtime::Permissions` | `runner.rb`, `lib/ollama_agent/runtime/permissions.rb` |

**Consequence:** the `trading_agent` LLM layer is thin — a `Skills::Base` subclass (`TradeEvaluator`)
with a strict decision `SCHEMA`, plus a few **read-only** registered tools. All *trading* engineering
(exchange, streams, candles, strategies, risk, execution, recovery) is net-new in the new gem.

---

## 4. The structured trade-intent contract

The LLM never returns prose. `TradeEvaluator < OllamaAgent::Skills::Base` declares a `SCHEMA`; the
base class validates every response and raises `ContractError` on any deviation.

```json
{
  "action":      "LONG",
  "symbol":      "BTCUSDT",
  "confidence":  0.83,
  "entry_type":  "MARKET",
  "risk_percent": 1.0,
  "stop_loss":   103200.0,
  "take_profit": 105800.0,
  "reasoning":   ["4H bullish BOS", "1H demand reclaim", "5m momentum expansion"]
}
```

Schema enforces: `action ∈ {LONG, SHORT, FLAT}`, `entry_type ∈ {MARKET, LIMIT}`,
`0 ≤ confidence ≤ 1`, `0 < risk_percent ≤ MAX_ACCOUNT_RISK`, required `symbol`/`stop_loss`/`take_profit`,
`reasoning` is a non-empty array. Anything else is rejected **before it reaches the RiskEngine**.

`symbol` is *still* re-checked against the whitelist in the RiskEngine — never trust an LLM string.

---

## 5. Exchange adapter contract

`Exchanges::Base` is abstract so we can add Bybit / Dhan / Zerodha later without touching the runtime:

```ruby
place_order(symbol:, side:, type:, quantity:, price: nil, client_order_id:)
cancel_order(symbol:, order_id:)
positions
balances
set_leverage(symbol:, leverage:)
subscribe_market(symbol:, &on_event)
subscribe_user(&on_event)
```

`Exchanges::Binance::FuturesClient` implements it on top of
[`binance-connector-ruby`](https://github.com/binance/binance-connector-ruby) for REST
(orders/positions/leverage/account) and websocket for market + user-data streams.
`StreamManager` owns reconnection, sequence-gap detection, stale-stream/heartbeat handling.

Use the Binance toolbox examples only as a **reference** for local order-book sync and websocket
sequencing — do not couple the runtime to example code.

---

## 6. Production-risk checklist (must-solve)

- **Duplicate orders** → client-supplied idempotency keys (`client_order_id`), execution locks per
  symbol, and periodic reconciliation against the user stream.
- **Websocket desync** → automatic reconnect, sequence-gap recovery, stale-stream detection,
  heartbeat monitoring (`StreamManager`).
- **Hallucinated symbols** → `SymbolRegistry` whitelist; RiskEngine rejects anything not on it.
- **Runaway position scaling** → hard caps outside LLM control:
  `MAX_OPEN_POSITIONS = 3`, `MAX_ACCOUNT_RISK = 5%`, `MAX_LEVERAGE = 5`.
- **Emergency kill-switch** → halt all new entries when `daily_drawdown > MAX_DAILY_DRAWDOWN`.
- **Rate limits** → centralized throttling, websocket-first reads, retry with jitter.

---

## 7. Models

Local-first via Ollama, cloud fallback via `Providers::Registry`:

- **Balanced / structured-output + tool calling:** `qwen3.x:14b` / `qwen3.x:32b`
- **Fast reasoning / planner:** `deepseek-r1:14b`
- **Heavy multi-symbol analysis (cloud fallback):** larger qwen / deepseek hosted models

Hybrid: a local agent handles low-latency execution decisions; a cloud agent handles deeper
multi-symbol ranking / regime detection.

---

## 8. Phased roadmap

Each phase maps to skeleton files under [`/trading_agent/lib/trading_agent`](../trading_agent/lib/trading_agent).

- **Phase 1 — deterministic plumbing (no AI):** `Exchanges::Binance::*`, `StreamManager`,
  `StateEngine`, `CandleStore`, `OrderManager`, `PositionManager`. Verify on **testnet**.
- **Phase 2 — structured LLM:** `Llm::DecisionSchema`, `Llm::TradeEvaluator`, `Llm::Tools`
  (read-only context fetchers), `ResponseValidator`. Reject malformed output.
- **Phase 3 — strategy + risk:** `Strategies::*`, `IndicatorStore`, `Risk::RiskEngine`,
  `Risk::PositionSizer`, `Risk::Guards`. Multi-timeframe context.
- **Phase 4 — autonomous execution + recovery + alerts:** full `Runner` loop, reconciliation,
  recovery daemon, Telegram/metrics alerts.

---

## 9. Verification

Skeleton-level (this deliverable):

1. `cd trading_agent && bundle install` resolves (`ollama_agent` via `path: ".."`).
2. `bundle exec ruby -Ilib -e 'require "trading_agent"'` loads cleanly.
3. `bundle exec rspec` passes the seed specs:
   - `TradeEvaluator` rejects a malformed LLM response (schema → `ContractError`).
   - `RiskEngine` rejects intents breaching `MAX_ACCOUNT_RISK` / `MAX_LEVERAGE` / kill-switch.

Later (per roadmap, out of scope here): Binance **testnet** smoke test of `FuturesClient`,
paper-trade dry-run of the full `Runner` loop, websocket reconnect/recovery test.

---

## 10. Skeleton layout

See [`/trading_agent`](../trading_agent). Key files:

- `lib/trading_agent/runner.rb` — the orchestration loop (ctx → strategy → evaluator → validate → risk → execute).
- `lib/trading_agent/llm/trade_evaluator.rb` — `OllamaAgent::Skills::Base` subclass; the linchpin reuse.
- `lib/trading_agent/risk/risk_engine.rb` + `risk/guards.rb` — the veto layer (implemented, not stubbed).
- `lib/trading_agent/exchanges/base.rb` — the adapter contract for multi-exchange support.
- `lib/trading_agent/state/state_engine.rb` — the source of truth.
