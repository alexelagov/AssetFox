# Security Policy

## Supported versions

AssetFox is currently in alpha. Security fixes are handled on the latest active
development branch and release build only.

## Reporting a vulnerability

Do not open a public GitHub issue for secrets, private infrastructure details,
or exploitable vulnerabilities.

Report privately to the repository owner or maintainer. Include:

- affected AssetFox version and build
- reproduction steps
- expected impact
- relevant logs with file paths, media names, credentials, and project names
  removed

## Public repository rules

- Do not commit `Config/Telemetry.local.xcconfig`.
- Do not commit `.app`, `.zip`, `.dmg`, `.pkg`, `dist/`, or `Builds/` artifacts.
- Do not commit production telemetry keys, Supabase service-role keys, signing
  certificates, provisioning profiles, private keys, or local machine paths.
- Treat client-bundled telemetry keys as public identifiers. Authorization and
  rate limiting must be enforced by the backend.
- Run a secret scan before making private branches or repository history public.
