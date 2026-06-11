# frozen_string_literal: true

module OllamaAgent
  module Config
    SkillConfig = Data.define(:skill_paths, :skills_enabled, :skills_include,
                              :skills_exclude, :external_skills_enabled) do
      def initialize(skill_paths: nil, skills_enabled: nil, skills_include: nil,
                     skills_exclude: nil, external_skills_enabled: nil)
        super
      end
    end
  end
end