# frozen_string_literal: true

require "digest"
require "yaml"

require_relative "ownership_compile_validators"
require_relative "ownership_rule_tree_flattener"
require_relative "ownership_index"

module OllamaAgent
  module Security
    # Parses and validates owners rules, then builds an {OwnershipIndex}.
    class OwnershipCompiler
      # @param yaml_string [String, nil]
      # @param path [String, nil]
      # @return [OwnershipIndex]
      def compile(yaml_string: nil, path: nil)
        @source_bytes = read_source(yaml_string: yaml_string, path: path)
        rules = rules_from_tree(parse_yaml(@source_bytes))
        flat = OwnershipRuleTreeFlattener.new.flatten(rules)
        OwnershipCompileValidators.validate!(flat)
        index_from_flat(flat)
      end

      # @return [String] hex SHA256 of the last compiled source bytes
      def source_sha256
        raise OwnershipCompileError, "compile first" unless @source_bytes

        Digest::SHA256.hexdigest(@source_bytes)
      end

      private

      def read_source(yaml_string:, path:)
        raise ArgumentError, "provide yaml_string: or path:" unless yaml_string || path

        path ? File.binread(path) : yaml_string.to_s.b
      end

      def rules_from_tree(tree)
        rules = extract_rules(tree)
        raise OwnershipCompileError, "rules must be a non-empty array" unless rules.is_a?(Array) && !rules.empty?

        rules
      end

      def index_from_flat(flat)
        sha = Digest::SHA256.hexdigest(@source_bytes)
        nodes = flat.map { |row| ownership_node_from(row) }
        OwnershipIndex.new(nodes, source_sha256: sha)
      end

      def ownership_node_from(row)
        OwnershipIndex.node(
          prefix: row[:prefix],
          owner: row[:owner],
          mutable_in_modes: row[:mutable_in_modes],
          criticality: row[:criticality],
          forbidden: row[:forbidden]
        )
      end

      def parse_yaml(bytes)
        YAML.safe_load(
          bytes,
          permitted_classes: [Symbol],
          permitted_symbols: [],
          aliases: true
        )
      rescue Psych::SyntaxError => e
        raise OwnershipCompileError, e.message
      end

      def extract_rules(tree)
        case tree
        when Array
          tree
        when Hash
          r = tree["rules"] || tree[:rules]
          raise OwnershipCompileError, "missing top-level 'rules'" unless r

          r
        else
          raise OwnershipCompileError, "owners YAML must be a mapping with 'rules' or a rules array"
        end
      end
    end
  end
end
