# frozen_string_literal: true

require_relative "../security/ownership_compiler"
require_relative "atomic_mutator"
require_relative "blob_store"
require_relative "compensation_engine"
require_relative "compensation_manifest"
require_relative "database_registry"
require_relative "event_store"
require_relative "fencing_allocator"
require_relative "integration_queue"
require_relative "intent_reservation"
require_relative "isolated_validator"
require_relative "lock_manager"
require_relative "post_condition_verifier"
require_relative "saga_coordinator"
require_relative "saga_recovery_daemon"
require_relative "wal"
require_relative "kernel_event_logger"

module OllamaAgent
  module Runtime
    # Wires concrete runtime dependencies for {KernelPipeline}.
    module KernelPipelineAssembly
      module_function

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists -- one-shot wiring; mirrors constructor list
      def build_for_workspace(workspace_root:, ownership_index: nil, clock_epoch_provider: nil,
                              isolated_validator: nil, hooks: nil, logger: nil, rollback_signals: nil)
        root = File.expand_path(workspace_root.to_s)
        index = ownership_index || default_ownership_index(root)
        clock = clock_epoch_provider || ticking_clock
        registry = DatabaseRegistry.new(root_dir: root)
        db = registry.runtime
        fence = FencingAllocator.new(db)
        kernel_dir = File.join(root, ".ollama_agent", "kernel")
        blob_store = BlobStore.new(kernel_dir: kernel_dir)
        wal = WAL.new(EventStore.new(registry.event_store))
        atomic_mutator = AtomicMutator.new(
          workspace_root: root,
          ownership_index: index,
          fencing_allocator: fence,
          wal: wal,
          blob_store: blob_store
        )
        intent_reservation = IntentReservation.new(db)
        lock_manager = LockManager.new(db: db, fencing_allocator: fence, clock_epoch: 0)
        saga_coordinator = SagaCoordinator.new(
          db: db,
          intent_reservation: intent_reservation,
          lock_manager: lock_manager,
          atomic_mutator: atomic_mutator,
          wal: wal,
          clock_epoch_provider: clock
        )
        compensation_manifest = CompensationManifest.new(db)
        compensation_engine = CompensationEngine.new(
          blob_store: blob_store,
          compensation_manifest: compensation_manifest,
          atomic_mutator: atomic_mutator,
          fencing_allocator: fence
        )
        saga_recovery_daemon = SagaRecoveryDaemon.new(
          db: db,
          saga_coordinator: saga_coordinator,
          compensation_engine: compensation_engine,
          clock_epoch_provider: clock
        )
        validator = isolated_validator || default_validator(root, wal)
        post_condition_verifier = PostConditionVerifier.new(isolated_validator: validator)
        integration_queue = IntegrationQueue.new(db)
        resolved_hooks = hooks
        resolved_hooks = KernelEventLogger.new(logger: logger, rollback_signals: rollback_signals) if resolved_hooks.nil? && !logger.nil?
        KernelPipeline.new(
          workspace_root: root,
          database_registry: registry,
          ownership_index: index,
          fencing_allocator: fence,
          lock_manager: lock_manager,
          intent_reservation: intent_reservation,
          atomic_mutator: atomic_mutator,
          saga_coordinator: saga_coordinator,
          isolated_validator: validator,
          post_condition_verifier: post_condition_verifier,
          blob_store: blob_store,
          compensation_manifest: compensation_manifest,
          compensation_engine: compensation_engine,
          saga_recovery_daemon: saga_recovery_daemon,
          integration_queue: integration_queue,
          wal: wal,
          clock_epoch_provider: clock,
          hooks: resolved_hooks
        )
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists

      def default_ownership_index(root)
        path = File.join(root, "config", "ollama_agent", "owners.yml")
        path = File.join(OllamaAgent.gem_root, "config", "ollama_agent", "owners.yml") unless File.file?(path)

        OllamaAgent::Security::OwnershipCompiler.new.compile(path: path)
      end

      def ticking_clock
        counter = [0]
        proc { counter[0] += 1 }
      end

      def default_validator(root, wal)
        IsolatedValidator.new(
          image: ENV.fetch("OLLAMA_AGENT_VALIDATOR_IMAGE", "ollama_agent-verification-sandbox:latest"),
          workspace_root: root,
          timeout_epochs: ENV.fetch("OLLAMA_AGENT_VALIDATOR_TIMEOUT_SEC", "300").to_i,
          wal: wal
        )
      end
    end
  end
end
