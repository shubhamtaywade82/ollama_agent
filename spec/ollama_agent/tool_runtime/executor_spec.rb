# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::ToolRuntime::Executor do
  let(:tool) do
    Class.new(OllamaAgent::ToolRuntime::Tool) do
      def name = "boom"

      def description = "raises"

      def schema = {}

      def call(_args)
        raise StandardError, "tool failed"
      end
    end.new
  end

  it "returns an error hash when the tool raises" do
    executor = described_class.new
    result = executor.execute({ tool: tool, args: {} })
    expect(result).to eq({ "status" => "error", "error" => "tool failed" })
  end

  it "returns the tool result when call succeeds" do
    ok = Class.new(OllamaAgent::ToolRuntime::Tool) do
      def name = "ok"

      def description = "ok"

      def schema = {}

      def call(args)
        { "status" => "done", "v" => args["q"] }
      end
    end.new

    executor = described_class.new
    out = executor.execute({ tool: ok, args: { "q" => 3 } })
    expect(out).to eq({ "status" => "done", "v" => 3 })
  end

  it "invokes validator when present" do
    validator = Class.new do
      def validate(tool_name, args)
        raise StandardError, "blocked #{tool_name}" if args["block"]

        args.merge("seen" => true)
      end
    end.new

    t = Class.new(OllamaAgent::ToolRuntime::Tool) do
      def name = "t"

      def description = "t"

      def schema = {}

      def call(args)
        args
      end
    end.new

    executor = described_class.new(validator: validator)
    merged = executor.execute({ tool: t, args: { "block" => false } })
    expect(merged).to eq({ "block" => false, "seen" => true })
  end

  it "captures validator errors" do
    validator = Class.new do
      def validate(_tool_name, args)
        raise StandardError, "no way" if args["bad"]

        args
      end
    end.new

    t = Class.new(OllamaAgent::ToolRuntime::Tool) do
      def name = "t"

      def description = "t"

      def schema = {}

      def call(args)
        args
      end
    end.new

    executor = described_class.new(validator: validator)
    result = executor.execute({ tool: t, args: { "bad" => true } })
    expect(result["status"]).to eq("error")
    expect(result["error"]).to eq("no way")
  end
end
