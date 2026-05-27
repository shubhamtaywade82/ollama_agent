# frozen_string_literal: true

require "spec_helper"
require "digest"

RSpec.describe OllamaAgent::State::TreeDigest do
  describe ".append_entry" do
    it "produces different digests for ambiguous path/content boundaries" do
      left = Digest::SHA256.new
      described_class.append_entry(left, "lib/sample.rb", "X")

      right = Digest::SHA256.new
      described_class.append_entry(right, "lib/sample", ".rbX")

      expect(right.hexdigest).not_to eq(left.hexdigest)
    end
  end
end
