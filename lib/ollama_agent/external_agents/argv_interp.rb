# frozen_string_literal: true

module OllamaAgent
  module ExternalAgents
    # Expands %{name} placeholders in argv templates (no shell).
    module ArgvInterp
      module_function

      def expand(tokens, subs)
        return [] unless tokens.is_a?(Array)

        tokens.map do |tok|
          tok.to_s.gsub(/%\{(\w+)\}/) do
            k = Regexp.last_match(1)
            subs[k] || subs[k.to_sym]&.to_s || ""
          end
        end
      end
    end
  end
end
