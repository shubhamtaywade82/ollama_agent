# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::TieredAgent::StateLog do
  subject(:log) { described_class.new }

  describe "#to_h" do
    it "starts with initializing summary" do
      expect(log.to_h["summary"]).to include("Initializing")
    end

    it "starts with empty variables and failures" do
      expect(log.to_h["variables"]).to eq({})
      expect(log.to_h["failures"]).to eq([])
    end
  end

  describe "#to_json" do
    it "round-trips through JSON.parse" do
      parsed = JSON.parse(log.to_json)
      expect(parsed).to eq(log.to_h)
    end
  end

  describe "#update_success" do
    it "sets a success summary" do
      log.update_success("execute_bash")
      expect(log.summary).to include("execute_bash")
    end

    it "records last executed tool in variables" do
      log.update_success("write_output_file")
      expect(log.variables["last_executed_tool"]).to eq("write_output_file")
    end
  end

  describe "#record_failure" do
    it "appends a failure entry" do
      log.record_failure("execute_bash", "syntax error")
      expect(log.failures.length).to eq(1)
      expect(log.failures.first).to include("tool" => "execute_bash", "error" => "syntax error")
    end

    it "caps retained failures at MAX_FAILURES" do
      (described_class::MAX_FAILURES + 5).times { |i| log.record_failure("tool_#{i}", "err") }
      expect(log.failures.length).to eq(described_class::MAX_FAILURES)
    end

    it "retains the most recent failures when capping" do
      (described_class::MAX_FAILURES + 3).times { |i| log.record_failure("tool", "err_#{i}") }
      last_error = log.failures.last["error"]
      expect(last_error).to eq("err_#{described_class::MAX_FAILURES + 2}")
    end
  end

  describe "#append_supervisor_intervention" do
    it "appends the intervention to the summary" do
      original = log.summary
      log.append_supervisor_intervention("Try approach B")
      expect(log.summary).to include(original)
      expect(log.summary).to include("Try approach B")
    end

    it "truncates very long content to 400 chars" do
      long_content = "x" * 1000
      log.append_supervisor_intervention(long_content)
      expect(log.summary.length).to be <= (log.summary.index("Supervisor:") + 20 + 400)
    end
  end

  describe "#set_variable" do
    it "stores the key-value pair" do
      log.set_variable("last_executed_tool", "read_source_file")
      expect(log.variables["last_executed_tool"]).to eq("read_source_file")
    end

    it "coerces symbol keys to strings" do
      log.set_variable(:foo, "bar")
      expect(log.variables["foo"]).to eq("bar")
    end
  end

  describe "#reset!" do
    it "clears all state" do
      log.update_success("execute_bash")
      log.record_failure("read_source_file", "not found")
      log.reset!

      expect(log.summary).to include("Initializing")
      expect(log.variables).to eq({})
      expect(log.failures).to eq([])
    end
  end
end
