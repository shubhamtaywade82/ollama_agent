# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Tool permission system. Controls which tools are accessible in a given run.
    #
    # Built-in profiles:
    #   :read_only  — file reads + search only
    #   :standard   — read + write files, no shell or git writes
    #   :developer  — full file + git + shell tools
    #   :full       — everything
    class Permissions
      PROFILES = {
        read_only: {
          allowed: %w[read_file list_files search_code git_status git_log git_diff
                      memory_recall memory_list http_get],
          denied: []
        },
        standard: {
          allowed: %w[read_file list_files search_code edit_file write_file
                      memory_store memory_recall memory_list memory_delete
                      git_status git_log git_diff http_get],
          denied: %w[run_shell git_commit http_post]
        },
        developer: {
          allowed: %w[read_file list_files search_code edit_file write_file
                      git_status git_log git_diff git_commit git_branch
                      run_shell memory_store memory_recall memory_list memory_delete
                      http_get],
          denied: %w[http_post]
        },
        full: {
          allowed: :all,
          denied: []
        }
      }.freeze

      # @param profile      [Symbol]         one of PROFILES keys
      # @param allowed      [Array, :all]    explicit tool allowlist (overrides profile)
      # @param denied       [Array]          explicit denylist (always wins)
      def initialize(profile: :standard, allowed: nil, denied: nil)
        @profile = profile.to_sym
        @custom_allowed = allowed
        @custom_denied  = Array(denied).map(&:to_s)
      end

      # Is this tool allowed?
      # @param tool_name [String, Symbol]
      # @return [Boolean]
      def allowed?(tool_name)
        name = tool_name.to_s

        return false if effective_denied.include?(name)

        eff_allowed = effective_allowed
        return true if eff_allowed == :all

        eff_allowed.include?(name)
      end

      # Filtered list of tool schemas — only allowed tools.
      def filter_schemas(schemas)
        schemas.select { |s| allowed?(schema_name(s)) }
      end

      attr_reader :profile

      def to_h
        {
          profile: @profile,
          effective_allowed: effective_allowed,
          effective_denied: effective_denied
        }
      end

      private

      def profile_config
        PROFILES[@profile] || PROFILES[:standard]
      end

      def effective_allowed
        return @custom_allowed if @custom_allowed

        profile_config[:allowed]
      end

      def effective_denied
        (profile_config[:denied] + @custom_denied).uniq
      end

      def schema_name(schema)
        schema.dig(:function, :name) ||
          schema.dig("function", "name") ||
          schema[:name] ||
          schema["name"] ||
          ""
      end
    end
  end
end
