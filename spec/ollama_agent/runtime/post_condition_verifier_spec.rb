# frozen_string_literal: true

require "spec_helper"

RSpec.describe OllamaAgent::Runtime::PostConditionVerifier do
  let(:isolated) { instance_double(OllamaAgent::Runtime::IsolatedValidator) }
  let(:verifier) { described_class.new(isolated_validator: isolated) }

  it "passes when every check exits with the expected code" do
    allow(isolated).to receive(:run).and_return(
      { status: :ok, exit_code: 0, stdout: "", stderr: "", image_digest: "sha256:abc" },
      { status: :nonzero_exit, exit_code: 2, stdout: "", stderr: "", image_digest: "sha256:abc" }
    )

    outcome = verifier.verify(
      manifest_id: "m1",
      logical_stamp: "9",
      checks: [
        { name: "a", command: ["/bin/true"], expect_exit: 0 },
        { name: "b", command: ["/bin/false"], expect_exit: 2 }
      ]
    )

    expect(outcome[:passed]).to be(true)
    expect(outcome[:results].map { |r| r[:ok] }).to eq([true, true])
    expect(outcome[:results].map { |r| r[:name] }).to eq(%w[a b])
  end

  it "fails when a check exit code does not match expect_exit" do
    allow(isolated).to receive(:run).and_return(
      { status: :ok, exit_code: 0, stdout: "", stderr: "", image_digest: nil }
    )

    outcome = verifier.verify(
      manifest_id: "m2",
      logical_stamp: "1",
      checks: [
        { "name" => "x", "command" => ["/bin/true"], "expect_exit" => 1 }
      ]
    )

    expect(outcome[:passed]).to be(false)
    expect(outcome[:results].first[:ok]).to be(false)
  end

  it "fails when the isolated validator reports timeout or runtime_unavailable" do
    allow(isolated).to receive(:run).and_return(
      { status: :timeout, exit_code: nil, stdout: "", stderr: "", image_digest: nil }
    )

    outcome = verifier.verify(
      manifest_id: "m3",
      logical_stamp: "2",
      checks: [{ name: "t", command: ["/bin/sleep", "9"] }]
    )

    expect(outcome[:passed]).to be(false)
    expect(outcome[:results].first[:ok]).to be(false)
  end
end
