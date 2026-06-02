# frozen_string_literal: true

require "spec_helper"
require "timeout"

# rubocop:disable RSpec/ExampleLength -- stress harness: threads + joins + SQL assertions
RSpec.describe OllamaAgent::Runtime::SagaCoordinator, :concurrency do
  # rubocop:disable Metrics/MethodLength -- builds isolated coordinator + shared mutex (SQLite single-writer)
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
    [coord, db]
  end
  # rubocop:enable Metrics/MethodLength

  it "commits 256 interleaved sagas when each coordinator call is mutex-serialized" do
    thread_count = 8
    sagas_per_thread = 32
    total = thread_count * sagas_per_thread

    Dir.mktmpdir("saga-co-concurrency") do |root|
      coord, db = build_coordinator(root)
      mx = Mutex.new
      errors = []

      threads = thread_count.times.map do |tid|
        Thread.new do
          sagas_per_thread.times do |idx|
            manifest_id = "m-#{tid}-#{idx}"
            scope = "lib/scope-#{tid}-#{idx}"
            intent_hash = "ih-#{tid}-#{idx}"
            mx.synchronize do
              started = coord.start(
                manifest_id: manifest_id,
                intent_hash: intent_hash,
                planned_scopes: [scope],
                metadata: {}
              )
              raise "start #{started} for #{manifest_id}" unless started == :reserved

              %w[locked mutations_applied verified integration_queued committed].each do |st|
                adv = coord.advance(manifest_id: manifest_id, to_state: st, reason: st)
                raise "advance #{st} -> #{adv} for #{manifest_id}" unless adv == :ok
              end
            end
          end
        rescue StandardError => e
          errors << e
        end
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
      threads.each do |th|
        while th.alive?
          raise Timeout::Error, "saga concurrency join exceeded 60s wall clock" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          th.join(0.05)
        end
      end

      expect(errors).to eq([])
      expect(db.get_first_value("SELECT COUNT(*) FROM sagas").to_i).to eq(total)
      expect(db.get_first_value("SELECT COUNT(*) FROM saga_transitions").to_i).to eq(total * 6)
      expect(db.get_first_value("SELECT COUNT(*) FROM sagas WHERE state = 'committed'").to_i).to eq(total)
    end
  end
end
# rubocop:enable RSpec/ExampleLength
