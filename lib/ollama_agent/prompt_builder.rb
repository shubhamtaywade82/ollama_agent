# frozen_string_literal: true

module OllamaAgent
  class PromptBuilder
    attr_reader :config

    def initialize(config:)
      @config = config
    end

    def system_prompt
      base = @config.runtime.system_prompt || (@config.runtime.read_only ? AgentPrompt.self_review_text : AgentPrompt.text)
      composed = PromptSkills.compose(
        base: base,
        skills_enabled: resolved_skills_enabled,
        skills_include: resolved_skills_include,
        skills_exclude: resolved_skills_exclude,
        skill_paths: resolved_skill_paths,
        external_skills_enabled: resolved_external_skills_enabled
      )
      return composed unless @config.runtime.orchestrator

      [composed, AgentPrompt.orchestrator_addon].join("\n\n---\n\n")
    end

    private

    def resolved_skills_enabled
      return @config.skills.skills_enabled unless @config.skills.skills_enabled.nil?

      PromptSkills.env_truthy("OLLAMA_AGENT_SKILLS", default: true)
    end

    def resolved_skills_include
      return @config.skills.skills_include unless @config.skills.skills_include.nil?

      PromptSkills.parse_id_list(ENV.fetch("OLLAMA_AGENT_SKILLS_INCLUDE", nil))
    end

    def resolved_skills_exclude
      return @config.skills.skills_exclude unless @config.skills.skills_exclude.nil?

      PromptSkills.parse_id_list(ENV.fetch("OLLAMA_AGENT_SKILLS_EXCLUDE", nil))
    end

    def resolved_skill_paths
      @config.skills.skill_paths
    end

    def resolved_external_skills_enabled
      return @config.skills.external_skills_enabled unless @config.skills.external_skills_enabled.nil?

      PromptSkills.env_truthy("OLLAMA_AGENT_EXTERNAL_SKILLS", default: true)
    end
  end
end