# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::ToolRuntime::Loop do
  let(:noop_class) do
    Class.new(OllamaAgent::ToolRuntime::Tool) do
      def name = "noop"

      def description = "noop"

      def schema = {}

      def call(_args)
        { "status" => "ok" }
      end
    end
  end

  let(:finish_class) do
    Class.new(OllamaAgent::ToolRuntime::Tool) do
      def initialize
        super
        @calls = 0
      end

      attr_reader :calls

      def name = "finish"

      def description = "done"

      def schema = {}

      def call(_args)
        @calls += 1
        { "status" => "done" }
      end
    end
  end

  let(:fake_planner_class) do
    Class.new do
      def initialize(steps)
        @steps = steps
      end

      def next_step(**)
        @steps.shift
      end
    end
  end

  it "runs until a tool result has status done" do
    finish = finish_class.new
    registry = OllamaAgent::ToolRuntime::Registry.new([noop_class.new, finish])
    planner = fake_planner_class.new(
      [
        { "tool" => "noop", "args" => {} },
        { "tool" => "finish", "args" => {} }
      ]
    )
    memory = OllamaAgent::ToolRuntime::Memory.new
    executor = OllamaAgent::ToolRuntime::Executor.new

    last = described_class.new(
      planner: planner,
      registry: registry,
      executor: executor,
      memory: memory,
      max_steps: 10
    ).run(context: "task")

    expect(last).to eq({ "status" => "done" })
    expect(memory.recent.size).to eq(2)
    expect(finish.calls).to eq(1)
  end

  it "raises MaxStepsExceeded when the loop never terminates" do
    registry = OllamaAgent::ToolRuntime::Registry.new([noop_class.new])
    planner = fake_planner_class.new(Array.new(15) { { "tool" => "noop", "args" => {} } })
    memory = OllamaAgent::ToolRuntime::Memory.new
    executor = OllamaAgent::ToolRuntime::Executor.new

    loop_runner = described_class.new(
      planner: planner,
      registry: registry,
      executor: executor,
      memory: memory,
      max_steps: 3
    )

    expect { loop_runner.run(context: "x") }
      .to raise_error(OllamaAgent::ToolRuntime::MaxStepsExceeded, /max_steps=3/)
  end

  it "raises InvalidPlanError when the planner returns an unknown tool" do
    registry = OllamaAgent::ToolRuntime::Registry.new([noop_class.new])
    planner = fake_planner_class.new([{ "tool" => "nope", "args" => {} }])
    memory = OllamaAgent::ToolRuntime::Memory.new
    executor = OllamaAgent::ToolRuntime::Executor.new

    loop_runner = described_class.new(
      planner: planner,
      registry: registry,
      executor: executor,
      memory: memory,
      max_steps: 5
    )

    expect { loop_runner.run(context: "x") }
      .to raise_error(OllamaAgent::ToolRuntime::InvalidPlanError, /invalid tool plan/)
  end

  it "logs steps when logger responds to info" do
    finish = finish_class.new
    registry = OllamaAgent::ToolRuntime::Registry.new([finish])
    planner = fake_planner_class.new([{ "tool" => "finish", "args" => {} }])
    memory = OllamaAgent::ToolRuntime::Memory.new
    executor = OllamaAgent::ToolRuntime::Executor.new
    logger = Class.new do
      attr_reader :lines

      def initialize
        @lines = []
      end

      def info(msg)
        @lines << msg
      end
    end.new

    last = described_class.new(
      planner: planner,
      registry: registry,
      executor: executor,
      memory: memory,
      logger: logger,
      max_steps: 5
    ).run(context: "c")

    expect(last).to eq({ "status" => "done" })
    expect(logger.lines).not_to be_empty
  end
end
