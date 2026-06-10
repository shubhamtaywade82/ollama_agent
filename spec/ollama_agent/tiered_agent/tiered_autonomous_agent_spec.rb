# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::TieredAgent::TieredAutonomousAgent do
  let(:phase_runner)  { instance_double(OllamaAgent::TieredAgent::PhaseRunner) }
  let(:exit_plan)     { { "rationale" => "Done", "tool_call" => "exit_success", "tool_instructions" => "" } }
  let(:write_plan)    { { "rationale" => "Write config", "tool_call" => "write_output_file", "tool_instructions" => "write /f" } }
  let(:bash_plan)     { { "rationale" => "Run bash", "tool_call" => "execute_bash", "tool_instructions" => "cmd" } }
  let(:ok_verify)     { { "confirmed_success" => true,  "reasons" => "ok" } }
  let(:fail_verify)   { { "confirmed_success" => false, "reasons" => "failed" } }
  let(:tool_executor) { instance_double(OllamaAgent::TieredAgent::ToolExecutor) }
  let(:fake_client)   { double("ollama_client") }

  # Suppress VRAM probe and banner output in tests unless explicitly needed.
  before do
    allow(OllamaAgent::OllamaConnection).to receive(:retry_wrapped_client).and_return(fake_client)
    allow(OllamaAgent::TieredAgent::HardwareProbe).to receive_messages(detect_vram_gb: nil, cloud_mode?: false)
    allow($stdout).to receive(:puts)
  end

  def build_agent(goal: "Fix config", max_loops: 10, **opts)
    described_class.new(goal: goal, max_loops: max_loops, **opts).tap do |a|
      a.instance_variable_set(:@phase_runner,  phase_runner)
      a.instance_variable_set(:@tool_executor, tool_executor)
    end
  end

  # ---------------------------------------------------------------------------
  # Profile / VRAM selection
  # ---------------------------------------------------------------------------

  describe "hardware profile selection" do
    it "uses :minimal profile when no GPU is detected" do
      agent = build_agent
      expect(agent.active_profile.name).to eq(:minimal)
    end

    it "selects :performance profile for 16 GB detected VRAM" do
      allow(OllamaAgent::TieredAgent::HardwareProbe).to receive(:detect_vram_gb).and_return(16.0)
      agent = build_agent
      expect(agent.active_profile.name).to eq(:performance)
    end

    it "selects :high profile for 24 GB detected VRAM" do
      allow(OllamaAgent::TieredAgent::HardwareProbe).to receive(:detect_vram_gb).and_return(24.0)
      agent = build_agent
      expect(agent.active_profile.name).to eq(:high)
    end

    it "honours an explicit :profile override regardless of VRAM" do
      allow(OllamaAgent::TieredAgent::HardwareProbe).to receive(:detect_vram_gb).and_return(8.0)
      agent = build_agent(profile: :ultra)
      expect(agent.active_profile.name).to eq(:ultra)
    end

    it "honours an explicit vram_gb override without calling the probe" do
      expect(OllamaAgent::TieredAgent::HardwareProbe).not_to receive(:detect_vram_gb)
      agent = build_agent(vram_gb: 22)
      expect(agent.active_profile.name).to eq(:high)
    end

    it "raises ArgumentError for an unknown :profile name" do
      expect { build_agent(profile: :nonexistent) }
        .to raise_error(ArgumentError, /nonexistent/)
    end

    it "profile takes precedence over vram_gb" do
      agent = build_agent(vram_gb: 8, profile: :maximum)
      expect(agent.active_profile.name).to eq(:maximum)
    end
  end

  # ---------------------------------------------------------------------------
  # Model overrides
  # ---------------------------------------------------------------------------

  describe "per-tier model overrides" do
    # Build without injecting the phase_runner double so we can inspect the real one.
    def build_agent_uninstrumented(**opts)
      described_class.new(goal: "Fix config", max_loops: 10, **opts)
    end

    it "uses profile defaults when no overrides are given" do
      agent  = build_agent_uninstrumented(profile: :standard)
      models = agent.instance_variable_get(:@phase_runner).instance_variable_get(:@models)
      prof   = OllamaAgent::TieredAgent::HardwareProfile.find(:standard)
      expect(models[:small]).to  eq(prof.model_small)
      expect(models[:medium]).to eq(prof.model_medium)
      expect(models[:large]).to  eq(prof.model_large)
    end

    it "overrides only the specified model tier" do
      agent  = build_agent_uninstrumented(profile: :minimal, model_large: "custom:latest")
      models = agent.instance_variable_get(:@phase_runner).instance_variable_get(:@models)
      expect(models[:large]).to eq("custom:latest")
      expect(models[:small]).to eq(OllamaAgent::TieredAgent::HardwareProfile.find(:minimal).model_small)
    end
  end

  # ---------------------------------------------------------------------------
  # Loop execution
  # ---------------------------------------------------------------------------

  describe "#execute_loop!" do
    subject(:agent) { build_agent }

    context "when the planner immediately signals exit_success" do
      it "returns :success after one cycle" do
        allow(phase_runner).to receive(:run_planning).and_return(exit_plan)
        expect(agent.execute_loop!).to eq(:success)
      end
    end

    context "when one tool call succeeds before exit" do
      it "runs all four sub-phases then exits" do
        call = 0
        allow(phase_runner).to receive(:run_planning) { (call += 1) == 1 ? write_plan : exit_plan }
        allow(tool_executor).to receive(:execute).and_return("[Success]")
        allow(phase_runner).to receive_messages(run_extraction: { "path" => "/f", "data" => "d" }, run_verification: ok_verify)
        expect(agent.execute_loop!).to eq(:success)
      end
    end

    context "escalation after repeated failures" do
      it "calls run_escalation after ESCALATION_THRESHOLD consecutive failures" do
        call = 0
        allow(phase_runner).to receive(:run_planning) do
          (call += 1) > described_class::ESCALATION_THRESHOLD ? exit_plan : bash_plan
        end
        allow(tool_executor).to receive(:execute).and_return("output")
        allow(phase_runner).to receive_messages(run_extraction: { "command" => "ls" }, run_verification: fail_verify, run_escalation: "Try differently")

        agent.execute_loop!
        expect(phase_runner).to have_received(:run_escalation).at_least(:once)
      end

      it "resets consecutive_failures to 0 after escalation" do
        call = 0
        allow(phase_runner).to receive(:run_planning) do
          (call += 1) > described_class::ESCALATION_THRESHOLD ? exit_plan : bash_plan
        end
        allow(tool_executor).to receive(:execute).and_return("output")
        allow(phase_runner).to receive_messages(run_extraction: { "command" => "ls" }, run_verification: fail_verify, run_escalation: "advice")

        agent.execute_loop!
        expect(agent.instance_variable_get(:@consecutive_failures)).to eq(0)
      end
    end

    context "when max_loops is reached" do
      it "returns :max_loops_reached" do
        small_agent = build_agent(max_loops: 2)
        allow(tool_executor).to receive(:execute).and_return("ok")
        allow(phase_runner).to receive_messages(run_planning: write_plan, run_extraction: { "path" => "/f", "data" => "d" }, run_verification: ok_verify)
        expect(small_agent.execute_loop!).to eq(:max_loops_reached)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Constructor guards
  # ---------------------------------------------------------------------------

  describe "#initialize" do
    it "clamps max_loops to at least 1" do
      a = build_agent(max_loops: 0)
      expect(a.instance_variable_get(:@max_loops)).to eq(1)
    end

    it "clamps max_loops to at most 500" do
      a = build_agent(max_loops: 9999)
      expect(a.instance_variable_get(:@max_loops)).to eq(500)
    end
  end
end
