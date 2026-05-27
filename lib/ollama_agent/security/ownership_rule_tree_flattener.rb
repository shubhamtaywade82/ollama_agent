# frozen_string_literal: true

require_relative "ownership_compile_validators"
require_relative "../runtime/execution_mode"

module OllamaAgent
  module Security
    # Walks the nested owners YAML rule tree into a flat list of rows for validation and indexing.
    class OwnershipRuleTreeFlattener
      def flatten(rules)
        flat = []
        visit_rules(rules, parent: nil, flat: flat, ancestry_prefixes: [])
        flat
      end

      private

      def visit_rules(list, parent:, flat:, ancestry_prefixes:)
        raise OwnershipCompileError, "rules must be an array" unless list.is_a?(Array)

        parent_prefix = parent && parent[:prefix]
        validate_sibling_prefix_overlap!(list, parent: parent_prefix)
        list.each { |raw| visit_one_rule(raw, parent: parent, flat: flat, ancestry_prefixes: ancestry_prefixes) }
      end

      def visit_one_rule(raw, parent:, flat:, ancestry_prefixes:)
        hash = stringify_keys(raw)
        validate_rule_shape!(hash)
        prefix = normalize_prefix!(hash.fetch("prefix"))
        ensure_no_cycle!(prefix, ancestry_prefixes)

        modes = Array(hash.fetch("mutable_in_modes")).map(&:to_s)
        append_flat_entry!(flat, hash, prefix, modes, parent)
        descend_children(hash, prefix, modes, flat, ancestry_prefixes)
      end

      def ensure_no_cycle!(prefix, ancestry_prefixes)
        return unless ancestry_prefixes.include?(prefix)

        raise OwnershipCompileError, "cycle or duplicate prefix in ancestry: #{prefix}"
      end

      def append_flat_entry!(flat, hash, prefix, modes, parent)
        parent_modes = parent ? parent.fetch(:mutable_in_modes) : OllamaAgent::Runtime::ExecutionMode::ALL
        flat << {
          prefix: prefix,
          owner: hash.fetch("owner").to_s,
          mutable_in_modes: modes.freeze,
          criticality: hash.fetch("criticality").to_s,
          forbidden: hash["forbidden"] == true,
          parent_modes: parent_modes
        }
      end

      def descend_children(hash, prefix, modes, flat, ancestry_prefixes)
        children = hash["children"]
        return if children.nil? || children == []

        raise OwnershipCompileError, "children for #{prefix} must be an array" unless children.is_a?(Array)

        visit_rules(
          children,
          parent: { mutable_in_modes: modes, prefix: prefix },
          flat: flat,
          ancestry_prefixes: ancestry_prefixes + [prefix]
        )
      end

      def validate_rule_shape!(hash)
        %w[prefix owner mutable_in_modes criticality].each do |key|
          raise OwnershipCompileError, "missing required key: #{key}" unless hash.key?(key)
        end
      end

      def normalize_prefix!(prefix)
        string = prefix.to_s.strip
        raise OwnershipCompileError, "prefix must be non-empty" if string.empty?
        raise OwnershipCompileError, "prefix must not have a trailing slash: #{string.inspect}" if string.end_with?("/")

        string
      end

      def stringify_keys(raw)
        raise OwnershipCompileError, "rule must be a mapping" unless raw.is_a?(Hash)

        raw.transform_keys(&:to_s)
      end

      def validate_sibling_prefix_overlap!(sibling_list, parent:)
        return unless sibling_list.is_a?(Array)

        prefixes = extract_sibling_prefixes(sibling_list)
        prefixes.combination(2) do |left, right|
          next unless ambiguous_prefix_pair?(left, right)

          raise OwnershipCompileError, ambiguous_prefix_message(parent, left, right)
        end
      end

      def extract_sibling_prefixes(sibling_list)
        sibling_list.filter_map do |raw|
          next unless raw.is_a?(Hash)

          normalize_prefix!(raw.transform_keys(&:to_s).fetch("prefix").to_s)
        end
      end

      def ambiguous_prefix_pair?(left, right)
        left != right && (prefix_strict_prefix?(left, right) || prefix_strict_prefix?(right, left))
      end

      def ambiguous_prefix_message(parent, left, right)
        label = parent || "root"
        "ambiguous sibling prefixes under #{label}: #{left.inspect} vs #{right.inspect}"
      end

      def prefix_strict_prefix?(short, long)
        long.start_with?("#{short}/") && long != short
      end
    end
  end
end
