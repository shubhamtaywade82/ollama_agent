# frozen_string_literal: true

module OllamaAgent
  module Config
    class SkillConfig
      attr_reader :skill_paths, :skills_enabled, :skills_include, :skills_exclude, :external_skills_enabled

      def initialize(skill_paths: nil, skills_enabled: nil, skills_include: nil, skills_exclude: nil, external_skills_enabled: nil)
        @skill_paths = skill_paths
        @skills_enabled = skills_enabled
        @skills_include = skills_include
        @skills_exclude = skills_exclude
        @external_skills_enabled = external_skills_enabled
      end
    end
  end
end