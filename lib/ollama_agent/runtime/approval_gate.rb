# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Governs whether a tool call or action requires explicit user approval.
    #
    # Policy precedence (highest to lowest):
    #   1. auto_approve: true  — approve everything silently
    #   2. Tool's requires_approval flag
    #   3. Registered per-tool overrides
    #   4. Risk-level threshold
    class ApprovalGate
      RISK_ORDER = { low: 0, medium: 1, high: 2, critical: 3 }.freeze

      # @param auto_approve     [Boolean] skip all approvals
      # @param risk_threshold   [Symbol]  auto-approve tools below this risk (:low, :medium, :high, :critical)
      # @param tool_overrides   [Hash]    { "tool_name" => true/false } per-tool override
      # @param stdin            [IO]
      # @param stdout           [IO]
      def initialize(auto_approve: false, risk_threshold: :medium,
                     tool_overrides: {}, stdin: $stdin, stdout: $stdout)
        @auto_approve    = auto_approve
        @risk_threshold  = risk_threshold.to_sym
        @tool_overrides  = tool_overrides.transform_keys(&:to_s)
        @stdin           = stdin
        @stdout          = stdout
      end

      # Decide whether this tool call is approved.
      # @param tool_name   [String]
      # @param args        [Hash]
      # @param risk_level  [Symbol]  from the tool definition
      # @param approval_required [Boolean] from the tool definition
      # @return [Boolean]
      def approved?(tool_name, args: {}, risk_level: :low, approval_required: false)
        return true if @auto_approve
        return @tool_overrides[tool_name.to_s] if @tool_overrides.key?(tool_name.to_s)
        return true unless needs_gate?(risk_level, approval_required)

        prompt_user(tool_name, args, risk_level)
      end

      # Record a decision (useful for tests / audit).
      attr_reader :last_decision

      private

      def needs_gate?(risk_level, approval_required)
        return true if approval_required

        RISK_ORDER[risk_level.to_sym].to_i >= RISK_ORDER[@risk_threshold].to_i
      end

      def prompt_user(tool_name, args, risk_level)
        @stdout.puts ""
        @stdout.puts "─" * 60
        @stdout.puts "  Approval required: \e[33m#{tool_name}\e[0m (risk: #{risk_level})"
        unless args.empty?
          @stdout.puts "  Args:"
          args.each { |k, v| @stdout.puts "    #{k}: #{v.inspect[0, 80]}" }
        end
        @stdout.puts "─" * 60
        @stdout.print "  Allow? [y/N] "
        @stdout.flush

        response = @stdin.gets&.chomp.to_s.downcase
        @last_decision = { tool: tool_name, approved: response == "y" }
        response == "y"
      rescue IOError
        false
      end
    end
  end
end
