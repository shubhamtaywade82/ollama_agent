# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::BlobStore do
  def store_in(dir)
    kernel = File.join(dir, ".ollama_agent", "kernel")
    described_class.new(kernel_dir: kernel)
  end

  it "put/get round trip and exist?" do
    Dir.mktmpdir("blob-rt") do |root|
      s = store_in(root)
      hex = s.put("payload")
      expect(hex).to match(/\A[0-9a-f]{64}\z/)
      expect(s.exist?(sha256: hex)).to be(true)
      expect(s.get(sha256: hex)).to eq("payload")
    end
  end

  it "raises BlobNotFound when the object is absent" do
    Dir.mktmpdir("blob-miss") do |root|
      s = store_in(root)
      missing = "0" * 64
      expect { s.get(sha256: missing) }.to raise_error(OllamaAgent::BlobNotFound)
    end
  end

  it "raises BlobIntegrityFault when bytes on disk do not match the address" do
    Dir.mktmpdir("blob-bad") do |root|
      s = store_in(root)
      hex = s.put("ok")
      path = File.join(root, ".ollama_agent", "kernel", "blobs", hex[0..1], hex[2..])
      File.binwrite(path, "corrupt")
      expect { s.get(sha256: hex) }.to raise_error(OllamaAgent::BlobIntegrityFault)
    end
  end
end
