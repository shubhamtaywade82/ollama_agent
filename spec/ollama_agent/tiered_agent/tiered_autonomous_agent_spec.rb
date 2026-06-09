# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::TieredAgent::TieredAutonomousAgent do
  let(:phase_runner)  { instance_double(OllamaAgent::TieredAgent::PhaseRunner) }
  let(:tool_executor) { instance_double(OllamaAgent::TieredAgent::ToolExecutor) }
  let(:fake_client)   { double("ollama_client") }

  subject(:agent) do
    described_class.new(goal: "Fix the config file", max_loops: 10).tap do |a|
      a.instance_variable_set(:@phase_runner,  phase_runner)
      a.instance_variable_set(:@tool_executor, tool_executor)
    end
  end

  let(:success_plan) do
    { "rationale" => "Write fixed config", "tool_call" => "write_output_file",
      "tool_instructions" => "write to /tmp/config.json" }
  end
  let(:exit_plan) do
    { "rationale" => "Done", "tool_call" => "exit_success", "tool_instructions" => "" }
  end
  let(:verification_ok)  { { "confirmed_success" => true,  "reasons" => "file written" } }
  let(:verification_fail) { { "confirmed_success" => false, "reasons" => "write error" } }

  before do
    allow(OllamaAgent::OllamaConnection).to receive(:retry_wrapped_client).and_return(fake_client)
  end

  describe "#execute_loop!" do
    context "when the planner immediately signals exit_success" do
      it "returns :success after one cycle" do
        allow(phase_runner).to receive(:run_planning).and_return(exit_plan)
        result = agent.execute_loop!
        expect(result).to eq(:success)
      end
    end

    context "when one tool call succeeds before exit" do
      it "executes planning → extraction → execution → verification then exits" do
        call_count = 0
        allow(phase_runner).to receive(:run_planning) do
          call_count += 1
          call_count == 1 ? success_plan : exit_plan
        end
        allow(phase_runner).to receive(:run_extraction)
          .with(tool_name: "write_output_file", instructions: anything)
          .and_return("path" => "/tmp/config.json", "data" => "{}")
        allow(tool_executor).to receive(:execute)
          .with("write_output_file", anything).and_return("[Success] Written to /tmp/config.json.")
        allow(phase_runner).to receive(:run_verification).and_return(verification_ok)

        result = agent.execute_loop!
        expect(result).to eq(:success)
      end
    end

    context "when verification fails repeatedly and escalation triggers" do
      it "calls run_escalation after ESCALATION_THRESHOLD consecutive failures" do
        fail_plan = { "rationale" => "try bash", "tool_call" => "execute_bash",
                      "tool_instructions" => "run script" }

        call_count = 0
        allow(phase_runner).to receive(:run_planning) do
          call_count += 1
          call_count > described_class::ESCALATION_THRESHOLD ? exit_plan : fail_plan
        end
        allow(phase_runner).to receive(:run_extraction)
          .and_return("command" => "echo hello")
        allow(tool_executor).to receive(:execute).and_return("output")
        allow(phase_runner).to receive(:run_verification).and_return(verification_fail)
        allow(phase_runner).to receive(:run_escalation).and_return("Try a different command")

        agent.execute_loop!

        expect(phase_runner).to have_received(:run_escalation).at_least(:once)
      end

      it "resets consecutive_failures after escalation" do
        fail_plan = { "rationale" => "bash", "tool_call" => "execute_bash",
                      "tool_instructions" => "cmd" }
        cycle = 0
        allow(phase_runner).to receive(:run_planning) do
          cycle += 1
          cycle > described_class::ESCALATION_THRESHOLD ? exit_plan : fail_plan
        end
        allow(phase_runner).to receive(:run_extraction).and_return("command" => "ls")
        allow(tool_executor).to receive(:execute).and_return("output")
        allow(phase_runner).to receive(:run_verification).and_return(verification_fail)
        allow(phase_runner).to receive(:run_escalation).and_return("advice")

        agent.execute_loop!

        expect(agent.instance_variable_get(:@consecutive_failures)).to eq(0)
      end
    end

    context "when max_loops is reached" do
      it "returns :max_loops_reached" do
        allow(phase_runner).to receive(:run_planning).and_return(success_plan)
        allow(phase_runner).to receive(:run_extraction).and_return("path" => "/f", "data" => "d")
        allow(tool_executor).to receive(:execute).and_return("ok")
        allow(phase_runner).to receive(:run_verification).and_return(verification_ok)

        small_agent = described_class.new(goal: "loop forever", max_loops: 3).tap do |a|
          a.instance_variable_set(:@phase_runner,  phase_runner)
          a.instance_variable_set(:@tool_executor, tool_executor)
        end

        result = small_agent.execute_loop!
        expect(result).to eq(:max_loops_reached)
      end
    end
  end

  describe "state log integration" do
    it "updates success state after a passing verification" do
      call_count = 0
      allow(phase_runner).to receive(:run_planning) do
        call_count += 1
        call_count == 1 ? success_plan : exit_plan
      end
      allow(phase_runner).to receive(:run_extraction).and_return("path" => "/f", "data" => "d")
      allow(tool_executor).to receive(:execute).and_return("ok")
      allow(phase_runner).to receive(:run_verification).and_return(verification_ok)

      agent.execute_loop!

      state = agent.instance_variable_get(:@state_log)
      expect(state.summary).to include("write_output_file")
    end

    it "records failures in the state log" do
      call_count = 0
      allow(phase_runner).to receive(:run_planning) do
        call_count += 1
        call_count == 1 ? success_plan : exit_plan
      end
      allow(phase_runner).to receive(:run_extraction).and_return("path" => "/f", "data" => "d")
      allow(tool_executor).to receive(:execute).and_return("error output")
      allow(phase_runner).to receive(:run_verification).and_return(verification_fail)

      agent.execute_loop!

      state = agent.instance_variable_get(:@state_log)
      expect(state.failures).not_to be_empty
    end
  end

  describe "#initialize" do
    it "clamps max_loops to at least 1" do
      a = described_class.new(goal: "g", max_loops: 0)
      expect(a.instance_variable_get(:@max_loops)).to eq(1)
    end

    it "clamps max_loops to at most 500" do
      a = described_class.new(goal: "g", max_loops: 9999)
      expect(a.instance_variable_get(:@max_loops)).to eq(500)
    end
  end
end
