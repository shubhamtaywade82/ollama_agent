# frozen_string_literal: true

module OllamaAgent
  # ANSI styling for TTY output. Respects https://no-color.org/ via NO_COLOR.
  # Assistant replies use tty-markdown when enabled (headings, lists, bold, code blocks).
  # rubocop:disable Metrics/ModuleLength -- single-responsibility output module; methods are all short
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

    # +compact+ (default): one "Thinking" label per agent run; later reasoning uses blank lines only (Cursor-like).
    # +framed+: repeat the full banner + rulers on every assistant message (legacy).
    def thinking_framed_style?
      ENV.fetch("OLLAMA_AGENT_THINKING_STYLE", "compact").to_s.strip.downcase == "framed"
    end

    # @api private  Reset at the start of each {Agent#run} so multi-turn tool loops share one thinking header.
    def reset_thinking_session!
      Thread.current[:ollama_agent_thinking_shown] = false
      Thread.current[:ollama_agent_stream_thinking_open] = false
      Thread.current[:ollama_agent_stream_had_thinking] = false
      Thread.current[:ollama_agent_stream_thinking_buffer] = nil
    end

    def thinking_already_shown_in_session?
      Thread.current[:ollama_agent_thinking_shown] == true
    end

    def mark_thinking_shown_in_session!
      Thread.current[:ollama_agent_thinking_shown] = true
    end

    # --- Streaming (ollama-client passes thinking only via patched hooks[:on_thinking]) ---

    # Print one dim "Thinking" label, then stream fragments in dim until content tokens arrive.
    # Handles both cumulative thinking strings (common from Ollama) and plain deltas; sanitizes UTF-8.
    def write_streaming_thinking_fragment(fragment)
      text = utf8_for_stream(fragment)
      return if text.empty?

      open_streaming_thinking_section_if_needed
      to_print = streaming_thinking_increment_to_print(text)
      return if to_print.empty?

      print to_print
      $stdout.flush
    end

    def write_stream_token(fragment)
      print utf8_for_stream(fragment)
      $stdout.flush
    end

    # Call before the first streamed content token: closes dim reasoning, optional Assistant heading.
    def finalize_streaming_thinking_before_content!
      return unless Thread.current[:ollama_agent_stream_thinking_open]

      Thread.current[:ollama_agent_stream_thinking_open] = false
      had = Thread.current[:ollama_agent_stream_had_thinking]
      Thread.current[:ollama_agent_stream_had_thinking] = false
      Thread.current[:ollama_agent_stream_thinking_buffer] = nil
      print "\e[0m" if color_enabled?
      puts
      puts assistant_reply_heading if had
    end

    # When the model returns only thinking (no content), close ANSI state on stream end.
    def close_streaming_thinking_if_still_open!
      return unless Thread.current[:ollama_agent_stream_thinking_open]

      Thread.current[:ollama_agent_stream_thinking_open] = false
      Thread.current[:ollama_agent_stream_had_thinking] = false
      Thread.current[:ollama_agent_stream_thinking_buffer] = nil
      print "\e[0m" if color_enabled?
      puts
    end

    def open_streaming_thinking_section_if_needed
      return if Thread.current[:ollama_agent_stream_thinking_open]

      Thread.current[:ollama_agent_stream_thinking_open] = true
      Thread.current[:ollama_agent_stream_had_thinking] = true
      label = color_enabled? ? "#{dim("Thinking")}\n" : "Thinking\n"
      print label
      print "\e[2m" if color_enabled?
    end
    private_class_method :open_streaming_thinking_section_if_needed

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- cumulative vs delta stream shapes
    def streaming_thinking_increment_to_print(next_utf8)
      prev = Thread.current[:ollama_agent_stream_thinking_buffer].to_s
      if prev.empty?
        Thread.current[:ollama_agent_stream_thinking_buffer] = next_utf8
        return next_utf8
      end

      if next_utf8.start_with?(prev) && next_utf8.bytesize >= prev.bytesize
        slice = next_utf8.byteslice(prev.bytesize..)
        Thread.current[:ollama_agent_stream_thinking_buffer] = next_utf8
        return slice
      end

      return +"" if next_utf8 == prev

      if next_utf8.bytesize < prev.bytesize
        Thread.current[:ollama_agent_stream_thinking_buffer] = next_utf8
        return next_utf8
      end

      Thread.current[:ollama_agent_stream_thinking_buffer] = prev + next_utf8
      next_utf8
    end
    private_class_method :streaming_thinking_increment_to_print
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def utf8_for_stream(fragment)
      fragment.to_s.encode("UTF-8", invalid: :replace, undef: :replace)
    end
    private_class_method :utf8_for_stream

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

    def format_thinking_compact_open(text)
      label = color_enabled? ? dim("Thinking") : "Thinking"
      body = thinking_compact_body(text)
      "#{label}\n#{body}"
    end

    # Later thinking in the same run (tool rounds, new chat chunks): same block, separated by a blank line.
    def format_thinking_compact_merge(text)
      "\n#{thinking_compact_body(text)}"
    end

    def thinking_compact_body(text)
      if thinking_markdown_enabled?
        parsed = markdown_parse(text, thinking: true)
        return parsed if parsed

        return dim_indent_body(text)
      end

      dim_indent_body(text)
    end

    def dim_indent_body(text)
      s = text.to_s.rstrip
      return "" if s.empty?

      indent = "  "
      dim(s.lines.map { |l| "#{indent}#{l.rstrip}" }.join("\n"))
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
      thinking_present = assistant_message_thinking_present?(message.thinking)
      if thinking_present
        puts thinking_output_chunk(message.thinking)
        mark_thinking_shown_in_session! unless thinking_framed_style?
      end
      assistant_reply_if_present(message.content, thinking_present)
    end

    def assistant_message_thinking_present?(text)
      text && !text.to_s.strip.empty?
    end
    private_class_method :assistant_message_thinking_present?

    def assistant_reply_if_present(content, thinking_present)
      return unless content && !content.to_s.strip.empty?

      write_assistant_reply(content, thinking_present)
    end
    private_class_method :assistant_reply_if_present

    def thinking_output_chunk(text)
      return format_thinking(text) if thinking_framed_style?
      return format_thinking_compact_open(text) unless thinking_already_shown_in_session?

      format_thinking_compact_merge(text)
    end
    private_class_method :thinking_output_chunk

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
  # rubocop:enable Metrics/ModuleLength
end
