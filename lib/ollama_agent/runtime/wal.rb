# frozen_string_literal: true

require "json"

require_relative "event_store"

module OllamaAgent
  module Runtime
    # Mutation-focused view over {EventStore} (+kind+ = +mutation+).
    class WAL
      MUTATION_KIND = EventStore::MUTATION_KIND
      MUTATION_STEP_KIND = "mutation_step"

      # @param event_store [EventStore]
      def initialize(event_store)
        @event_store = event_store
      end

      # @return [:inserted, :duplicate] see {EventStore#append}
      def append_mutation(manifest_id:, logical_stamp:, payload:, intent_hash: nil, created_at: nil)
        @event_store.append(
          manifest_id: manifest_id,
          logical_stamp: logical_stamp,
          kind: MUTATION_KIND,
          payload: payload,
          intent_hash: intent_hash,
          created_at: created_at
        )
      end

      # Fine-grained mutation progress (no +intent_hash+; not deduped).
      def append_mutation_step(manifest_id:, logical_stamp:, step:, data: {})
        blob = JSON.generate(data.merge("step" => step))
        @event_store.append(
          manifest_id: manifest_id,
          logical_stamp: logical_stamp,
          kind: MUTATION_STEP_KIND,
          payload: blob,
          intent_hash: nil,
          created_at: nil
        )
      end

      # Yields mutation rows for +manifest_id+ in stable +id+ order.
      def replay(manifest_id:)
        return to_enum(:replay, manifest_id: manifest_id) unless block_given?

        @event_store.each_for(manifest_id: manifest_id) do |row|
          yield row if row["kind"] == MUTATION_KIND
        end
      end
    end
  end
end
