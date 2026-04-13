# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Core::SchemaValidator do
  subject(:validator) { described_class.new }

  let(:schema) do
    {
      type: "object",
      properties: {
        name: { type: "string", minLength: 1 },
        age: { type: "integer", minimum: 0, maximum: 150 },
        role: { type: "string", enum: %w[admin user guest] }
      },
      required: %w[name]
    }
  end

  describe "#validate" do
    context "with valid data" do
      it "returns no errors" do
        errors = validator.validate(schema, { "name" => "Alice", "age" => 30, "role" => "admin" })
        expect(errors).to be_empty
      end

      it "accepts partial data when optional fields are absent" do
        errors = validator.validate(schema, { "name" => "Bob" })
        expect(errors).to be_empty
      end
    end

    context "with missing required fields" do
      it "reports the missing field" do
        errors = validator.validate(schema, {})
        expect(errors).to include(match(/missing required field.*name/i))
      end
    end

    context "with wrong type" do
      it "reports type mismatch" do
        errors = validator.validate(schema, { "name" => 42 })
        expect(errors.join).to include("name")
      end
    end

    context "with enum violation" do
      it "reports the constraint violation" do
        errors = validator.validate(schema, { "name" => "X", "role" => "superadmin" })
        expect(errors.join).to include("must be one of")
      end
    end

    context "with range violation" do
      it "reports minimum breach" do
        errors = validator.validate(schema, { "name" => "X", "age" => -1 })
        expect(errors.join).to include("minimum")
      end

      it "reports maximum breach" do
        errors = validator.validate(schema, { "name" => "X", "age" => 200 })
        expect(errors.join).to include("maximum")
      end
    end

    context "with string length violation" do
      it "reports minLength breach" do
        errors = validator.validate(schema, { "name" => "" })
        expect(errors.join).to include("minLength")
      end
    end
  end

  describe "#validate!" do
    it "returns true when valid" do
      expect(validator.validate!(schema, { "name" => "Alice" })).to be(true)
    end

    it "raises ValidationError when invalid" do
      expect do
        validator.validate!(schema, {})
      end.to raise_error(OllamaAgent::Core::SchemaValidator::ValidationError)
    end
  end
end
