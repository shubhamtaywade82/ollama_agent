# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe OllamaAgent::Runtime::KernelHealth do
  def health_for(tmp, rollback: nil)
    reg = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: tmp)
    blobs = OllamaAgent::Runtime::BlobStore.new(kernel_dir: reg.kernel_dir)
    described_class.new(db_registry: reg, blob_store: blobs, rollback_signals: rollback)
  end

  it "returns ok when databases, blobs, and schema versions are healthy" do
    Dir.mktmpdir("kernel-health-ok") do |tmp|
      out = health_for(tmp).check
      expect(out[:status]).to eq(:ok)
      expect(out[:checks].values.all? { |c| c[:ok] }).to be(true)
    end
  end

  it "returns degraded when schema_migrations lag behind disk migrations" do
    Dir.mktmpdir("kernel-health-schema") do |tmp|
      reg = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: tmp)
      reg.runtime
      db = SQLite3::Database.new(File.join(reg.kernel_dir, "runtime.db"))
      db.execute("DELETE FROM schema_migrations WHERE version = ?", 2)
      db.close

      blobs = OllamaAgent::Runtime::BlobStore.new(kernel_dir: reg.kernel_dir)
      out = described_class.new(db_registry: reg, blob_store: blobs).check
      expect(out[:status]).to eq(:degraded)
      expect(out[:checks][:schema_migrations][:ok]).to be(false)
    end
  end

  it "returns degraded when rollback_signals reports a trigger" do
    Dir.mktmpdir("kernel-health-rollback") do |tmp|
      signals = OllamaAgent::Runtime::RollbackSignals.new
      signals.record(event: :mutation_failure)
      signals.record(event: :mutation_failure)
      signals.record(event: :mutation_success)
      signals.record(event: :mutation_success)
      signals.record(event: :mutation_success)
      signals.record(event: :mutation_success)
      signals.record(event: :mutation_success)
      signals.record(event: :mutation_success)
      signals.record(event: :mutation_success)
      signals.record(event: :mutation_success)
      signals.record(event: :mutation_success)

      out = health_for(tmp, rollback: signals).check
      expect(out[:status]).to eq(:degraded)
      expect(out[:checks][:rollback_signals][:ok]).to be(false)
    end
  end

  it "returns unhealthy when the event store connection cannot execute SQL" do
    Dir.mktmpdir("kernel-health-bad-db") do |tmp|
      reg = OllamaAgent::Runtime::DatabaseRegistry.new(root_dir: tmp)
      bad = Object.new

      def bad.execute(*)
        raise SQLite3::Exception, "forced"
      end

      allow(reg).to receive_messages(event_store: bad, runtime: bad)

      blobs = OllamaAgent::Runtime::BlobStore.new(kernel_dir: reg.kernel_dir)
      out = described_class.new(db_registry: reg, blob_store: blobs).check
      expect(out[:status]).to eq(:unhealthy)
      expect(out[:checks][:event_store][:ok]).to be(false)
    end
  end
end
