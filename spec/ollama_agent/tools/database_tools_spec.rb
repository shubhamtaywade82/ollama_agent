# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Tools::DbQuery do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("db_query")
    end

    it "is read_only safe" do
      expect(tool.read_only_safe).to be(true)
    end
  end

  describe "#call" do
    it "rejects non-SELECT queries" do
      result = tool.call({ "sql" => "DROP TABLE users" }, context: {})
      expect(result).to match(/Error/)
      expect(result).to match(/SELECT|WITH/)
    end

    it "rejects empty SQL" do
      result = tool.call({ "sql" => "" }, context: {})
      expect(result).to match(/Error/)
    end

    it "returns error when ActiveRecord is not available" do
      result = tool.call({ "sql" => "SELECT 1" }, context: {})
      expect(result).to match(/Error/)
    end
  end
end

RSpec.describe OllamaAgent::Tools::DbSchema do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("db_schema")
    end
  end

  describe "#call" do
    it "returns error when ActiveRecord is not available" do
      result = tool.call({}, context: {})
      expect(result).to match(/Error/)
    end
  end
end

RSpec.describe OllamaAgent::Tools::RunMigration do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has the correct tool name" do
      expect(tool.name).to eq("run_migration")
    end

    it "is high risk and requires approval" do
      expect(tool.risk_level).to eq(:high)
      expect(tool.requires_approval).to be(true)
    end

    it "is not read_only safe" do
      expect(tool.read_only_safe).to be(false)
    end
  end

  describe "#call" do
    it "is blocked in read-only mode" do
      result = tool.call({ "direction" => "status" }, context: { root: Dir.pwd, read_only: true })
      expect(result).to match(/read-only/)
    end
  end
end
