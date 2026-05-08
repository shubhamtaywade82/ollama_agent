# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SagaCoordinator recovery after coordinator loss", :concurrency do
  it "exposes orphaned active sagas to a fresh coordinator and compensates safely" do
    tick = [0]
    clock = -> { tick[0] += 1 }
    Dir.mktmpdir("saga-recovery") do |root|
      registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      db = registry.runtime
      ir = OllamaAgent::Runtime::IntentReservation.new(db)
      fence = OllamaAgent::Runtime::FencingAllocator.new(db)
      lm = OllamaAgent::Runtime::LockManager.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      mutator = instance_double(OllamaAgent::Runtime::AtomicMutator)
      wal = instance_double(OllamaAgent::Runtime::WAL)

      coordinator1 = OllamaAgent::Runtime::SagaCoordinator.new(
        db: db,
        intent_reservation: ir,
        lock_manager: lm,
        atomic_mutator: mutator,
        wal: wal,
        clock_epoch_provider: clock
      )

      expect(
        coordinator1.start(
          manifest_id: "orphan-m",
          intent_hash: "orphan-intent",
          planned_scopes: %w[lib/recovery],
          metadata: {}
        )
      ).to eq(:reserved)
      expect(coordinator1.advance(manifest_id: "orphan-m", to_state: "locked")).to eq(:ok)
      expect(coordinator1.advance(manifest_id: "orphan-m", to_state: "mutations_applied")).to eq(:ok)

      coordinator2 = OllamaAgent::Runtime::SagaCoordinator.new(
        db: db,
        intent_reservation: ir,
        lock_manager: lm,
        atomic_mutator: mutator,
        wal: wal,
        clock_epoch_provider: clock
      )

      active = coordinator2.each_active.to_a
      expect(active).to eq([{ manifest_id: "orphan-m", state: "mutations_applied" }])

      expect(coordinator2.compensate(manifest_id: "orphan-m", reason: "simulated kill")).to eq(:ok)
      expect(coordinator2.compensate(manifest_id: "orphan-m", reason: "retry")).to eq(:sealed)
      expect(coordinator2.each_active.to_a).to eq([])
      expect(ir.release(intent_hash: "orphan-intent", manifest_id: "orphan-m")).to eq(:missing)
    end
  end
end
