# syncode: install/update/uninstall editors

Date: 2026-08-17
Status: Approved design

## Summary

`syncode` gains the ability to install, update, and uninstall the two supported
editors (VS Code, VSCodium) from their official release channels, on both
platforms (Windows `syncode.ps1`, Linux `syncode.sh`). Version discovery uses
official APIs (no HTML scraping).

## New flags

Applied identically in both ports:

| Action | Short | Full |
| --- | --- | --- |
| Install missing editor(s) | `-i` | `--install [fork]` |
| Update installed editor(s) | `-u` | `--update [fork]` |
| Uninstall editor(s) | `-rm` | `--uninstall [fork]` |
| Show installed vs latest | `-V` | `--list-versions` |

- No fork arg = applies to all forks (install/update only the applicable ones).
- `-d`/`--dry-run` composes with all new flags: print the plan table, change
  nothing.
- Fork names: `code`, `codium` (as in existing `FORK_ORDER`).

## Release channels

### VS Code (`code`)

| Step | Endpoint | Result |
| --- | --- | --- |
| Latest version | `https://update.code.visualstudio.com/api/releases/stable` | JSON array, newest first; take `[0]` |
| Installer URL | `https://update.code.visualstudio.com/<ver>/<platform>/stable` | HTTP 302 to real installer |

Platform slugs: `win32-x64-user` (Windows user), `linux-deb-x64` (Debian/Ubuntu),
`linux-rpm-x64` (RHEL/Fedora), `linux-x64` (tarball fallback).

Verified 2026-08-17: `1.133.0/win32-x64-user/stable` → `VSCodeUserSetup-x64-1.133.0.exe`;
`1.133.0/linux-deb-x64/stable` → `code_1.133.0-…_amd64.deb`.

### VSCodium (`codium`)

| Step | Endpoint | Result |
| --- | --- | --- |
| Latest version | GitHub API `https://api.github.com/repos/VSCodium/vscodium/releases/latest` | `tag_name` (e.g. `1.126.04524`) |
| Installer URL | `https://github.com/VSCodium/vscodium/releases/download/<tag>/<asset>` | direct asset |

Assets (tag = `1.126.04524`, verified): Windows `VSCodiumUserSetup-x64-<tag>.exe`;
Linux `codium_<tag>_amd64.deb`, `codium-<tag>-el8.x86_64.rpm`,
`VSCodium-linux-x64-<tag>.tar.gz` fallback.

## Install flow

1. Print plan table: `name / installed / latest / action`.
2. Confirm (`Y/n`).
3. Download installer to temp dir.
4. Silent install:
   - Windows (both forks): Inno installer `/VERYSILENT /NORESTART`
     (VS Code user setup, VSCodium user setup).
   - Linux: detect package manager — `apt` → `sudo apt install ./<file>.deb`,
     `dnf`/`yum` → `sudo dnf install ./<file>.rpm`; fallback tarball →
     extract to `~/.local/share/<Code|VSCodium>`.
5. Run existing config sync (settings + extensions) for the installed fork.

## Update flow

Same as install, but only if installed version < latest. Compares via
`Get-InstalledVersion` vs latest. If already latest: report and skip download.

## Uninstall flow

- Windows: prefer `unins000.exe /VERYSILENT` (Inno uninstaller at
  `%LOCALAPPDATA%\Programs\<Code|VSCodium>\unins000.exe`); fallback
  `winget uninstall <id>`; then delete config dir `%APPDATA%\Code|VSCodium`.
- Linux: `sudo apt remove <code|codium>` / `sudo dnf remove <code|codium>`;
  tarball install → `rm -rf ~/.local/share/<Code|VSCodium>`; delete config dir
  `~/.config/<Code|VSCodium>`.

## Installed version detection (`Get-InstalledVersion`)

1. CLI on PATH → first line of `<fork> --version`.
2. Else read `resources/app/package.json` `version` field from known install
   paths:
   - Windows: `%LOCALAPPDATA%\Programs\Microsoft VS Code`,
     `%LOCALAPPDATA%\Programs\VSCodium`.
   - Linux: `/usr/share/code`, `/usr/share/codium`,
     `~/.local/share/VSCodium` (tarball).
3. After syncode itself installs a fork, read version directly from the known
   install path (no PATH dependency).

## Error handling

- Network failure → `[ERROR]` + exit 1, nothing mutated.
- Installer download interrupted → temp cleanup, exit 1.
- No package manager detected (Linux) → fall back to tarball install.
- `--install` on an already-installed fork → report "already installed", skip.

## Testing

- `bash -n` and PowerShell parser check on both scripts (existing convention).
- Dry-run of each new flag with `-d` (no mutation).
- Manual smoke: `--list-versions` on a machine with and without editors.

## Out of scope

- macOS (syncode.sh is Linux-only; syncode.ps1 is Windows-only by design).
- More editors (still `code` + `codium` only).
- Architecture variants (x64 only; arm64 noted in docs, not implemented).