# frozen_string_literal: true

module OllamaAgent
  module Topology
    # Typed intermediate representation for topology extraction and linking.
    module IR
      # Shared metadata for all topology IR +Data+ nodes.
      # Each concrete node repeats these members first: +kind+, +source_path+, +source_line+,
      # +origin_extractor_version+.
      module Node
        MEMBERS = %i[kind source_path source_line origin_extractor_version].freeze
      end

      def self.deep_freeze_hashes(list)
        Array(list).map { |h| deep_freeze_hash(h) }.freeze
      end

      def self.deep_freeze_hash(obj)
        case obj
        when Hash
          obj.transform_keys(&:to_s).transform_values { |v| deep_freeze_hash(v) }.freeze
        when Array
          obj.map { |v| deep_freeze_hash(v) }.freeze
        else
          obj
        end
      end
    end
  end
end
