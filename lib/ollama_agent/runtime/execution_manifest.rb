# frozen_string_literal: true

require "json"
require "securerandom"

module OllamaAgent
  module Runtime
    # Manifest record representing one execution attempt and lineage.
    class ExecutionManifest
      attr_reader :id, :parent_manifest_id, :workspace_fingerprint, :created_at, :metadata

      def initialize(
        parent_manifest_id:,
        workspace_fingerprint:,
        created_at:,
        metadata: {},
        id: SecureRandom.uuid
      )
        @id = id
        @parent_manifest_id = parent_manifest_id
        @workspace_fingerprint = workspace_fingerprint
        @created_at = created_at
        @metadata = metadata.dup
      end

      def to_h
        {
          "id" => id,
          "parent_manifest_id" => parent_manifest_id,
          "workspace_fingerprint" => workspace_fingerprint,
          "created_at" => created_at,
          "metadata" => metadata
        }
      end

      def to_json(*)
        JSON.generate(to_h, *)
      end
    end
  end
end
