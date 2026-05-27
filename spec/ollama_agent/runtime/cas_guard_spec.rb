# frozen_string_literal: true

require "spec_helper"
require "digest"

RSpec.describe OllamaAgent::Runtime::CASGuard do
  def sha256_hex(bytes)
    Digest::SHA256.hexdigest(bytes.b)
  end

  describe ".check" do
    it "matches the documented matrix of outcomes" do
      new_file = described_class::NEW_FILE_SENTINEL
      rows = [
        { current: "a", expected: sha256_hex("a"), want: :ok },
        { current: nil, expected: new_file, want: :ok },
        { current: "x", expected: new_file, want: :precondition_failed },
        { current: "a", expected: sha256_hex("b"), want: :precondition_failed },
        { current: nil, expected: sha256_hex(""), want: :ok },
        { current: "", expected: sha256_hex(""), want: :ok },
        { current: "a", expected: sha256_hex("a"), fencing_token_provided: 9, fencing_token_current: 2,
          want: :stale_token }
      ]

      rows.each do |row|
        got = described_class.check(
          current_content_or_nil: row[:current],
          expected_pre_hash: row[:expected],
          fencing_token_provided: row.fetch(:fencing_token_provided, 1),
          fencing_token_current: row.fetch(:fencing_token_current, 2)
        )
        expect(got).to eq(row[:want]), "failed row #{row.inspect}"
      end
    end

    it "rejects fencing tokens below 1" do
      expect(
        described_class.check(
          current_content_or_nil: nil,
          expected_pre_hash: described_class::NEW_FILE_SENTINEL,
          fencing_token_provided: 0,
          fencing_token_current: 2
        )
      ).to eq(:stale_token)
    end

    it "rejects allocated tokens below 2" do
      expect(
        described_class.check(
          current_content_or_nil: nil,
          expected_pre_hash: described_class::NEW_FILE_SENTINEL,
          fencing_token_provided: 1,
          fencing_token_current: 1
        )
      ).to eq(:stale_token)
    end
  end
end
