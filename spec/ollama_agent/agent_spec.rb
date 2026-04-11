# frozen_string_literal: true

require "open3"
require "spec_helper"

RSpec.describe OllamaAgent::Agent do
  let(:tmpdir) { Dir.mktmpdir }
  let(:root) { tmpdir }

  after do
    FileUtils.remove_entry(tmpdir)
  end

  describe "constructor" do
    it "accepts provider_name and permissions and applies them to configuration" do
      perms = OllamaAgent::Runtime::Permissions.new(profile: :read_only)
      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(
        Ollama::Response.new("message" => { "role" => "assistant", "content" => "ok" })
      )
      agent = described_class.new(
        client: client,
        root: root,
        confirm_patches: false,
        provider_name: "anthropic",
        permissions: perms
      )
      expect(agent.instance_variable_get(:@provider_name)).to eq("anthropic")
      expect(agent.instance_variable_get(:@permissions)).to eq(perms)
    end
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
    # agent.client is now a RetryMiddleware wrapping an Ollama::Client
    def ollama_config(agent)
      agent.client.instance_variable_get(:@client).instance_variable_get(:@config)
    end

    it "defaults to 120s when OLLAMA_AGENT_TIMEOUT is unset" do
      ENV.delete("OLLAMA_AGENT_TIMEOUT")
      agent = described_class.new(root: root)
      expect(ollama_config(agent).timeout).to eq(120)
    end

    it "sets Ollama read timeout from OLLAMA_AGENT_TIMEOUT" do
      ENV["OLLAMA_AGENT_TIMEOUT"] = "90"
      agent = described_class.new(root: root)
      expect(ollama_config(agent).timeout).to eq(90)
    ensure
      ENV.delete("OLLAMA_AGENT_TIMEOUT")
    end

    it "prefers http_timeout keyword over OLLAMA_AGENT_TIMEOUT" do
      ENV["OLLAMA_AGENT_TIMEOUT"] = "90"
      agent = described_class.new(root: root, http_timeout: 45)
      expect(ollama_config(agent).timeout).to eq(45)
    ensure
      ENV.delete("OLLAMA_AGENT_TIMEOUT")
    end

    it "applies OLLAMA_BASE_URL and OLLAMA_API_KEY for Ollama Cloud (ollama-client convention)" do
      ENV["OLLAMA_BASE_URL"] = "https://ollama.com"
      ENV["OLLAMA_API_KEY"] = "test-key"
      agent = described_class.new(root: root)
      expect(ollama_config(agent).base_url).to eq("https://ollama.com")
      expect(ollama_config(agent).api_key).to eq("test-key")
    ensure
      ENV.delete("OLLAMA_BASE_URL")
      ENV.delete("OLLAMA_API_KEY")
    end

    it "applies OLLAMA_AGENT_MODEL into Ollama::Config for Ollama Cloud (same id as chat requests)" do
      ENV["OLLAMA_BASE_URL"] = "https://ollama.com"
      ENV["OLLAMA_API_KEY"] = "test-key"
      ENV["OLLAMA_AGENT_MODEL"] = "gpt-oss:120b"
      agent = described_class.new(root: root)
      expect(ollama_config(agent).model).to eq("gpt-oss:120b")
    ensure
      ENV.delete("OLLAMA_BASE_URL")
      ENV.delete("OLLAMA_API_KEY")
      ENV.delete("OLLAMA_AGENT_MODEL")
    end

    it "warns on stderr when OLLAMA_AGENT_TIMEOUT is invalid and OLLAMA_AGENT_DEBUG is on" do
      ENV["OLLAMA_AGENT_TIMEOUT"] = "not-a-number"
      ENV["OLLAMA_AGENT_DEBUG"] = "1"
      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat)
      agent = described_class.new(client: client, root: root, confirm_patches: false)
      expect do
        agent.send(:resolved_http_timeout_seconds)
      end.to output(/OLLAMA_AGENT_TIMEOUT/).to_stderr
      expect(agent.send(:resolved_http_timeout_seconds)).to eq(120)
    ensure
      ENV.delete("OLLAMA_AGENT_TIMEOUT")
      ENV.delete("OLLAMA_AGENT_DEBUG")
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

    it "uses base prompt only when skills_enabled is false" do
      agent = described_class.new(client: instance_double(Ollama::Client), root: root, confirm_patches: false,
                                  skills_enabled: false)
      expect(agent.send(:system_prompt)).to eq(OllamaAgent::AgentPrompt.text.strip)
    end

    it "includes a bundled skill section when skills are enabled and narrowed by id" do
      agent = described_class.new(client: instance_double(Ollama::Client), root: root, confirm_patches: false,
                                  skills_enabled: true, skills_include: "rubocop")
      prompt = agent.send(:system_prompt)
      expect(prompt).to include("## rubocop")
      expect(prompt).to include("RuboCop")
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

  describe "OLLAMA_AGENT_STRICT_ENV" do
    it "raises ConfigurationError when OLLAMA_AGENT_MAX_TURNS is invalid" do
      ENV["OLLAMA_AGENT_STRICT_ENV"] = "1"
      ENV["OLLAMA_AGENT_MAX_TURNS"] = "not-int"
      client = instance_double(Ollama::Client)
      expect do
        described_class.new(client: client, root: root)
      end.to raise_error(OllamaAgent::ConfigurationError, /OLLAMA_AGENT_MAX_TURNS/)
    ensure
      ENV.delete("OLLAMA_AGENT_STRICT_ENV")
      ENV.delete("OLLAMA_AGENT_MAX_TURNS")
    end
  end

  describe "streaming hooks" do
    it "exposes a Hooks instance" do
      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(
        Ollama::Response.new("message" => { "role" => "assistant", "content" => "done" })
      )
      agent = described_class.new(client: client, root: root)
      expect(agent.hooks).to be_a(OllamaAgent::Streaming::Hooks)
    end

    it "emits on_tool_call and on_tool_result when a tool executes" do
      File.write(File.join(root, "f.txt"), "content")

      tool_response = Ollama::Response.new(
        "message" => {
          "role" => "assistant", "content" => "",
          "tool_calls" => [
            { "id" => "1", "function" => { "name" => "read_file",
                                           "arguments" => { "path" => "f.txt" }.to_json } }
          ]
        }
      )
      final = Ollama::Response.new("message" => { "role" => "assistant", "content" => "ok" })

      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(tool_response, final)

      tool_calls   = []
      tool_results = []
      agent = described_class.new(client: client, root: root, confirm_patches: false)
      agent.hooks.on(:on_tool_call)   { |p| tool_calls   << p[:name] }
      agent.hooks.on(:on_tool_result) { |p| tool_results << p[:name] }

      agent.run("read f")
      expect(tool_calls).to   eq(["read_file"])
      expect(tool_results).to eq(["read_file"])
    end

    it "calls chat without hooks when on_token is not subscribed" do
      response = Ollama::Response.new("message" => { "role" => "assistant", "content" => "ok" })
      client = instance_spy(Ollama::Client, chat: response)
      agent = described_class.new(client: client, root: root, confirm_patches: false)
      agent.run("question")
      expect(client).to have_received(:chat).with(hash_not_including(:hooks)).once
    end

    it "uses streaming path when on_token subscriber is registered" do
      tokens_received = []
      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat) do |**kwargs|
        kwargs[:hooks][:on_token].call("hello ")
        kwargs[:hooks][:on_token].call("world")
        Ollama::Response.new("message" => { "role" => "assistant", "content" => "hello world" })
      end
      agent = described_class.new(client: client, root: root)
      agent.hooks.on(:on_token) { |p| tokens_received << p[:token] }
      agent.run("hi")
      expect(tokens_received).to eq(["hello ", "world"])
    end

    it "emits on_complete when the loop finishes" do
      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(
        Ollama::Response.new("message" => { "role" => "assistant", "content" => "done" })
      )
      agent = described_class.new(client: client, root: root)
      completed = false
      agent.hooks.on(:on_complete) { |_| completed = true }
      agent.run("hello")
      expect(completed).to be true
    end
  end
end
