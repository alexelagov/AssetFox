# Public Repository Checklist

Use this checklist before changing the GitHub repository visibility from private
to public.

## Required checks

- Confirm the working tree is clean with `git status --short`.
- Confirm local-only release files are ignored:
  - `Config/Telemetry.local.xcconfig`
  - `dist/`
  - `Builds/`
  - `*.app`
  - `*.zip`
  - `*.dmg`
  - `*.pkg`
- Run a secret scan against the full Git history. Prefer `gitleaks` or GitHub
  secret scanning before changing visibility.
- Rotate any credential that may have appeared in terminal output, logs,
  screenshots, or old commits.
- Confirm telemetry uses only a limited client-safe key. Never ship a Supabase
  service-role key or unrestricted backend secret in the app bundle.
- Rotate `ASSETFOX_TELEMETRY_KEY` in Supabase before publishing if the previous
  key appeared in local terminal output, screenshots, logs, or shared builds.
- Review Supabase security advisors. At the time this checklist was added,
  `public.rls_auto_enable()` was reported as an externally callable
  `SECURITY DEFINER` function and should be revoked, moved, or changed before
  public launch if it is not intentionally exposed.
- Confirm bundled third-party binaries are allowed to be redistributed and have
  attribution in `AssetFox/OpenSourceLicenses.txt`.
- Confirm the repository license matches the intended sharing model.

## Telemetry stance

The tracked source tree does not contain the production telemetry endpoint or
key. Public/default builds keep telemetry unconfigured unless
`ASSETFOX_TELEMETRY_ENDPOINT_URL` and `ASSETFOX_TELEMETRY_API_KEY` are injected
through the ignored local release config.

Internal release builds read telemetry settings from:

```text
Config/Telemetry.local.xcconfig
```

That file must remain local and ignored.

The Edge Function may run with `verify_jwt=false` only when it performs its own
authentication, validation, and abuse controls. `assetfox-telemetry` currently
checks `x-assetfox-telemetry-key` and validates event/property allowlists; add
rate limiting before broader distribution.

## Release artifacts

Do not commit packaged apps or zips to the repository. Publish distributable
builds through GitHub Releases or another release channel.

## After changing visibility

- Enable GitHub secret scanning if available.
- Enable branch protection on `main`.
- Require pull requests before merging to `main`.
- Keep release credentials outside the repository and outside GitHub issues.
