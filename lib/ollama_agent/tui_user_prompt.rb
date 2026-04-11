# frozen_string_literal: true

require "pastel"
require "tty-prompt"

module OllamaAgent
  # {UserPrompt} compatible confirmations using TTY::Prompt (arrow-friendly yes/no).
  # rubocop:disable Naming/PredicateMethod -- confirm_* mirror {UserPrompt} API
  class TuiUserPrompt
    def initialize(prompt:, stdout: $stdout)
      @prompt = prompt
      @stdout = stdout
    end

    def confirm_patch(path, diff)
      show_block("Proposed diff for #{path}:", diff)
      @prompt.yes?(apply_question("Apply this patch?"))
    end

    def confirm_write_file(path, content_preview)
      show_block("Proposed write_file for #{path}:", content_preview)
      @prompt.yes?(apply_question("Write this file?"))
    end

    def confirm_delegate(agent_id, task)
      body = task.to_s
      body = "#{body[0, 2000]}\n..." if body.length > 2000
      show_block("Delegate to #{agent_id}:", body)
      @prompt.yes?(apply_question("Run external agent?"))
    end

    private

    def apply_question(text)
      Pastel.new.yellow("#{text} (y/n)")
    end

    def show_block(title, body)
      @stdout.puts ""
      @stdout.puts Pastel.new.bold.yellow(title)
      @stdout.puts body
    end
  end
  # rubocop:enable Naming/PredicateMethod
end
