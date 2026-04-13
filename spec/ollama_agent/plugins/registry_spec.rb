# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Plugins::Registry do
  subject(:registry) { described_class.new }

  describe "#register" do
    it "registers a plugin by name" do
      registry.register(:my_plugin) { |_r| nil }
      expect(registry.plugin_names).to include(:my_plugin)
    end

    it "calls the block with the registry" do
      received = nil
      registry.register(:test) { |r| received = r }
      expect(received).to eq(registry)
    end

    it "raises on duplicate plugin names" do
      registry.register(:dup) { |_r| nil }
      expect { registry.register(:dup) { |_r| nil } }.to raise_error(ArgumentError, /already registered/)
    end
  end

  describe "#extend" do
    it "adds a tool extension" do
      tool = Object.new
      registry.extend(:tools, tool)
      expect(registry.extensions_for(:tools)).to include(tool)
    end

    it "raises for unknown extension points" do
      expect { registry.extend(:unknown_point, nil) }.to raise_error(ArgumentError, /Unknown extension point/)
    end
  end

  describe "#add_tool / #add_prompt / #add_policy" do
    it "adds a tool" do
      registry.add_tool("my_tool")
      expect(registry.extensions_for(:tools)).to include("my_tool")
    end

    it "adds a prompt" do
      registry.add_prompt(name: "review", content: "Review this code")
      prompts = registry.extensions_for(:prompts)
      expect(prompts).to include({ name: "review", content: "Review this code" })
    end

    it "adds a policy via block" do
      registry.add_policy { |_t, _a, _c| nil }
      expect(registry.extensions_for(:policies).size).to eq(1)
    end
  end

  describe "#add_command" do
    it "registers a slash command handler" do
      registry.add_command(slash_command: "/test") { |_arg| "result" }
      handlers = registry.extensions_for(:command_handlers)
      expect(handlers.first[:slash_command]).to eq("/test")
    end
  end

  describe "#reset!" do
    it "clears all plugins and extensions" do
      registry.register(:p1) { |_r| nil }
      registry.add_tool("tool1")
      registry.reset!
      expect(registry.plugin_names).to be_empty
      expect(registry.extensions_for(:tools)).to be_empty
    end
  end
end
