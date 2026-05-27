# frozen_string_literal: true

namespace :validator do
  desc "Build IsolatedValidator Docker image (containers/ollama_agent-verification-sandbox.Dockerfile)"
  task :build do
    root = File.expand_path("../..", __dir__)
    dockerfile = File.join(root, "containers", "ollama_agent-verification-sandbox.Dockerfile")
    image = ENV.fetch("OLLAMA_AGENT_VALIDATOR_IMAGE", "ollama_agent-verification-sandbox:latest")
    sh "docker", "build", "-f", dockerfile, "-t", image, root
  end

  desc "Run RSpec examples tagged :docker (requires Docker; sets DOCKER_AVAILABLE=true for the subprocess only)"
  task :run_specs do
    sh({ "DOCKER_AVAILABLE" => "true" }, "bundle", "exec", "rspec", "--tag", "docker", "--format", "documentation")
  end
end
