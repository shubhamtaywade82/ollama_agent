# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Topology::Linker::Discovery do
  it "finds ruby files and prunes excluded directories" do
    Dir.mktmpdir("linker-discovery") do |root|
      keep = File.join(root, "lib", "kept.rb")
      FileUtils.mkdir_p(File.dirname(keep))
      File.write(keep, "#")

      skip_dir = File.join(root, "node_modules", "pkg", "skip.rb")
      FileUtils.mkdir_p(File.dirname(skip_dir))
      File.write(skip_dir, "#")

      found = described_class.find_files(roots: [root])
      expect(found).to include(File.expand_path(keep))
      expect(found).not_to include(File.expand_path(skip_dir))
    end
  end
end
