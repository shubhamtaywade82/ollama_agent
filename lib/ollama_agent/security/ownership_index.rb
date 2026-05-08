# frozen_string_literal: true

require "pathname"

require_relative "resource_guard"

module OllamaAgent
  module Security
    # One resolved ownership rule (immutable).
    OwnershipNode = Data.define(:prefix, :owner, :mutable_in_modes, :criticality, :forbidden)

    # Longest-prefix match index over workspace-relative ownership rules.
    # Path checks delegate to {ResourceGuard} semantics (adapter: same allow? contract).
    class OwnershipIndex
      # @param nodes [Array<OwnershipNode>]
      # @param source_sha256 [String]
      def initialize(nodes, source_sha256:)
        @source_sha256 = source_sha256
        @sorted_nodes = nodes.sort_by { |n| -n.prefix.length }
      end

      attr_reader :source_sha256

      # Builds a frozen node for the compiler.
      def self.node(prefix:, owner:, mutable_in_modes:, criticality:, forbidden:)
        OwnershipNode.new(
          prefix: prefix,
          owner: owner,
          mutable_in_modes: mutable_in_modes.freeze,
          criticality: criticality,
          forbidden: forbidden
        )
      end

      # @return [OwnershipNode, nil] nil when path is unsafe or no rule matches
      def lookup(absolute_path:, workspace_root:)
        return nil if raw_path_has_dot_dot?(absolute_path)

        guard = ResourceGuard.new(root: workspace_root)
        return nil unless guard.allow?(absolute_path.to_s)

        root = Pathname.new(workspace_root).realpath
        abs = absolute_pathname(absolute_path, root)
        rel = abs.relative_path_from(root).to_s
        @sorted_nodes.find { |n| rel == n.prefix || rel.start_with?("#{n.prefix}/") }
      rescue ArgumentError, Errno::ENOENT, Errno::ELOOP, Errno::EACCES
        nil
      end

      private

      def raw_path_has_dot_dot?(candidate_path)
        Pathname.new(candidate_path).each_filename.to_a.include?("..")
      end

      def absolute_pathname(absolute_path, root)
        pn = Pathname.new(absolute_path)
        base = pn.absolute? ? pn : root.join(pn)
        base.expand_path.cleanpath
      end
    end
  end
end
