# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/runtime_command_system/ast"
require "ollama_agent/runtime_command_system/session/runtime"
require "ollama_agent/runtime_command_system/dispatch/handlers/model_handler"

RSpec.describe OllamaAgent::RuntimeCommandSystem::Dispatch::Handlers::ModelHandler do
  subject(:handler) { described_class.new }

  let(:agent) { instance_double(OllamaAgent::Agent) }
  let(:session) do
    instance_double(
      OllamaAgent::RuntimeCommandSystem::Session::Runtime,
      agent: agent
    )
  end

  before do
    allow(OllamaAgent::Providers::ModelRegistry).to receive(:find).and_return(nil)
    allow(session).to receive(:switch_model!)
  end

  it "calls session.switch_model! with the model name" do
    ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model qwen3:32b")
    handler.call(ast: ast, session: session)
    expect(session).to have_received(:switch_model!).with("qwen3:32b", descriptor: nil)
  end

  it "returns a hash with the model name" do
    ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model qwen3:32b")
    result = handler.call(ast: ast, session: session)
    expect(result[:model]).to eq("qwen3:32b")
  end

  it "raises ArgumentError when no model name given (bare /model)" do
    ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model")
    expect { handler.call(ast: ast, session: session) }.to raise_error(ArgumentError, /Missing model name/)
  end

  it "raises ArgumentError when argument is only whitespace" do
    ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model ")
    expect { handler.call(ast: ast, session: session) }.to raise_error(ArgumentError, /Missing model name/)
  end

  it "passes found descriptor to switch_model!" do
    descriptor = instance_double(OllamaAgent::Providers::ModelDescriptor, name: "qwen3:32b")
    allow(OllamaAgent::Providers::ModelRegistry).to receive(:find)
      .with("qwen3:32b", agent: agent)
      .and_return(descriptor)

    ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model qwen3:32b")
    handler.call(ast: ast, session: session)
    expect(session).to have_received(:switch_model!).with("qwen3:32b", descriptor: descriptor)
  end

  it "passes nil descriptor when model not found in registry" do
    allow(OllamaAgent::Providers::ModelRegistry).to receive(:find).and_return(nil)
    ast = OllamaAgent::RuntimeCommandSystem::AST::Parser.parse("/model unknown-model")
    handler.call(ast: ast, session: session)
    expect(session).to have_received(:switch_model!).with("unknown-model", descriptor: nil)
  end
end
