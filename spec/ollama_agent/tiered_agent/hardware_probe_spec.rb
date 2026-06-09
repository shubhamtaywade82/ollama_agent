# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::TieredAgent::HardwareProbe do
  describe ".detect_vram_gb" do
    context "when nvidia-smi reports a single GPU" do
      it "converts MiB to GB" do
        allow(described_class).to receive(:run_cmd)
          .with(/nvidia-smi/)
          .and_return("8192\n")
        allow(described_class).to receive(:run_cmd).with(/rocm-smi/).and_return(nil)
        allow(described_class).to receive(:run_cmd).with(/sysctl/).and_return(nil)

        result = described_class.detect_vram_gb
        expect(result).to be_within(0.01).of(8.0)
      end
    end

    context "when nvidia-smi reports multiple GPUs" do
      it "returns the maximum single-GPU VRAM" do
        allow(described_class).to receive(:run_cmd)
          .with(/nvidia-smi/)
          .and_return("8192\n16384\n")
        allow(described_class).to receive(:run_cmd).with(/rocm-smi/).and_return(nil)
        allow(described_class).to receive(:run_cmd).with(/sysctl/).and_return(nil)

        result = described_class.detect_vram_gb
        expect(result).to be_within(0.01).of(16.0)
      end
    end

    context "when nvidia-smi is unavailable but rocm-smi is present" do
      it "falls through to AMD probe" do
        allow(described_class).to receive(:run_cmd).with(/nvidia-smi/).and_return(nil)
        allow(described_class).to receive(:run_cmd)
          .with(/rocm-smi/)
          .and_return("GPU[0]: VRAM Total Memory (B): 17163091968\n")
        allow(described_class).to receive(:run_cmd).with(/sysctl/).and_return(nil)

        result = described_class.detect_vram_gb
        expect(result).to be_within(0.1).of(16.0)
      end
    end

    context "when on macOS with unified memory" do
      it "returns 75% of physical RAM" do
        allow(described_class).to receive(:run_cmd).with(/nvidia-smi/).and_return(nil)
        allow(described_class).to receive(:run_cmd).with(/rocm-smi/).and_return(nil)
        allow(described_class).to receive(:run_cmd)
          .with(/sysctl/)
          .and_return("34359738368\n") # 32 GB in bytes

        stub_const("RUBY_PLATFORM", "arm64-darwin23")
        result = described_class.detect_vram_gb
        expect(result).to be_within(0.1).of(24.0) # 32 * 0.75
      end
    end

    context "when all probes fail" do
      it "returns nil without raising" do
        allow(described_class).to receive(:run_cmd).and_return(nil)
        expect(described_class.detect_vram_gb).to be_nil
      end
    end

    context "when probes raise unexpected errors" do
      it "returns nil without propagating the exception" do
        allow(described_class).to receive(:run_cmd).and_raise(RuntimeError, "unexpected")
        expect { described_class.detect_vram_gb }.not_to raise_error
        expect(described_class.detect_vram_gb).to be_nil
      end
    end
  end

  describe ".summary" do
    it "includes GB when detected" do
      allow(described_class).to receive(:detect_vram_gb).and_return(16.0)
      expect(described_class.summary).to include("16.0 GB")
    end

    it "reports CPU-only when nil" do
      allow(described_class).to receive(:detect_vram_gb).and_return(nil)
      expect(described_class.summary).to include("CPU-only")
    end

    it "never raises" do
      allow(described_class).to receive(:detect_vram_gb).and_raise(RuntimeError)
      expect { described_class.summary }.not_to raise_error
    end
  end
end
