# Docker-tagged RSpec activation (`:docker`)

The `OllamaAgent::Runtime::IsolatedValidator` examples that exercise a real Docker CLI are tagged **`:docker`** (see `spec/ollama_agent/runtime/isolated_validator_spec.rb`, context `"with Docker"`).

## Why specs are skipped by default

`spec/spec_helper.rb` skips `:docker` examples unless:

1. `ENV["DOCKER_AVAILABLE"] == "true"`, and  
2. `/usr/bin/docker` exists and is executable, and  
3. `docker info` succeeds (daemon reachable).

This keeps CI and local runs **fast and deterministic** without pulling or running containers.

## Opt-in: one-time image build

Build the verification sandbox image once from the gem root (same Dockerfile referenced by `OLLAMA_AGENT_VALIDATOR_IMAGE` defaults in `KernelPipelineAssembly`):

```bash
docker build -f containers/ollama_agent-verification-sandbox.Dockerfile \
  -t ollama_agent-verification-sandbox:latest .
```

You may override the tag with `OLLAMA_AGENT_VALIDATOR_IMAGE` if your workflow pins a different name.

## Run only Docker-tagged specs

From the repository root:

```bash
export DOCKER_AVAILABLE=true
bundle exec rspec --tag docker --format documentation
```

RSpec prints filter metadata when the tag is active, for example: `Run options: include {:docker=>true}`.

Example successful output shape:

```text
OllamaAgent::Runtime::IsolatedValidator
  with Docker
    returns :ok and captures stdout for a simple echo
    does not expand host-shell metacharacters when argv is passed through to the container
    returns :runtime_unavailable when the runtime executable cannot be resolved

Finished in … seconds
3 examples, 0 failures
```

## Rake shortcuts

- `rake validator:build` — builds the default (or `OLLAMA_AGENT_VALIDATOR_IMAGE`) image.  
- `rake validator:run_specs` — sets `DOCKER_AVAILABLE=true` for the child process and runs `rspec --tag docker`.

**CI:** Do **not** enable `DOCKER_AVAILABLE` or invoke these Rake tasks in automated CI unless the runner explicitly provides Docker; keep Docker runs opt-in and documented here.
