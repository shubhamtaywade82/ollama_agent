# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::SagaRecoveryDaemon do
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- test harness wiring
  def build_stack(root)
    tick = [0]
    clock = proc { tick[0] += 1 }
    registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
    db = registry.runtime
    ir = OllamaAgent::Runtime::IntentReservation.new(db)
    fence = OllamaAgent::Runtime::FencingAllocator.new(db)
    lm = OllamaAgent::Runtime::LockManager.new(db: db, fencing_allocator: fence, clock_epoch: 0)
    coordinator = OllamaAgent::Runtime::SagaCoordinator.new(
      db: db,
      intent_reservation: ir,
      lock_manager: lm,
      atomic_mutator: instance_double(OllamaAgent::Runtime::AtomicMutator),
      wal: instance_double(OllamaAgent::Runtime::WAL),
      clock_epoch_provider: clock
    )
    kernel = File.join(root, ".ollama_agent", "kernel")
    blob = OllamaAgent::Runtime::BlobStore.new(kernel_dir: kernel)
    cm = OllamaAgent::Runtime::CompensationManifest.new(db)
    engine = OllamaAgent::Runtime::CompensationEngine.new(
      blob_store: blob,
      compensation_manifest: cm,
      atomic_mutator: instance_double(OllamaAgent::Runtime::AtomicMutator),
      fencing_allocator: fence
    )
    daemon = described_class.new(
      db: db,
      saga_coordinator: coordinator,
      compensation_engine: engine,
      clock_epoch_provider: clock
    )
    [coordinator, engine, daemon, db, blob, cm, tick]
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  it "claims an orphan, restores via compensation engine, seals the saga, and drops the lease" do
    Dir.mktmpdir("recovery-happy") do |root|
      coordinator, _engine, daemon, db, blob, cm, tick = build_stack(root)
      target = File.join(root, "lib", "x.rb")
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite(target, "broken")
      hex = blob.put("good")

      expect(
        coordinator.start(
          manifest_id: "m-rec",
          intent_hash: "ih-rec",
          planned_scopes: ["solo"],
          metadata: {}
        )
      ).to eq(:reserved)
      expect(coordinator.advance(manifest_id: "m-rec", to_state: "locked")).to eq(:ok)

      cm.record(
        manifest_id: "m-rec",
        path: target,
        op: "atomic_write",
        pre_blob_sha: hex,
        pre_existed: 1,
        fencing_token: 1,
        logical_stamp: "c1"
      )

      tick[0] = 10
      outcomes = daemon.recover_orphans(holder: "worker-a", ttl_epochs: 100)
      expect(outcomes).to contain_exactly(hash_including(manifest_id: "m-rec", status: :recovered))

      snap = coordinator.state_of(manifest_id: "m-rec")
      expect(snap[:state]).to eq("compensated")
      expect(snap[:terminal]).to be(true)
      expect(File.binread(target)).to eq("good")
      expect(db.get_first_row("SELECT * FROM recovery_leases WHERE manifest_id = ?", ["m-rec"])).to be_nil
    end
  end

  it "skips recovery when another holder holds an active lease" do
    Dir.mktmpdir("recovery-lease") do |root|
      tick = [0]
      clock = proc { tick[0] += 1 }
      registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      db = registry.runtime
      ir = OllamaAgent::Runtime::IntentReservation.new(db)
      fence = OllamaAgent::Runtime::FencingAllocator.new(db)
      lm = OllamaAgent::Runtime::LockManager.new(db: db, fencing_allocator: fence, clock_epoch: 0)
      coordinator = OllamaAgent::Runtime::SagaCoordinator.new(
        db: db,
        intent_reservation: ir,
        lock_manager: lm,
        atomic_mutator: instance_double(OllamaAgent::Runtime::AtomicMutator),
        wal: instance_double(OllamaAgent::Runtime::WAL),
        clock_epoch_provider: clock
      )
      engine = instance_double(OllamaAgent::Runtime::CompensationEngine)
      allow(engine).to receive(:compensate).and_return({ restored: 0, missing: 0, errors: [] })
      daemon = described_class.new(
        db: db,
        saga_coordinator: coordinator,
        compensation_engine: engine,
        clock_epoch_provider: clock
      )

      expect(
        coordinator.start(
          manifest_id: "m-lease",
          intent_hash: "ih-l",
          planned_scopes: ["y"],
          metadata: {}
        )
      ).to eq(:reserved)

      tick[0] = 50
      db.execute(
        "INSERT INTO recovery_leases (manifest_id, holder, acquired_at_epoch, expires_at_epoch) " \
        "VALUES (?,?,?,?)",
        ["m-lease", "other", 0, 1_000]
      )

      outcomes = daemon.recover_orphans(holder: "worker-b", ttl_epochs: 10)
      expect(outcomes).to contain_exactly(hash_including(manifest_id: "m-lease", status: :lease_held_by_other))
      expect(engine).not_to have_received(:compensate)
    end
  end
end
