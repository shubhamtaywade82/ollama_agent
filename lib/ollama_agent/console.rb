# frozen_string_literal: true

module OllamaAgent
  # ANSI styling for TTY output. Respects https://no-color.org/ via NO_COLOR.
  module Console
    module_function

    def color_enabled?
      $stdout.tty? && ENV["NO_COLOR"].to_s.empty? && ENV["OLLAMA_AGENT_COLOR"] != "0"
    end

    def style(text, *codes)
      return text.to_s unless color_enabled?

      t = text.to_s
      return t if t.empty? || codes.flatten.compact.empty?

      "\e[#{codes.flatten.compact.join(";")}m#{t}\e[0m"
    end

    def bold(text) = style(text, 1)
    def dim(text) = style(text, 2)
    def cyan(text) = style(text, 36)
    def green(text) = style(text, 32)
    def yellow(text) = style(text, 33)
    def red(text) = style(text, 31)

    def welcome_banner(text)
      bold(cyan(text))
    end

    def prompt_prefix
      cyan("> ")
    end

    def assistant_output(text)
      green(text)
    end

    def patch_title(text)
      bold(yellow(text))
    end

    def apply_prompt(text)
      yellow(text)
    end

    def error_line(text)
      red(text)
    end
  end
end
