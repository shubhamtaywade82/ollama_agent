# Minimal sandbox for post-condition / isolated validation (array-exec only at the Docker CLI).
# Build: docker build -f containers/ollama_agent-verification-sandbox.Dockerfile -t ollama-agent-validator:local .
#
# ruby:3.3-slim is smaller than the default non-slim image while keeping glibc compatibility.
FROM ruby:3.3-slim-bookworm

RUN groupadd --system --gid 65532 sandbox \
  && useradd --system --uid 65532 --gid sandbox --home-dir /workspace --shell /usr/sbin/nologin sandbox

WORKDIR /workspace

# Replace with a concrete argv at `docker run ... image <cmd...>`; this is only a smoke default.
ENTRYPOINT []
CMD ["ruby", "-rjson", "-e", "puts JSON.dump({ok: true})"]

USER sandbox
