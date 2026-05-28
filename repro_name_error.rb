require_relative "lib/ollama_agent"
require_relative "lib/ollama_agent/cli/tui_repl"

begin
  agent = Object.new
  tui = Object.new
  OllamaAgent::CLI::TuiRepl.new(agent: agent, tui: tui)
  puts "Initialization successful"
rescue NameError => e
  puts "Caught expected error: #{e.message}"
  puts e.backtrace.join("\n")
rescue StandardError => e
  puts "Caught other error: #{e.class}: #{e.message}"
end
