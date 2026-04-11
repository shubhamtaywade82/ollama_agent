# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/ollama_agent/ollama_cloud_catalog"

RSpec.describe OllamaAgent::OllamaCloudCatalog do
  describe ".names_from_tags_json" do
    it "returns sorted unique model names" do
      json = '{"models":[{"name":"z"},{"name":"a"},{"name":"a"}]}'
      expect(described_class.names_from_tags_json(json)).to eq(%w[a z])
    end

    it "returns empty array for empty models" do
      expect(described_class.names_from_tags_json('{"models":[]}')).to eq([])
    end
  end

  describe ".catalog_uri" do
    it "uses the explicit base URL when given" do
      uri = described_class.catalog_uri("https://ollama.com/api/tags")
      expect(uri.host).to eq("ollama.com")
      expect(uri.path).to eq("/api/tags")
    end
  end
end
