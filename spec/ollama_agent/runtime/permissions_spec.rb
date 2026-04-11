# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::Permissions do
  describe ":read_only profile" do
    subject(:perms) { described_class.new(profile: :read_only) }

    it "allows read_file" do
      expect(perms.allowed?("read_file")).to be(true)
    end

    it "allows search_code" do
      expect(perms.allowed?("search_code")).to be(true)
    end

    it "denies edit_file" do
      expect(perms.allowed?("edit_file")).to be(false)
    end

    it "denies run_shell" do
      expect(perms.allowed?("run_shell")).to be(false)
    end
  end

  describe ":full profile" do
    subject(:perms) { described_class.new(profile: :full) }

    it "allows run_shell" do
      expect(perms.allowed?("run_shell")).to be(true)
    end

    it "allows http_post" do
      expect(perms.allowed?("http_post")).to be(true)
    end
  end

  describe "custom denied list" do
    subject(:perms) { described_class.new(profile: :full, denied: %w[run_shell]) }

    it "denies explicitly denied tools even in full profile" do
      expect(perms.allowed?("run_shell")).to be(false)
    end

    it "still allows others" do
      expect(perms.allowed?("read_file")).to be(true)
    end
  end

  describe "#filter_schemas" do
    subject(:perms) { described_class.new(profile: :read_only) }

    let(:schemas) do
      [
        { type: "function", function: { name: "read_file" } },
        { type: "function", function: { name: "edit_file" } }
      ]
    end

    it "returns only allowed schemas" do
      filtered = perms.filter_schemas(schemas)
      names = filtered.map { |s| s.dig(:function, :name) }
      expect(names).to include("read_file")
      expect(names).not_to include("edit_file")
    end
  end
end
