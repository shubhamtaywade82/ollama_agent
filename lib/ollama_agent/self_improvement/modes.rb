# frozen_string_literal: true

module OllamaAgent
  module SelfImprovement
    # CLI modes for self_review / improve (analysis-only, interactive fixes, automated sandbox).
    module Modes
      VALID = %w[analysis interactive automated].freeze

      module_function

      def normalize(mode)
        case mode.to_s.strip.downcase
        when "", "analysis", "1", "readonly", "read-only" then "analysis"
        when "interactive", "2", "fix", "confirm" then "interactive"
        when "automated", "3", "sandbox", "full" then "automated"
        else mode.to_s.strip.downcase
        end
      end

      def valid?(mode)
        VALID.include?(mode)
      end
    end
  end
end
