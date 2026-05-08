# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::LockManager do
  def open_stack
    Dir.mktmpdir("lock-mgr") do |root|
      registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      yield registry.runtime, OllamaAgent::Runtime::FencingAllocator.new(registry.runtime), root
    end
  end

  it "acquires a new lease with fencing and lease tokens" do
    open_stack do |db, fence, _root|
      lm = described_class.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      got = lm.acquire(scope: "s1", holder: "a", ttl_epochs: 100, current_epoch: 0)

      expect(got).to be_a(Hash)
      expect(got[:lease_token]).to be_a(Integer)
      expect(got[:fencing_token]).to eq(1)
    end
  end

  it "returns :held when another holder holds an active lease" do
    open_stack do |db, fence, _root|
      lm = described_class.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      expect(
        lm.acquire(scope: "path/x", holder: "alice", ttl_epochs: 50, current_epoch: 0)
      ).to be_a(Hash)

      expect(lm.acquire(scope: "path/x", holder: "bob", ttl_epochs: 50, current_epoch: 0)).to eq(:held)
    end
  end

  it "allows the same holder to re-enter an active lease without replacing tokens" do
    open_stack do |db, fence, _root|
      lm = described_class.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      first = lm.acquire(scope: "r", holder: "alice", ttl_epochs: 50, current_epoch: 0)
      second = lm.acquire(scope: "r", holder: "alice", ttl_epochs: 50, current_epoch: 0)

      expect(second).to eq(first)
    end
  end

  it "recaptures after expiry with a fresh lease and higher fencing token" do
    open_stack do |db, fence, _root|
      lm = described_class.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      first = lm.acquire(scope: "scope-z", holder: "a", ttl_epochs: 10, current_epoch: 0)
      fence_after_first = first[:fencing_token]

      second = lm.acquire(scope: "scope-z", holder: "b", ttl_epochs: 10, current_epoch: 50)

      expect(second).to be_a(Hash)
      expect(second[:fencing_token]).to be > fence_after_first
      expect(second[:lease_token]).not_to eq(first[:lease_token])
    end
  end

  it "returns :stale_lease when ttl_epochs is below 1" do
    open_stack do |db, fence, _root|
      lm = described_class.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      expect(lm.acquire(scope: "x", holder: "a", ttl_epochs: 0, current_epoch: 0)).to eq(:stale_lease)
    end
  end

  it "renews an active lease" do
    open_stack do |db, fence, _root|
      lm = described_class.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      got = lm.acquire(scope: "k", holder: "a", ttl_epochs: 10, current_epoch: 0)

      expect(
        lm.renew(scope: "k", holder: "a", lease_token: got[:lease_token], ttl_epochs: 20, current_epoch: 5)
      ).to eq(:ok)

      row = db.get_first_row("SELECT expires_at_epoch FROM locks WHERE scope = ?", ["k"])
      expect(row["expires_at_epoch"].to_i).to eq(25)
    end
  end

  it "returns :expired on renew when the lease is past expiry" do
    open_stack do |db, fence, _root|
      lm = described_class.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      got = lm.acquire(scope: "k2", holder: "a", ttl_epochs: 5, current_epoch: 0)

      expect(
        lm.renew(scope: "k2", holder: "a", lease_token: got[:lease_token], ttl_epochs: 10, current_epoch: 10)
      ).to eq(:expired)
    end
  end

  it "returns :stale_lease on renew when the lease token does not match" do
    open_stack do |db, fence, _root|
      lm = described_class.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      got = lm.acquire(scope: "k3", holder: "a", ttl_epochs: 50, current_epoch: 0)

      expect(
        lm.renew(scope: "k3", holder: "a", lease_token: got[:lease_token] + 1, ttl_epochs: 10,
                 current_epoch: 1)
      ).to eq(:stale_lease)
    end
  end

  it "releases a held lock" do
    open_stack do |db, fence, _root|
      lm = described_class.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      got = lm.acquire(scope: "rel", holder: "a", ttl_epochs: 50, current_epoch: 0)

      expect(lm.release(scope: "rel", holder: "a", lease_token: got[:lease_token])).to eq(:ok)
      expect(db.get_first_row("SELECT * FROM locks WHERE scope = ?", ["rel"])).to be_nil
    end
  end

  it "returns :stale_lease on release when the lease token is wrong" do
    open_stack do |db, fence, _root|
      lm = described_class.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      got = lm.acquire(scope: "rel2", holder: "a", ttl_epochs: 50, current_epoch: 0)

      expect(lm.release(scope: "rel2", holder: "a", lease_token: got[:lease_token] + 1)).to eq(:stale_lease)
      expect(db.get_first_row("SELECT * FROM locks WHERE scope = ?", ["rel2"])).not_to be_nil
    end
  end

  it "prunes expired rows" do
    open_stack do |db, fence, _root|
      lm = described_class.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      lm.acquire(scope: "old", holder: "a", ttl_epochs: 5, current_epoch: 0)
      lm.acquire(scope: "new", holder: "b", ttl_epochs: 100, current_epoch: 0)

      deleted = lm.prune_expired(current_epoch: 10)
      expect(deleted).to eq(1)
      expect(db.get_first_row("SELECT * FROM locks WHERE scope = ?", ["old"])).to be_nil
      expect(db.get_first_row("SELECT * FROM locks WHERE scope = ?", ["new"])).not_to be_nil
    end
  end

  it "increments fencing tokens monotonically across serial acquisitions on one scope" do
    open_stack do |db, fence, _root|
      lm = described_class.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      tokens = []
      3.times do |i|
        got = lm.acquire(scope: "mono", holder: "w", ttl_epochs: 10, current_epoch: i * 20)
        tokens << got[:fencing_token]
        expect(lm.release(scope: "mono", holder: "w", lease_token: got[:lease_token])).to eq(:ok)
      end
      expect(tokens).to eq(tokens.sort.uniq)
      expect(tokens[1]).to be > tokens[0]
      expect(tokens[2]).to be > tokens[1]
    end
  end
end
