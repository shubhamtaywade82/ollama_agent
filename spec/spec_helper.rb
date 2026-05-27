# frozen_string_literal: true

require "fileutils"

require "ollama_agent"
require_relative "support/runtime_kernel_harness"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:example, :docker) do
    skip "DOCKER_AVAILABLE is not set to \"true\"" unless ENV["DOCKER_AVAILABLE"] == "true"
    skip "/usr/bin/docker is not executable" unless File.executable?("/usr/bin/docker")
    unless system("/usr/bin/docker", "info", out: File::NULL, err: File::NULL)
      skip "Docker daemon is not reachable via /usr/bin/docker info"
    end
  end
end
