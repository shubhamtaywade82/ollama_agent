# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# rubocop:disable RSpec/DescribeClass -- integration smoke for legacy routing
RSpec.describe "legacy tool path without kernel", :integration do
  around do |example|
    previous = ENV.fetch("OLLAMA_AGENT_KERNEL", nil)
    ENV.delete("OLLAMA_AGENT_KERNEL")
    example.run
    ENV["OLLAMA_AGENT_KERNEL"] = previous if previous
  end

  # rubocop:disable Metrics/MethodLength -- building Ollama tool-call payload
  def tool_response(name, args)
    Ollama::Response.new(
      "message" => {
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [
          {
            "id" => "call-1",
            "function" => {
              "name" => name,
              "arguments" => args.to_json
            }
          }
        ]
      }
    )
  end
  # rubocop:enable Metrics/MethodLength

  def final_response(text)
    Ollama::Response.new("message" => { "role" => "assistant", "content" => text })
  end

  it "runs write_file on the legacy path without creating kernel storage" do
    Dir.mktmpdir("legacy-write") do |root|
      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(
        tool_response("write_file", { "path" => "hello.txt", "content" => "world" }),
        final_response("done.")
      )

      agent = OllamaAgent::Agent.new(client: client, root: root, confirm_patches: false)
      agent.run("please write hello.txt")

      expect(File.read(File.join(root, "hello.txt"))).to eq("world")
      kernel = File.join(root, ".ollama_agent", "kernel")
      expect(File.directory?(kernel)).to be(false)
    end
  end

  it "runs read_file on the legacy path without kernel storage" do
    Dir.mktmpdir("legacy-read") do |root|
      File.write(File.join(root, "sample.txt"), "body")

      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(
        tool_response("read_file", { "path" => "sample.txt" }),
        final_response("read ok")
      )

      agent = OllamaAgent::Agent.new(client: client, root: root, confirm_patches: false)
      agent.run("read sample")

      expect(File.directory?(File.join(root, ".ollama_agent", "kernel"))).to be(false)
    end
  end

  it "runs edit_file on the legacy path without kernel storage" do
    Dir.mktmpdir("legacy-edit") do |root|
      File.write(File.join(root, "README.md"), "hi\n")

      diff = <<~DIFF
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -hi
        +hello
      DIFF

      client = instance_double(Ollama::Client)
      allow(client).to receive(:chat).and_return(
        tool_response("edit_file", { "path" => "README.md", "diff" => diff }),
        final_response("patched")
      )

      agent = OllamaAgent::Agent.new(client: client, root: root, confirm_patches: false)
      agent.run("edit readme")

      expect(File.read(File.join(root, "README.md"))).to eq("hello\n")
      expect(File.directory?(File.join(root, ".ollama_agent", "kernel"))).to be(false)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
