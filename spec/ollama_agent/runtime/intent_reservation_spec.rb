# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe OllamaAgent::Runtime::IntentReservation do
  def with_db
    Dir.mktmpdir("intent-res") do |root|
      registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      yield registry.runtime
    end
  end

  it "reserves a new intent" do
    with_db do |db|
      ir = described_class.new(db)
      expect(
        ir.reserve(
          intent_hash: "h1",
          manifest_id: "m1",
          scopes: %w[b a],
          current_epoch: 1
        )
      ).to eq(:reserved)

      row = db.get_first_row("SELECT * FROM intent_reservations WHERE intent_hash = ?", ["h1"])
      expect(JSON.parse(row["scopes"])).to eq(%w[a b])
    end
  end

  it "returns :duplicate when the intent_hash already exists" do
    with_db do |db|
      ir = described_class.new(db)
      ir.reserve(intent_hash: "h2", manifest_id: "m1", scopes: ["x"], current_epoch: 0)
      expect(
        ir.reserve(intent_hash: "h2", manifest_id: "m1", scopes: ["y"], current_epoch: 1)
      ).to eq(:duplicate)
    end
  end

  it "returns :conflict when scopes overlap an existing reservation" do
    with_db do |db|
      ir = described_class.new(db)
      ir.reserve(intent_hash: "i-a", manifest_id: "m1", scopes: %w[lib/app lib/models], current_epoch: 0)
      expect(
        ir.reserve(intent_hash: "i-b", manifest_id: "m2", scopes: %w[lib/models spec], current_epoch: 0)
      ).to eq(:conflict)
    end
  end

  it "releases a reservation" do
    with_db do |db|
      ir = described_class.new(db)
      ir.reserve(intent_hash: "h3", manifest_id: "m9", scopes: ["z"], current_epoch: 0)
      expect(ir.release(intent_hash: "h3", manifest_id: "m9")).to eq(:ok)
      expect(db.get_first_row("SELECT * FROM intent_reservations WHERE intent_hash = ?", ["h3"])).to be_nil
    end
  end

  it "returns :wrong_owner when manifest_id does not match" do
    with_db do |db|
      ir = described_class.new(db)
      ir.reserve(intent_hash: "h4", manifest_id: "owner-a", scopes: ["q"], current_epoch: 0)
      expect(ir.release(intent_hash: "h4", manifest_id: "owner-b")).to eq(:wrong_owner)
    end
  end

  it "returns :missing when the intent is absent" do
    with_db do |db|
      ir = described_class.new(db)
      expect(ir.release(intent_hash: "nope", manifest_id: "m1")).to eq(:missing)
    end
  end

  it "lists conflicting intent hashes for scopes" do
    with_db do |db|
      ir = described_class.new(db)
      ir.reserve(intent_hash: "c1", manifest_id: "m1", scopes: %w[a b], current_epoch: 0)
      ir.reserve(intent_hash: "c2", manifest_id: "m1", scopes: %w[c d], current_epoch: 0)

      expect(ir.conflicts_for(scopes: %w[b x]).sort).to eq(%w[c1])
      expect(ir.conflicts_for(scopes: ["z"]).sort).to eq([])
    end
  end
end
