# frozen_string_literal: true

module OllamaAgent
  # ANSI styling for TTY output. Respects https://no-color.org/ via NO_COLOR.
  # Assistant replies use tty-markdown when enabled (headings, lists, bold, code blocks).
  module Console
    module_function

    # Muted tty-markdown palette so "Thinking" stays visually distinct from the main reply
    # (default TTY::Markdown theme uses cyan/yellow like normal assistant output).
    THINKING_MARKDOWN_THEME = {
      em: :bright_black,
      header: %i[bright_black bold],
      hr: :bright_black,
      link: %i[bright_black underline],
      list: :bright_black,
      strong: %i[bright_black bold],
      table: :bright_black,
      quote: :bright_black,
      image: :bright_black,
      note: :bright_black,
      comment: :bright_black
    }.freeze

    THINKING_FRAME_WIDTH = 44

    def color_enabled?
      $stdout.tty? && ENV["NO_COLOR"].to_s.empty? && ENV["OLLAMA_AGENT_COLOR"] != "0"
    end

    def markdown_enabled?
      $stdout.tty? && ENV["NO_COLOR"].to_s.empty? && ENV["OLLAMA_AGENT_MARKDOWN"] != "0"
    end

    # Thinking uses dim plain text by default so it stays visually separate from the main reply.
    # Set OLLAMA_AGENT_THINKING_MARKDOWN=1 to render thinking through tty-markdown (muted theme).
    def thinking_markdown_enabled?
      markdown_enabled? && ENV["OLLAMA_AGENT_THINKING_MARKDOWN"] == "1"
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
    def magenta(text) = style(text, 35)

    def welcome_banner(text)
      bold(cyan(text))
    end

    def prompt_prefix
      cyan("> ")
    end

    def assistant_output(text)
      green(text)
    end

    # Renders Markdown to the terminal (bold, lists, fenced code) when enabled; otherwise plain green text.
    def format_assistant(text)
      return assistant_output(text) unless markdown_enabled?

      markdown_parse(text) || assistant_output(text)
    end

    def format_thinking(text)
      line = thinking_frame_line
      header = "#{magenta(bold("Thinking"))}\n#{line}\n"
      body = if thinking_markdown_enabled?
               markdown_parse(text, thinking: true) || dim(text.to_s)
             else
               dim(text.to_s)
             end
      "#{header}#{body}\n#{line}"
    end

    def assistant_reply_heading
      bold(green("Assistant"))
    end

    def thinking_frame_line
      dim("-" * THINKING_FRAME_WIDTH)
    end

    class << self
      private

      def markdown_parse(text, thinking: false)
        require "tty-markdown"
        theme = thinking ? THINKING_MARKDOWN_THEME : {}
        TTY::Markdown.parse(text.to_s, theme: theme)
      rescue LoadError, StandardError
        nil
      end

      def write_assistant_reply(content, thinking_present)
        puts if thinking_present
        puts assistant_reply_heading if thinking_present
        puts format_assistant(content)
      end
    end

    # Prints thinking (if any) then main content; duck-types #thinking and #content.
    def puts_assistant_message(message)
      t = message.thinking
      c = message.content
      thinking_present = t && !t.to_s.empty?

      puts format_thinking(t) if thinking_present
      write_assistant_reply(c, thinking_present) if c && !c.to_s.empty?
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

    def tool_call_line(name, args)
      keys = args.is_a?(Hash) ? args.keys.first(2).join(", ") : ""
      cyan("[tool→] #{name}(#{keys})")
    end

    def tool_result_line(name, result)
      preview = result.to_s[0, 60].gsub(/\s+/, " ")
      dim("[tool←] #{name}: #{preview}")
    end
  end
end
