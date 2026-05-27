# frozen_string_literal: true

require_relative "../errors"
require_relative "criticality_policy"

module OllamaAgent
  module Runtime
    # Bridges legacy {Permissions}/{Policies} with {Security::OwnershipIndex} + {CriticalityPolicy}.
    class PermissionBridge
      def initialize(permissions:, policies:, ownership_index:, workspace_root:)
        @permissions = permissions
        @policies = policies
        @ownership_index = ownership_index
        @workspace_root = File.expand_path(workspace_root.to_s)
      end

      # Strict agreement between legacy and kernel layers (+PermissionConflictError+ on mismatch).
      def allow_mutation?(tool_name:, path:, mode:, read_only: false, rename_to: nil)
        leg = legacy_mutation_allowed?(tool_name: tool_name, path: path, read_only: read_only, rename_to: rename_to,
                                       ctx_root: @workspace_root)
        ker = kernel_mutation_allowed?(path: path, mode: mode, rename_to: rename_to)
        raise OllamaAgent::PermissionConflictError.new(legacy_allowed: leg, kernel_allowed: ker) if leg != ker

        leg && ker
      end

      # Kernel wins on disagreement (see {KernelBridge}); logs policy divergence.
      # rubocop:disable Metrics/ParameterLists -- mirrors KernelBridge call sites
      def pipeline_allowed?(tool_name:, path:, mode:, read_only: false, rename_to: nil, logger: nil, root: nil)
        ctx_root = root || @workspace_root
        leg = legacy_mutation_allowed?(tool_name: tool_name, path: path, read_only: read_only, rename_to: rename_to,
                                       ctx_root: ctx_root)
        ker = kernel_mutation_allowed?(path: path, mode: mode, rename_to: rename_to)
        if leg != ker
          log_divergence(logger, leg, ker, path)
          return ker
        end

        leg && ker
      end
      # rubocop:enable Metrics/ParameterLists

      private

      def log_divergence(logger, legacy_allowed, kernel_allowed, path)
        return unless logger

        if legacy_allowed && !kernel_allowed
          logger.error("permission bridge: legacy allowed but kernel denied; using kernel (path=#{path})")
        elsif !legacy_allowed && kernel_allowed
          logger.warn("permission bridge: legacy denied but kernel allowed; using kernel (path=#{path})")
        end
      end

      def legacy_mutation_allowed?(tool_name:, path:, read_only:, rename_to:, ctx_root: nil)
        root = ctx_root || @workspace_root
        return false unless @permissions.allowed?(tool_name.to_s)

        ctx = { read_only: read_only, root: root, shell_call_count: 0, shell_call_limit: 10 }
        if rename_to
          return false unless policy_clear?(tool_name, { "path" => path, "from_path" => path, "to_path" => rename_to },
                                            ctx)

          return policy_clear?(tool_name, { "path" => rename_to }, ctx)
        end

        policy_clear?(tool_name, { "path" => path }, ctx)
      end

      def policy_clear?(tool_name, args, ctx)
        @policies.evaluate(tool_name.to_s, args, ctx).nil?
      end

      def kernel_mutation_allowed?(path:, mode:, rename_to: nil)
        rels = rename_to ? [path.to_s, rename_to.to_s] : [path.to_s]
        rels.all? { |rel| kernel_allows_single_path?(rel, mode) }
      end

      def kernel_allows_single_path?(relative_path, mode)
        abs = File.expand_path(relative_path.to_s, @workspace_root)
        node = @ownership_index.lookup(absolute_path: abs, workspace_root: @workspace_root)
        return false unless node
        return false if node.forbidden

        CriticalityPolicy.gate(node, mode: mode.to_s) == :allow
      end
    end
  end
end
