# frozen_string_literal: true

module OllamaAgent
  # Injectable stdin/stdout for patch/write/delegate confirmations (tests use StringIO).
  # rubocop:disable Naming/PredicateMethod -- confirm_* are interactive prompts returning bool
  class UserPrompt
    def initialize(stdin: $stdin, stdout: $stdout)
      @stdin = stdin
      @stdout = stdout
    end

    def confirm_patch(path, diff)
      @stdout.puts Console.patch_title("Proposed diff for #{path}:")
      @stdout.puts diff
      @stdout.print Console.apply_prompt("Apply? (y/n) ")
      @stdin.gets.to_s.chomp.casecmp("y").zero?
    end

    def confirm_write_file(path, content_preview)
      @stdout.puts Console.patch_title("Proposed write_file for #{path}:")
      @stdout.puts content_preview
      @stdout.print Console.apply_prompt("Write file? (y/n) ")
      @stdin.gets.to_s.chomp.casecmp("y").zero?
    end

    def confirm_delegate(agent_id, task)
      @stdout.puts Console.patch_title("Delegate to #{agent_id}:")
      @stdout.puts task.to_s[0, 2000]
      @stdout.puts "..." if task.to_s.length > 2000
      @stdout.print Console.apply_prompt("Run external agent? (y/n) ")
      @stdin.gets.to_s.chomp.casecmp("y").zero?
    end
  end
  # rubocop:enable Naming/PredicateMethod
end
