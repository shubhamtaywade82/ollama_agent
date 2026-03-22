# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Console do
  describe ".color_enabled?" do
    it "is false when NO_COLOR is set" do
      ENV["NO_COLOR"] = "1"
      expect(described_class.color_enabled?).to be false
    ensure
      ENV.delete("NO_COLOR")
    end

    it "is false when OLLAMA_AGENT_COLOR is 0" do
      ENV["OLLAMA_AGENT_COLOR"] = "0"
      expect(described_class.color_enabled?).to be false
    ensure
      ENV.delete("OLLAMA_AGENT_COLOR")
    end
  end

  describe ".style" do
    it "returns plain text when color is disabled" do
      ENV["OLLAMA_AGENT_COLOR"] = "0"
      expect(described_class.style("hi", 32)).to eq("hi")
    ensure
      ENV.delete("OLLAMA_AGENT_COLOR")
    end
  end

  describe ".format_assistant" do
    it "falls back to plain styling when Markdown is disabled" do
      ENV["OLLAMA_AGENT_MARKDOWN"] = "0"
      expect(described_class.format_assistant("**hi**")).to eq(described_class.assistant_output("**hi**"))
    ensure
      ENV.delete("OLLAMA_AGENT_MARKDOWN")
    end
  end

  describe ".format_thinking" do
    it "keeps thinking as dim plain text by default (framed)" do
      ENV["OLLAMA_AGENT_MARKDOWN"] = "0"
      out = described_class.format_thinking("**note**")
      dash = "-" * OllamaAgent::Console::THINKING_FRAME_WIDTH
      expect(out).to include("**note**")
      expect(out).to include(dash)
      expect(out).to start_with(described_class.magenta(described_class.bold("Thinking")))
    ensure
      ENV.delete("OLLAMA_AGENT_MARKDOWN")
    end

    it "renders Markdown in the thinking body when OLLAMA_AGENT_THINKING_MARKDOWN=1" do
      ENV.delete("NO_COLOR")
      ENV.delete("OLLAMA_AGENT_MARKDOWN")
      ENV["OLLAMA_AGENT_THINKING_MARKDOWN"] = "1"
      allow($stdout).to receive(:tty?).and_return(true)

      out = described_class.format_thinking("Line\n\n**bold**")
      expect(out).to include(described_class.bold("Thinking"))
      expect(out).not_to include("**bold**")
    ensure
      ENV.delete("OLLAMA_AGENT_THINKING_MARKDOWN")
    end
  end

  describe ".puts_assistant_message" do
    let(:msg_class) { Struct.new(:thinking, :content) }

    context "when colors and markdown are off" do
      let(:framed_assistant_output) do
        d = "-" * OllamaAgent::Console::THINKING_FRAME_WIDTH
        <<~OUT
          Thinking
          #{d}
          plan
          #{d}

          Assistant
          Answer
        OUT
      end

      before do
        ENV["OLLAMA_AGENT_MARKDOWN"] = "0"
        ENV["OLLAMA_AGENT_COLOR"] = "0"
        ENV.delete("NO_COLOR")
      end

      after do
        ENV.delete("OLLAMA_AGENT_MARKDOWN")
        ENV.delete("OLLAMA_AGENT_COLOR")
      end

      it "frames thinking, then Assistant heading, then the reply" do
        msg = msg_class.new("plan", "Answer")
        expect { described_class.puts_assistant_message(msg) }.to output(framed_assistant_output).to_stdout
      end

      it "prints only the assistant line when there is no thinking" do
        expect { described_class.puts_assistant_message(msg_class.new(nil, "Only")) }.to output("Only\n").to_stdout
      end
    end
  end
end
