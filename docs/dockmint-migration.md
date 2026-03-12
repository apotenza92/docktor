# Docktor to Dockmint Release Migration

This document defines the release sequence for the Docktor to Dockmint migration.

## Release Sequence

| Release | Channel | `rename_phase` | Bundle IDs | Sparkle feed host | Homebrew aliases |
| --- | --- | --- | --- | --- | --- |
| R1 | Beta | `transition` | `pzc.Dockter.beta` | `apotenza92/docktor` | Keep `docktor@beta` |
| R2 | Stable + Beta | `transition` | `pzc.Dockter`, `pzc.Dockter.beta` | `apotenza92/docktor` | Keep `docktor`, `docktor@beta` |
| R3 | Stable + Beta | `cleanup` | `pzc.Dockmint`, `pzc.Dockmint.beta` | `apotenza92/dockmint` | Keep `docktor`, `docktor@beta` for one overlap release |
| R4 | Stable + Beta | `cleanup` | `pzc.Dockmint`, `pzc.Dockmint.beta` | `apotenza92/dockmint` | Remove `docktor`, `docktor@beta` |

## Required GitHub Configuration

Canonical releases must run from `apotenza92/dockmint`.

Repository variables on the canonical repo:

- `DOCKMINT_RENAME_PHASE=transition` for R1 and R2, then `cleanup` for R3 and later.
- `DOCKMINT_LEGACY_FEED_REPO=apotenza92/docktor`
- `DOCKMINT_PUBLISH_LEGACY_APPCASTS=true` for R1, R2, and R3
- `DOCKMINT_LEGACY_HOMEBREW_ALIAS_MODE=keep` for R1, R2, and R3

Repository secrets on the canonical repo:

- `LEGACY_FEED_GITHUB_TOKEN` so release automation can mirror appcasts into `apotenza92/docktor`
- the normal signing, notarization, Sparkle, and Homebrew release secrets described in `AGENTS.md`

`workflow_dispatch` also supports one-off overrides for:

- `rename_phase`
- `legacy_feed_repo`
- `publish_legacy_appcasts`
- `legacy_homebrew_alias_mode`

Use those overrides when preparing R3 or R4 if you do not want to update repo variables before tagging.

## Per-Release Checklist

### R1 Beta transition

- Release from `apotenza92/dockmint`.
- Use `rename_phase=transition`.
- Keep `publish_legacy_appcasts=true`.
- Keep `legacy_homebrew_alias_mode=keep`.
- Verify an installed `Docktor Beta` updates to `Dockmint Beta` without losing settings, login item registration, or update continuity.

### R2 Stable transition

- Release from `apotenza92/dockmint`.
- Keep `rename_phase=transition`.
- Keep `publish_legacy_appcasts=true`.
- Keep `legacy_homebrew_alias_mode=keep`.
- Verify an installed `Docktor` updates to `Dockmint` without resetting preferences or breaking `docktor://` URLs.

### R3 Cleanup cutover

- Release from `apotenza92/dockmint`.
- Switch to `rename_phase=cleanup`.
- Keep `publish_legacy_appcasts=true` for this release only.
- Keep `legacy_homebrew_alias_mode=keep` for this release only.
- Verify transition builds upgrade cleanly to `pzc.Dockmint` / `pzc.Dockmint.beta`.

### R4 Legacy removal

- Release from `apotenza92/dockmint`.
- Keep `rename_phase=cleanup`.
- Set `publish_legacy_appcasts=false`.
- Set `legacy_homebrew_alias_mode=remove`.
- Verify fresh installs and Sparkle-updated installs both resolve to `Dockmint`.

## Validation Expectations

Before tagging any migration release:

- `python3 scripts/release/validate_dockmint_migration.py`
- `./scripts/release.sh <version>`

`./scripts/release.sh` enforces canonical `apotenza92/dockmint` origin by default. Set `DOCKMINT_ALLOW_LEGACY_RELEASE_REPO=1` only for an intentional emergency override.
