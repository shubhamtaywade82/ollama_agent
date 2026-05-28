# frozen_string_literal: true

require "spec_helper"
require "ollama_agent/providers/rate_window"

RSpec.describe OllamaAgent::Providers::RateWindow do
  subject(:window) { described_class.new(window_seconds: 60) }

  describe "#record and #current_rate" do
    it "sums all recorded values within the window" do
      window.record(1)
      window.record(500)
      window.record(250)
      expect(window.current_rate).to eq(751)
    end

    it "returns 0 when no values recorded" do
      expect(window.current_rate).to eq(0)
    end

    it "defaults record value to 1" do
      window.record
      expect(window.current_rate).to eq(1)
    end
  end

  describe "#count" do
    it "returns the number of entries" do
      window.record(100)
      window.record(200)
      expect(window.count).to eq(2)
    end
  end

  describe "window expiry" do
    it "excludes entries older than the window" do
      old_entry = { at: Time.now - 61, value: 9999 }
      window.instance_variable_get(:@entries) << old_entry
      window.record(1)
      # current_rate should only count the fresh entry, not the expired one
      expect(window.current_rate).to eq(1)
    end
  end

  describe "thread safety" do
    it "handles concurrent writes without raising" do
      threads = 20.times.map { Thread.new { window.record(1) } }
      threads.each(&:join)
      expect(window.current_rate).to eq(20)
    end
  end
end
