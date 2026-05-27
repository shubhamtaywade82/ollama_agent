# frozen_string_literal: true

require_relative "lib/trading_agent/version"

Gem::Specification.new do |spec|
  spec.name = "trading_agent"
  spec.version = TradingAgent::VERSION
  spec.authors = ["Shubham Taywade"]
  spec.email = ["shubhamtaywade82@gmail.com"]

  spec.summary = "Event-driven autonomous trading runtime with an LLM reasoning layer."
  spec.description = "A production-grade Ruby trading framework. A deterministic runtime owns market " \
                     "data, websocket state, candle aggregation, strategies, risk management, and order " \
                     "execution; the LLM (via ollama_agent) only reasons and emits a structured, " \
                     "schema-validated trade intent. The runtime — never the LLM — is the source of truth."
  spec.homepage = "https://github.com/shubhamtaywade82/ollama_agent"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "exe/*",
    "README.md"
  ]
  spec.bindir = "exe"
  spec.executables = ["trading_agent"]
  spec.require_paths = ["lib"]

  # LLM orchestration layer (reasoning, structured-output skills, schema validation, tool calling).
  spec.add_dependency "ollama_agent", ">= 1.0"

  # Exchange connectivity (REST + websocket). Binance USD-M Futures first.
  spec.add_dependency "binance-connector-ruby", "~> 1.5"

  # Concurrency / event loop for websocket streams and the runtime.
  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "concurrent-ruby", "~> 1.2"

  # Fast JSON for stream payloads.
  spec.add_dependency "oj", "~> 3.16"

  # Local persistence for snapshots / audit (also a transitive ollama_agent dep).
  spec.add_dependency "sqlite3", "~> 2.0"

  # rubocop:disable Gemspec/DevelopmentDependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  # rubocop:enable Gemspec/DevelopmentDependencies
end
