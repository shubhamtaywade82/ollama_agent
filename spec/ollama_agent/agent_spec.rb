# frozen_string_literal: true

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

    it "raises when the loop never finishes with tool-only replies" do
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
      expect { agent.run("loop") }.to raise_error(OllamaAgent::Error, /Maximum agent turns/)
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
