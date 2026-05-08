# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::SagaCoordinator do
  # rubocop:disable Metrics/MethodLength -- builds isolated kernel DB + coordinator
  def build_coordinator(root)
    tick = [0]
    registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
    db = registry.runtime
    ir = OllamaAgent::Runtime::IntentReservation.new(db)
    lm = OllamaAgent::Runtime::LockManager.new(
      db: db,
      fencing_allocator: OllamaAgent::Runtime::FencingAllocator.new(db),
      clock_epoch: 0
    )
    coord = described_class.new(
      db: db,
      intent_reservation: ir,
      lock_manager: lm,
      atomic_mutator: instance_double(OllamaAgent::Runtime::AtomicMutator),
      wal: instance_double(OllamaAgent::Runtime::WAL),
      clock_epoch_provider: proc { tick[0] += 1 }
    )
    [coord, db, ir]
  end
  # rubocop:enable Metrics/MethodLength

  def with_workspace(&block)
    Dir.mktmpdir("saga-co-spec", &block)
  end

  describe "#start" do
    it "returns :reserved and records the saga plus bootstrap transition" do
      with_workspace do |root|
        coord, db, _ir = build_coordinator(root)
        expect(
          coord.start(
            manifest_id: "m1",
            intent_hash: "ih1",
            planned_scopes: %w[lib/a lib/b],
            supervisor_lease: "sup-1",
            metadata: { "k" => "v" }
          )
        ).to eq(:reserved)

        row = db.get_first_row("SELECT * FROM sagas WHERE manifest_id = ?", ["m1"])
        expect(row["state"]).to eq("reserved")
        expect(row["terminal"].to_i).to eq(0)
        expect(row["intent_hash"]).to eq("ih1")
        expect(JSON.parse(row["planned_scopes"])).to eq(%w[lib/a lib/b])
        expect(row["supervisor_lease"]).to eq("sup-1")
        expect(JSON.parse(row["metadata"])).to eq("k" => "v")

        tr = db.get_first_row("SELECT * FROM saga_transitions WHERE manifest_id = ?", ["m1"])
        expect(tr["from_state"]).to eq(described_class::START_FROM)
        expect(tr["to_state"]).to eq("reserved")
      end
    end

    it "returns :duplicate when intent_hash is already reserved" do
      with_workspace do |root|
        coord, db, _ir = build_coordinator(root)
        coord.start(manifest_id: "m1", intent_hash: "dup", planned_scopes: ["x"], metadata: {})
        expect(
          coord.start(manifest_id: "m2", intent_hash: "dup", planned_scopes: ["y"], metadata: {})
        ).to eq(:duplicate)
        expect(db.get_first_value("SELECT COUNT(*) FROM sagas")).to eq(1)
      end
    end

    it "returns :conflict when scopes overlap an existing reservation" do
      with_workspace do |root|
        coord, db, _ir = build_coordinator(root)
        coord.start(manifest_id: "m1", intent_hash: "a", planned_scopes: %w[lib/x], metadata: {})
        expect(
          coord.start(manifest_id: "m2", intent_hash: "b", planned_scopes: %w[lib/x lib/y], metadata: {})
        ).to eq(:conflict)
        expect(db.get_first_value("SELECT COUNT(*) FROM sagas")).to eq(1)
      end
    end
  end

  describe "#advance" do
    it "advances through the happy path to committed" do
      with_workspace do |root|
        coord, db, _ir = build_coordinator(root)
        coord.start(manifest_id: "m1", intent_hash: "h", planned_scopes: ["z"], metadata: {})
        steps = %w[locked mutations_applied verified integration_queued committed]
        steps.each do |st|
          expect(coord.advance(manifest_id: "m1", to_state: st, reason: st)).to eq(:ok)
        end
        snapshot = coord.state_of(manifest_id: "m1")
        expect(snapshot[:state]).to eq("committed")
        expect(snapshot[:terminal]).to be(true)
        expect(db.get_first_value("SELECT COUNT(*) FROM saga_transitions WHERE manifest_id = ?", ["m1"]).to_i).to eq(6)
        expect(db.get_first_value("SELECT COUNT(*) FROM intent_reservations").to_i).to eq(0)
      end
    end

    it "returns :illegal_transition for a disallowed edge" do
      with_workspace do |root|
        coord, _db, _ir = build_coordinator(root)
        coord.start(manifest_id: "m1", intent_hash: "h", planned_scopes: ["z"], metadata: {})
        expect(coord.advance(manifest_id: "m1", to_state: "committed", reason: "skip")).to eq(:illegal_transition)
      end
    end

    it "returns :sealed when the saga is already terminal" do
      with_workspace do |root|
        coord, _db, _ir = build_coordinator(root)
        coord.start(manifest_id: "m1", intent_hash: "h", planned_scopes: ["z"], metadata: {})
        %w[locked mutations_applied verified integration_queued committed].each do |st|
          coord.advance(manifest_id: "m1", to_state: st)
        end
        expect(coord.advance(manifest_id: "m1", to_state: "compensated")).to eq(:sealed)
      end
    end

    it "returns :missing for an unknown manifest" do
      with_workspace do |root|
        coord, _db, _ir = build_coordinator(root)
        expect(coord.advance(manifest_id: "nope", to_state: "locked")).to eq(:missing)
      end
    end
  end

  describe "#compensate" do
    %w[reserved locked mutations_applied verified integration_queued].each do |state|
      it "moves from #{state} to compensated and releases the intent reservation" do
        with_workspace do |root|
          coord, _db, ir = build_coordinator(root)
          manifest_id = "m-#{state}"
          intent = "intent-#{state}"
          coord.start(manifest_id: manifest_id, intent_hash: intent, planned_scopes: ["solo-#{state}"], metadata: {})
          walk_to_state(coord, manifest_id, state)
          expect(coord.compensate(manifest_id: manifest_id, reason: "abort")).to eq(:ok)
          snap = coord.state_of(manifest_id: manifest_id)
          expect(snap[:state]).to eq("compensated")
          expect(snap[:terminal]).to be(true)
          expect(ir.release(intent_hash: intent, manifest_id: manifest_id)).to eq(:missing)
        end
      end
    end

    it "returns :sealed when called again on a terminal saga" do
      with_workspace do |root|
        coord, _db, _ir = build_coordinator(root)
        coord.start(manifest_id: "m1", intent_hash: "h", planned_scopes: ["z"], metadata: {})
        expect(coord.compensate(manifest_id: "m1", reason: "r1")).to eq(:ok)
        expect(coord.compensate(manifest_id: "m1", reason: "r2")).to eq(:sealed)
      end
    end

    it "returns :missing for an unknown manifest" do
      with_workspace do |root|
        coord, _db, _ir = build_coordinator(root)
        expect(coord.compensate(manifest_id: "ghost", reason: "x")).to eq(:missing)
      end
    end
  end

  def walk_to_state(coord, manifest_id, target_state)
    return if target_state == "reserved"

    sequence = %w[locked mutations_applied verified integration_queued]
    idx = sequence.index(target_state)
    raise ArgumentError, "unsupported #{target_state}" unless idx

    sequence[0..idx].each do |st|
      coord.advance(manifest_id: manifest_id, to_state: st, reason: "walk")
    end
  end
end
