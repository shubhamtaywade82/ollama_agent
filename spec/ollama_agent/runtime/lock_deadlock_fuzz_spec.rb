# frozen_string_literal: true

require "spec_helper"
require "timeout"

RSpec.describe "LockManager deadlock fuzz", :concurrency do
  it "does not wedge under concurrent sorted acquire/release cycles" do
    scopes = %w[a b c d].freeze
    thread_count = 16
    cycle_count = 64

    Dir.mktmpdir("lock-fuzz") do |root|
      registry = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: root)
      db = registry.runtime
      fence = OllamaAgent::Runtime::FencingAllocator.new(db)
      lm = OllamaAgent::Runtime::LockManager.new(db: db, fencing_allocator: fence, clock_epoch: 0)

      # SQLite3::Database is not safe for concurrent use from multiple Ruby threads; the fuzz still
      # hammers scheduling/order discipline while serializing kernel calls (mirrors a single-writer runtime).
      mx = Mutex.new
      errors = []
      threads = thread_count.times.map do |idx|
        Thread.new do
          cycle_count.times do
            tokens = {}
            scopes.each do |scope|
              acquired = nil
              loop do
                mx.synchronize do
                  acquired = lm.acquire(scope: scope, holder: "worker-#{idx}", ttl_epochs: 1_000_000,
                                        current_epoch: 0)
                end
                break if acquired.is_a?(Hash)

                raise "unexpected acquire result: #{acquired.inspect}" unless acquired == :held

                Thread.pass
              end
              tokens[scope] = acquired
            end
            scopes.reverse_each do |scope|
              got = tokens[scope]
              release_result = mx.synchronize do
                lm.release(scope: scope, holder: "worker-#{idx}", lease_token: got[:lease_token])
              end
              raise "release failed: #{release_result}" unless release_result == :ok
            end
          end
        rescue StandardError => e
          errors << e
        end
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
      threads.each do |th|
        while th.alive?
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            raise Timeout::Error, "lock fuzz exceeded 30s wall clock"
          end

          th.join(0.05)
        end
      end

      expect(errors).to eq([])
      expect(db.get_first_value("SELECT COUNT(*) FROM locks").to_i).to eq(0)
    end
  end
end
