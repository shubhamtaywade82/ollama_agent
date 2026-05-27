# frozen_string_literal: true

# examples/agentic_tool_calling.rb
#
# Demonstrates the two local-environment agentic tools introduced in:
#   lib/ollama_agent/tools/filesystem_explorer.rb  (list_directory_contents)
#   lib/ollama_agent/tools/safe_calculator.rb      (calculate)
#
# Based on the pattern from:
#   "Easy Agentic Tool Calling with Gemma 4" — KDnuggets, May 2026
#   https://www.kdnuggets.com/easy-agentic-tool-calling-with-gemma-4
#
# Run from the project root:
#   bundle exec ruby examples/agentic_tool_calling.rb
#
# Prerequisites:
#   - Ollama running locally (http://localhost:11434)
#   - A tool-capable model pulled, e.g.:
#       ollama pull gemma4:e2b
#   - OLLAMA_AGENT_MODEL set (or the default from ollama-client is used):
#       export OLLAMA_AGENT_MODEL=gemma4:e2b

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ollama_agent"

MODEL   = ENV.fetch("OLLAMA_AGENT_MODEL", "gemma4:e2b")
DIVIDER = "-" * 72

def section(title)
  puts "\n#{DIVIDER}"
  puts "  #{title}"
  puts DIVIDER
end

def run_prompt(runner, prompt)
  puts "\n[PROMPT] #{prompt}\n\n"
  result = runner.run(prompt)
  puts result
end

# ── Build a runner pointed at this repo ──────────────────────────────────────

runner = OllamaAgent::Runner.build(
  root:      Dir.pwd,
  model:     MODEL,
  read_only: true   # these tools are safe in read-only mode; no patches needed
)

puts "OllamaAgent — agentic tool calling demo"
puts "Model  : #{MODEL}"
puts "Root   : #{Dir.pwd}"

# ── Example 1: filesystem inspection only ───────────────────────────────────

section("1 / 3  Filesystem inspection")

run_prompt(
  runner,
  "What files are in the lib/ollama_agent/tools/ folder? " \
  "Which one looks like it handles shell command execution?"
)

# ── Example 2: arithmetic only ───────────────────────────────────────────────

section("2 / 3  Arithmetic evaluation")

run_prompt(
  runner,
  "What is the standard deviation of the numbers " \
  "12, 18, 23, 24, 29, 31, 35, 41, 44, 47 " \
  "using the population formula (divide by N)? " \
  "Use the calculate tool for each arithmetic step."
)

# ── Example 3: both tools chained ────────────────────────────────────────────

section("3 / 3  Combined — inspect then compute")

run_prompt(
  runner,
  "Look at the files in the current folder (project root) and tell me " \
  "the total size of all files in kilobytes, rounded to two decimal places. " \
  "List every file you find with its size first, then sum them."
)

puts "\n#{DIVIDER}"
puts "  Done."
puts DIVIDER

# ── Using the tool classes directly (no agent loop) ──────────────────────────
#
# Both tools can be called outside the agent loop for testing or scripting.
#
#   require "ollama_agent"
#
#   fs   = OllamaAgent::Tools::FilesystemExplorer.new
#   calc = OllamaAgent::Tools::SafeCalculator.new
#
#   puts fs.call({ "path" => "lib" }, context: { root: Dir.pwd })
#   puts calc.call({ "expression" => "(412 + 1834 + 10786 + 88 + 2210) / 1024" })
#
# Security invariants verified in specs:
#   spec/ollama_agent/tools/filesystem_explorer_spec.rb
#   spec/ollama_agent/tools/safe_calculator_spec.rb
