# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Topology::ZeitwerkInflector do
  describe ".camelize" do
    it "maps a snake path to a constant path" do
      expect(described_class.camelize(snake_path: "user_account")).to eq("UserAccount")
      expect(described_class.camelize(snake_path: "admin/user")).to eq("Admin::User")
    end

    it "applies acronym overrides" do
      acronyms = { "api" => "API", "html" => "HTML" }
      expect(described_class.camelize(snake_path: "api_client", acronyms: acronyms)).to eq("APIClient")
      expect(described_class.camelize(snake_path: "html_parser", acronyms: acronyms)).to eq("HTMLParser")
    end
  end

  describe ".file_to_constant" do
    it "strips a matching root and camelizes the relative path" do
      Dir.mktmpdir("zeitwerk-inflect") do |root|
        models = File.join(root, "app", "models")
        FileUtils.mkdir_p(models)
        path = File.join(models, "user_account.rb")
        File.write(path, "#")

        fqcn = described_class.file_to_constant(
          file_path: path,
          root_paths: [File.join(root, "app/models")]
        )
        expect(fqcn).to eq("UserAccount")
      end
    end
  end

  describe ".constant_to_file_pattern" do
    it "returns candidate paths under each root" do
      Dir.mktmpdir("zeitwerk-patterns") do |root|
        models = File.join(root, "app", "models")
        FileUtils.mkdir_p(models)
        expected = File.join(models, "admin", "user.rb")
        patterns = described_class.constant_to_file_pattern(
          fqcn: "Admin::User",
          root_paths: [File.join(root, "app/models")]
        )
        expect(patterns).to include(expected)
      end
    end
  end
end
