# frozen_string_literal: true

require "open3"
require "spec_helper"

RSpec.describe OllamaAgent::Agent do
  let(:tmpdir) { Dir.mktmpdir }
  let(:root) { tmpdir }

  after do
    FileUtils.remove_entry(tmpdir)
  end

  describe "#run" do
    it "completes when the model returns no tool calls" do
      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(
        Ollama::Response.new(
          "message" => { "role" => "assistant", "content" => "All done." }
        )
      )

      agent = described_class.new(client: client, root: root, confirm_patches: false)
      expect { agent.run("hello") }.not_to raise_error
    end

    it "executes read_file and continues the loop" do
      File.write(File.join(root, "sample.txt"), "hello")

      tool_response = Ollama::Response.new(
        "message" => {
          "role" => "assistant",
          "content" => "",
          "tool_calls" => [
            {
              "id" => "1",
              "function" => {
                "name" => "read_file",
                "arguments" => { "path" => "sample.txt" }.to_json
              }
            }
          ]
        }
      )

      final_response = Ollama::Response.new(
        "message" => { "role" => "assistant", "content" => "Read ok." }
      )

      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(tool_response, final_response)

      agent = described_class.new(client: client, root: root, confirm_patches: false)
      expect { agent.run("read") }.not_to raise_error
    end

    it "stops after max tool rounds when the model never returns without tools" do
      stub_const("OllamaAgent::Agent::MAX_TURNS", 3)

      tool_response = Ollama::Response.new(
        "message" => {
          "role" => "assistant",
          "content" => "",
          "tool_calls" => [
            {
              "id" => "1",
              "function" => {
                "name" => "read_file",
                "arguments" => { "path" => "nope" }.to_json
              }
            }
          ]
        }
      )

      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(tool_response)

      agent = described_class.new(client: client, root: root, confirm_patches: false)
      expect { agent.run("loop") }.not_to raise_error
    end

    it "executes tools from JSON lines in content when OLLAMA_AGENT_PARSE_TOOL_JSON=1" do
      File.write(File.join(root, "sample.txt"), "hello")

      ENV["OLLAMA_AGENT_PARSE_TOOL_JSON"] = "1"

      first = Ollama::Response.new(
        "message" => {
          "role" => "assistant",
          "content" => '{"name":"read_file","parameters":{"path":"sample.txt"}}'
        }
      )
      second = Ollama::Response.new(
        "message" => { "role" => "assistant", "content" => "Done." }
      )

      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(first, second)

      agent = described_class.new(client: client, root: root, confirm_patches: false)
      expect { agent.run("read") }.not_to raise_error
    ensure
      ENV.delete("OLLAMA_AGENT_PARSE_TOOL_JSON")
    end
  end

  describe "default HTTP client" do
    it "defaults to 120s when OLLAMA_AGENT_TIMEOUT is unset" do
      ENV.delete("OLLAMA_AGENT_TIMEOUT")
      agent = described_class.new(root: root)
      config = agent.client.instance_variable_get(:@config)
      expect(config.timeout).to eq(120)
    end

    it "sets Ollama read timeout from OLLAMA_AGENT_TIMEOUT" do
      ENV["OLLAMA_AGENT_TIMEOUT"] = "90"
      agent = described_class.new(root: root)
      config = agent.client.instance_variable_get(:@config)
      expect(config.timeout).to eq(90)
    ensure
      ENV.delete("OLLAMA_AGENT_TIMEOUT")
    end

    it "prefers http_timeout keyword over OLLAMA_AGENT_TIMEOUT" do
      ENV["OLLAMA_AGENT_TIMEOUT"] = "90"
      agent = described_class.new(root: root, http_timeout: 45)
      config = agent.client.instance_variable_get(:@config)
      expect(config.timeout).to eq(45)
    ensure
      ENV.delete("OLLAMA_AGENT_TIMEOUT")
    end

    it "applies OLLAMA_BASE_URL and OLLAMA_API_KEY for Ollama Cloud (ollama-client convention)" do
      ENV["OLLAMA_BASE_URL"] = "https://ollama.com"
      ENV["OLLAMA_API_KEY"] = "test-key"
      agent = described_class.new(root: root)
      config = agent.client.instance_variable_get(:@config)
      expect(config.base_url).to eq("https://ollama.com")
      expect(config.api_key).to eq("test-key")
    ensure
      ENV.delete("OLLAMA_BASE_URL")
      ENV.delete("OLLAMA_API_KEY")
    end
  end

  describe "system_prompt" do
    it "does not use commas after --- / +++ path placeholders" do
      prompt = OllamaAgent::AgentPrompt.text
      expect(prompt).not_to include("+++ b/<path>,")
      expect(prompt).not_to include("--- a/<path>,")
    end

    it "does not embed a copy-pasteable README example diff" do
      prompt = OllamaAgent::AgentPrompt.text
      expect(prompt).not_to include("--- a/README.md")
      expect(prompt).not_to include("old line from read_file")
      expect(prompt).not_to include("context line")
    end

    it "uses self-review instructions when read_only is true" do
      prompt = OllamaAgent::AgentPrompt.self_review_text
      expect(prompt).to include("analysis-only")
      expect(prompt).not_to include("edit_file last")
    end
  end

  describe "read_only and tools" do
    it "omits edit_file from tools when read_only is true" do
      agent = described_class.new(client: instance_double(Ollama::Client), root: root, read_only: true,
                                  confirm_patches: false)
      args = agent.send(:chat_request_args, [])
      expect(args[:tools].size).to eq(3)
      names = args[:tools].map { |t| t.dig(:function, :name) }
      expect(names).not_to include("edit_file")
    end

    it "uses patch_policy to skip confirmation for auto-approved paths" do
      skip "patch --dry-run not supported" unless patch_supports_dry_run?

      File.write(File.join(root, "README.md"), "hi\n")
      policy = ->(_path, _diff) { :auto_approve }

      agent = described_class.new(root: root, confirm_patches: true, patch_policy: policy)

      diff = <<~DIFF
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -hi
        +hello
      DIFF
      result = agent.send(:edit_file, "README.md", diff)
      expect(result).to eq("Patch applied successfully.")
    end

    def patch_supports_dry_run?
      out, = Open3.capture2e("patch", "--help")
      out.include?("dry-run")
    end
  end

  describe "path sandbox" do
    it "rejects reads outside the project root" do
      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(
        Ollama::Response.new(
          "message" => {
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [
              {
                "id" => "1",
                "function" => {
                  "name" => "read_file",
                  "arguments" => { "path" => "../../../etc/passwd" }.to_json
                }
              }
            ]
          }
        ),
        Ollama::Response.new(
          "message" => { "role" => "assistant", "content" => "Stopped." }
        )
      )

      agent = described_class.new(client: client, root: root, confirm_patches: false)
      expect { agent.run("x") }.not_to raise_error
    end
  end
end
