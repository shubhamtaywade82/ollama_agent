# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/cli/repl_shared"
require "ollama_agent/runtime_command_system/command_palette"

RSpec.describe "ReplShared#runtime_command_palette" do
  let(:test_class) do
    Class.new do
      include OllamaAgent::CLI::ReplShared

      def initialize(agent)
        @agent = agent
        @stdout = StringIO.new
      end

      public :runtime_command_palette
    end
  end

  let(:agent) { instance_double(OllamaAgent::Agent) }
  subject(:obj) { test_class.new(agent) }

  before do
    allow(OllamaAgent::Plugins::Registry).to receive(:all_command_handlers).and_return([])
  end

  it "returns the same instance across multiple calls" do
    first  = obj.runtime_command_palette
    second = obj.runtime_command_palette

    expect(first).to be(second)
  end

  it "returns a CommandPalette" do
    expect(obj.runtime_command_palette).to be_a(OllamaAgent::RuntimeCommandSystem::CommandPalette)
  end
end
