# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/runtime_command_system/ast"
require "ollama_agent/runtime_command_system/dispatch/dispatcher"

RSpec.describe OllamaAgent::RuntimeCommandSystem::Dispatch::Dispatcher do
  subject(:dispatcher) { described_class.new }

  let(:handler) { double("Handler") }
  let(:session) { double("session") }

  before { dispatcher.register("model", handler) }

  describe "#handles?" do
    it "returns true for registered command without slash" do
      expect(dispatcher.handles?("model")).to be true
    end

    it "returns true for registered command with slash" do
      expect(dispatcher.handles?("/model")).to be true
    end

    it "returns false for unregistered command" do
      expect(dispatcher.handles?("help")).to be false
    end
  end

  describe "#dispatch" do
    it "routes to registered handler and merges handled: true" do
      allow(handler).to receive(:call).and_return({ model: "qwen3:32b" })
      ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model qwen3:32b")
      result = dispatcher.dispatch(ast, session: session)
      expect(result[:handled]).to be true
      expect(result[:model]).to eq("qwen3:32b")
    end

    it "returns handled: false for unregistered command" do
      ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/help")
      result = dispatcher.dispatch(ast, session: session)
      expect(result[:handled]).to be false
    end

    it "merges handled: true even when handler returns nil" do
      allow(handler).to receive(:call).and_return(nil)
      ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model qwen3:32b")
      result = dispatcher.dispatch(ast, session: session)
      expect(result[:handled]).to be true
    end
  end
end
