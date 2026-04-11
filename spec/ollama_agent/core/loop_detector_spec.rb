# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Core::LoopDetector do
  subject(:detector) { described_class.new(window: 2, threshold: 2) }

  describe "#record!" do
    it "appends to history" do
      detector.record!("read_file", { path: "a.rb" })
      expect(detector.history).not_to be_empty
    end
  end

  describe "#loop_detected?" do
    context "when no loop" do
      it "returns false with diverse calls" do
        detector.record!("read_file",   { path: "a.rb" })
        detector.record!("edit_file",   { path: "b.rb" })
        detector.record!("search_code", { query: "foo" })
        expect(detector).not_to be_loop_detected
      end
    end

    context "when pattern repeats enough times" do
      before do
        2.times do
          detector.record!("read_file",  { path: "a.rb" })
          detector.record!("write_file", { path: "a.rb" })
        end
      end

      it "detects the loop" do
        expect(detector).to be_loop_detected
      end

      it "provides a summary" do
        expect(detector.loop_summary).to include("Loop detected")
      end
    end

    context "when below threshold" do
      it "returns false with one repetition" do
        detector.record!("read_file",  { path: "a.rb" })
        detector.record!("write_file", { path: "a.rb" })
        expect(detector).not_to be_loop_detected
      end
    end
  end

  describe "#reset!" do
    it "clears history" do
      2.times do
        detector.record!("read_file", {})
        detector.record!("edit_file", {})
      end
      detector.reset!
      expect(detector.history).to be_empty
      expect(detector).not_to be_loop_detected
    end
  end
end
