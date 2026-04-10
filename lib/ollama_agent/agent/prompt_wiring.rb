# frozen_string_literal: true

module OllamaAgent
  class Agent
    # System prompt and bundled skill resolution.
    module PromptWiring
      private

      # rubocop:disable Metrics/MethodLength
      def system_prompt
        base = @read_only ? AgentPrompt.self_review_text : AgentPrompt.text
        composed = PromptSkills.compose(
          base: base,
          skills_enabled: resolved_skills_enabled,
          skills_include: resolved_skills_include,
          skills_exclude: resolved_skills_exclude,
          skill_paths: resolved_skill_paths,
          external_skills_enabled: resolved_external_skills_enabled
        )
        return composed unless @orchestrator

        [composed, AgentPrompt.orchestrator_addon].join("\n\n---\n\n")
      end
      # rubocop:enable Metrics/MethodLength

      def resolved_skills_enabled
        return @skills_enabled unless @skills_enabled.nil?

        PromptSkills.env_truthy("OLLAMA_AGENT_SKILLS", default: true)
      end

      def resolved_skills_include
        return @skills_include unless @skills_include.nil?

        PromptSkills.parse_id_list(ENV.fetch("OLLAMA_AGENT_SKILLS_INCLUDE", nil))
      end

      def resolved_skills_exclude
        return @skills_exclude unless @skills_exclude.nil?

        PromptSkills.parse_id_list(ENV.fetch("OLLAMA_AGENT_SKILLS_EXCLUDE", nil))
      end

      def resolved_skill_paths
        @skill_paths
      end

      def resolved_external_skills_enabled
        return @external_skills_enabled unless @external_skills_enabled.nil?

        PromptSkills.env_truthy("OLLAMA_AGENT_EXTERNAL_SKILLS", default: true)
      end
    end
  end
end
