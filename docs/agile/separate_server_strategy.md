# Separate Server Strategy

Default delivery mode is local runtime execution within the CLI process.

## No-Server First

Use local mode by default when:

- single-user workflows dominate
- repo-local state is acceptable
- always-on orchestration is not required

## Trigger Conditions for Separate Server

Introduce a dedicated server only when one or more are true:

- multi-user concurrent orchestration is required
- always-on shared recovery coordination is required
- centralized compliance and audit controls are mandatory
- a remote shared endpoint is needed for non-CLI clients

## Architecture Rule

If server mode is introduced, it must wrap existing kernel primitives and must
not fork runtime logic from local mode. Local mode remains first-class.
