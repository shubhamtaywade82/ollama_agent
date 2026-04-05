# frozen_string_literal: true

module OllamaAgent
  module ExternalAgents
    # Ensures paths stay under a project root (expanded, absolute).
    module PathValidator
      class << self
        def validate_within_root!(root, paths)
          root = File.expand_path(root)
          Array(paths).each do |p|
            next if p.to_s.strip.empty?

            abs = File.expand_path(p, root)
            next if within_root?(abs, root)

            if ENV["OLLAMA_AGENT_DEBUG"] == "1"
              warn "ollama_agent: PathValidator rejected path outside project root (#{p.inspect})"
            end
            raise ArgumentError, "path outside project root"
          end
        end

        # Both arguments should already be expanded absolute paths (e.g. from Pathname or File.expand_path).
        def within_root?(absolute_path, expanded_root)
          expanded_root = File.expand_path(expanded_root)
          abs = absolute_path.to_s
          abs == expanded_root || abs.start_with?(expanded_root + File::SEPARATOR)
        end
      end
    end
  end
end
