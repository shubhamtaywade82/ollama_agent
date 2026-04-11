# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Policy engine for the agent runtime.
    #
    # A Policy is a named rule that can:
    #   - Block a tool call (returns a rejection reason string)
    #   - Allow it (returns nil / :allow)
    #   - Modify args before execution
    #
    # Policies are evaluated in registration order.
    # First blocking policy wins.
    #
    # @example
    #   policies = OllamaAgent::Runtime::Policies.new
    #   policies.add(:no_outside_writes) do |tool, args, ctx|
    #     if tool == "write_file" && !args["path"]&.start_with?(ctx[:root])
    #       "write_file: cannot write outside project root"
    #     end
    #   end
    class Policies
      Policy = Data.define(:name, :handler)

      def initialize
        @policies = []
        install_default_policies
      end

      # Register a policy.
      # @param name    [Symbol, String]
      # @param handler [Proc]  receives (tool_name, args, context) → nil | String (rejection reason)
      def add(name, &handler)
        raise ArgumentError, "Policy handler block required" unless block_given?

        @policies << Policy.new(name: name.to_sym, handler: handler)
      end

      # Remove a named policy.
      def remove(name)
        @policies.reject! { |p| p.name == name.to_sym }
      end

      # Evaluate all policies for a tool call.
      # @return [nil, String]  nil = allowed; String = rejection reason
      def evaluate(tool_name, args, context = {})
        @policies.each do |policy|
          result = policy.handler.call(tool_name.to_s, args, context)
          return result.to_s if result && result != :allow
        end
        nil
      end

      # Check read_only at the policy level
      def blocked?(tool_name, args, context = {})
        !evaluate(tool_name, args, context).nil?
      end

      def policy_names
        @policies.map(&:name)
      end

      private

      def install_default_policies
        # Enforce read_only context flag
        add(:read_only_enforcement) do |tool, _args, ctx|
          write_tools = %w[edit_file write_file run_shell git_commit http_post memory_delete]
          if ctx[:read_only] && write_tools.include?(tool)
            "#{tool} is not allowed in read-only mode"
          end
        end

        # Prevent writing outside project root for file tools
        add(:path_sandbox_enforcement) do |tool, args, ctx|
          next unless ctx[:root] && %w[edit_file write_file read_file].include?(tool)

          path = (args["path"] || args[:path]).to_s
          next if path.empty?

          expanded = File.expand_path(path, ctx[:root])
          root_abs = File.expand_path(ctx[:root])

          unless expanded.start_with?(root_abs)
            "#{tool}: path must stay within project root (#{root_abs})"
          end
        end

        # Rate-limit shell commands (max 10 per run)
        add(:shell_rate_limit) do |tool, _args, ctx|
          next unless tool == "run_shell"

          counter = (ctx[:shell_call_count] || 0)
          limit   = (ctx[:shell_call_limit] || 10)
          "run_shell: rate limit of #{limit} calls per run exceeded" if counter >= limit
        end
      end
    end
  end
end
