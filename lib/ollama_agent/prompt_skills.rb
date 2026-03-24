# frozen_string_literal: true

require "yaml"

module OllamaAgent
  # Bundled Markdown skills under lib/ollama_agent/prompt_skills plus optional paths (env / Agent kwargs).
  # rubocop:disable Metrics/ModuleLength -- single cohesive loader; split only if it grows further
  module PromptSkills
    BUNDLED_DIR = File.join(__dir__, "prompt_skills")
    MANIFEST_PATH = File.join(BUNDLED_DIR, "manifest.yml")

    module_function

    def strip_frontmatter(text)
      return "" if text.nil?

      s = text.to_s
      lines = s.lines
      return s unless lines.first&.strip == "---"

      closing = (1...lines.size).find { |i| lines[i].strip == "---" }
      return s if closing.nil?

      lines[(closing + 1)..].join.lstrip
    end

    def read_skill_file(path)
      strip_frontmatter(File.read(path, encoding: Encoding::UTF_8))
    rescue Errno::ENOENT
      ""
    end

    # rubocop:disable Metrics/ParameterLists -- mirrors Agent keyword surface
    def compose(base:, skills_enabled: nil, skills_include: nil, skills_exclude: nil,
                skill_paths: nil, external_skills_enabled: nil)
      parts = [base.to_s.strip]
      if bundled_enabled?(skills_enabled)
        bundled = bundled_text(skills_include: skills_include, skills_exclude: skills_exclude)
        parts << bundled unless bundled.empty?
      end
      ext = external_text(skill_paths: skill_paths, external_skills_enabled: external_skills_enabled)
      parts << ext unless ext.empty?
      parts.reject(&:empty?).join("\n\n---\n\n")
    end
    # rubocop:enable Metrics/ParameterLists

    def bundled_enabled?(skills_enabled)
      truthy?(skills_enabled, default: true)
    end

    def external_enabled?(external_skills_enabled)
      truthy?(external_skills_enabled, default: true)
    end

    def external_text(skill_paths: nil, external_skills_enabled: nil)
      return "" unless external_enabled?(external_skills_enabled)

      merged = merge_skill_paths(skill_paths)
      bodies = merged.flat_map { |segment| bodies_for_path_segment(segment) }
      bodies.reject(&:empty?).join("\n\n---\n\n")
    end

    def bodies_for_path_segment(segment)
      path = File.expand_path(segment)
      return [read_skill_file(path)] if File.file?(path)
      return [] unless File.directory?(path)

      Dir.glob(File.join(path, "*.md")).map { |f| read_skill_file(f) }
    end
    private_class_method :bodies_for_path_segment

    def bundled_text(skills_include: nil, skills_exclude: nil)
      entries = manifest_entries
      return "" if entries.empty?

      filter_ids(entries, skills_include: skills_include, skills_exclude: skills_exclude).filter_map do |entry|
        body = read_skill_file(File.join(BUNDLED_DIR, entry.fetch("file")))
        next if body.empty?

        "## #{entry.fetch("id")}\n\n#{body}"
      end.join("\n\n---\n\n")
    end

    def merge_skill_paths(paths)
      env = split_paths(ENV.fetch("OLLAMA_AGENT_SKILL_PATHS", nil))
      extra =
        case paths
        when nil then []
        when Array then paths.compact.map(&:to_s)
        else split_paths(paths.to_s)
        end
      (env + extra).uniq
    end

    def split_paths(raw)
      return [] if raw.nil?

      s = raw.to_s.strip
      return [] if s.empty?

      s.split(File::PATH_SEPARATOR).map(&:strip).reject(&:empty?)
    end

    def truthy?(value, default:)
      return default if value.nil?

      case value
      when true then true
      when false then false
      else
        parse_string_truthy(value.to_s, default: default)
      end
    end

    def parse_string_truthy(str, default:)
      s = str.strip.downcase
      return default if s.empty?

      return false if %w[0 false no off].include?(s)
      return true if %w[1 true yes on].include?(s)

      default
    end

    def parse_id_list(raw)
      return nil if raw.nil?

      s = raw.to_s.strip
      return nil if s.empty?

      s.split(",").map(&:strip).reject(&:empty?).map(&:downcase)
    end

    def env_truthy(env_key, default: true)
      raw = ENV.fetch(env_key, nil)
      return default if raw.nil? || raw.to_s.strip.empty?

      parse_string_truthy(raw.to_s, default: default)
    end

    # rubocop:disable Metrics/AbcSize -- straightforward filter + optional reorder
    def filter_ids(entries, skills_include: nil, skills_exclude: nil)
      include_list = parse_id_list(skills_include)
      exclude_ids = parse_id_list(skills_exclude) || []

      ordered = entries.dup
      if include_list
        id_index = include_list.each_with_index.to_h
        ordered = ordered.select { |e| id_index.key?(e.fetch("id").downcase) }
        ordered.sort_by! { |e| id_index[e.fetch("id").downcase] }
      end

      ordered.reject { |e| exclude_ids.include?(e.fetch("id").downcase) }
    end
    # rubocop:enable Metrics/AbcSize

    def manifest_entries
      return [] unless File.file?(MANIFEST_PATH)

      data = YAML.safe_load(
        File.read(MANIFEST_PATH, encoding: Encoding::UTF_8),
        permitted_classes: [],
        aliases: true
      )
      Array(data&.fetch("skills", nil))
    end
  end
  # rubocop:enable Metrics/ModuleLength
end
