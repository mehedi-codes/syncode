# syncode: interactive dashboard (status + actions) and release-channel modules

Date: 2026-08-17
Status: Approved design
Supersedes/extends: `2026-08-17-install-update-uninstall-editors-design.md`

## Summary

`syncode` becomes an interactive tool: running it with no flags shows a status
dashboard for both editors (code, codium), lets the user pick one editor and
one action (install / update / config / reset / uninstall / help), and loops
back to the dashboard after each action. All existing flags remain as
non-interactive automation shortcuts that skip the menu.

The release-channel data behind install/update/uninstall moves out of both
scripts into one shared `releases.json`, loaded by both ports. New sourced
modules (`release`, `version`) hold the release-channel logic and the version
comparator.

## Entry-point behavior

### No flags (default) — interactive hub

1. Show status dashboard (4 columns per editor).
2. User picks one editor (single-select).
3. User picks an action: `install` / `update` / `config` / `reset` / `uninstall` / `help`.
4. Destructive actions require typing the full action name to confirm:
   - `Type "reset" to confirm` / `Type "uninstall" to confirm`
5. After the action completes, loop back to the dashboard (state re-read, so a
   fresh install shows `not synced` / `none installed` until `config` runs).
6. `q` quits (exit 0).

### Flags — automation shortcuts (bypass menu)

| Action | Short | Full |
| --- | --- | --- |
| Install missing editor(s) | `-i` | `--install [fork]` |
| Update installed editor(s) | `-u` | `--update [fork]` |
| Uninstall editor(s) | `-rm` | `--uninstall [fork]` |
| Show installed vs latest | `-V` | `--list-versions` |

- `-d`/`--dry-run` composes with all flags: print plan table, change nothing.
- Existing `-r`/`--revert` (flag path for reset) stays.
- Flag with no fork arg applies to all forks.
- `install.ps1`/`install.sh` pass flags through unchanged (scriptable one-time
  runs still work).

## Status dashboard

One row per editor, 4 columns:

| name | installed | latest | settings | extensions |
| --- | --- | --- | --- | --- |
| code | 1.133.0 | 1.133.0 | ✓ synced | ✓ up to date |
| codium | — | 1.126.04524 | — | — |

- `installed`: version from `Get-InstalledVersion` (CLI first, `package.json`
  fallback), or `—` if no editor detected (no CLI, no install path, no config
  dir).
- `latest`: live lookup (parallel, with timeout); `unknown` if unreachable.
  Not blocking — dashboard renders, column fills when the call returns.
- `settings`: `synced` / `diverged` / `—` (no `settings.json`). Uses existing
  `Test-SameSettings` hash comparison.
- `extensions`: `up to date` / `N missing` / `none installed` / `n/a` (no CLI
  on PATH — same limitation as today).

Columns reflect live state on every dashboard render, including after actions.

## Action semantics

| Action | What it does | Confirm? |
| --- | --- | --- |
| install | install latest stable if missing (see channels) | no |
| update | upgrade if installed < latest; no-op if current | no |
| config | copy settings (+backup .bak), install missing extensions | no |
| reset | restore factory defaults (revert flow) | type "reset" |
| uninstall | remove editor + config dir | type "uninstall" |
| help | one-line explanation of each action, back to menu | — |

No auto-sync after install: install hands back to the dashboard; user runs
`config` explicitly.

## Release channels

### VS Code (`code`)

| Step | Endpoint | Result |
| --- | --- | --- |
| Latest version | `https://update.code.visualstudio.com/api/releases/stable` | JSON array, newest first; take `[0]` |
| Installer URL | `https://update.code.visualstudio.com/<ver>/<platform>/stable` | HTTP 302 to real installer |

### VSCodium (`codium`)

| Step | Endpoint | Result |
| --- | --- | --- |
| Latest version | `https://api.github.com/repos/VSCodium/vscodium/releases/latest` | `tag_name` |
| Installer URL | `https://github.com/VSCodium/vscodium/releases/download/<tag>/<asset>` | direct asset |

Verified 2026-08-17: VS Code latest 1.133.0; VSCodium latest 1.126.04524.
winget is NOT used for install/update (it lags: code 1.132.0 vs 1.133.0);
winget is uninstall fallback only.

## releases.json (shared data)

`src/shared/releases.json` — release-channel facts only. Fork identity
(`FORK_DIR`, `FORK_ORDER`) stays in the scripts.

```json
{
  "code": {
    "latestApi": "https://update.code.visualstudio.com/api/releases/stable",
    "installer": {
      "win":   "https://update.code.visualstudio.com/<ver>/win32-x64-user/stable",
      "linux": "https://update.code.visualstudio.com/<ver>/linux-deb-x64/stable"
    },
    "uninstaller": { "win": "unins000.exe", "linux": "" },
    "package": { "winget": "Microsoft.VisualStudioCode", "apt": "code", "dnf": "code" }
  },
  "codium": { "…": "…" }
}
```

- `win`/`linux` keys per platform; one `<ver>` placeholder substituted at use.
- Shipped through `install.ps1`/`install.sh` as a 4th fetched file beside the
  script (existing `$CONFIG_DIR` / `CONFIG_DIR` resolution reused unchanged).

## Module structure (both ports, in lockstep)

```
src/
  shared/
    settings.json   extensions.json   releases.json
  windows/
    syncode.ps1     ← entry: flags, dashboard, menu, orchestration
    release.ps1     ← load releases.json, latest-version API, installer URL
    version.ps1     ← pure comparator + installed-version detection
  linux/
    syncode.sh
    release.sh
    version.sh
```

- `syncode.sh` sources `release.sh`/`version.sh` from `$SCRIPT_DIR`;
  `syncode.ps1` dot-sources from `$PSScriptRoot`.
- **Comparator duplicated in both ports** (~10-line pure function, segment-wise,
  tolerant of differing segment counts e.g. `1.126.04524` vs `1.133.0`).
  Logic can't be shared across bash/PowerShell; data is what gets single-sourced.
- Detect/plan/apply stay in the entry script (not churning cold code).

## Version detection

1. CLI on PATH → first line of `<fork> --version`.
2. Else read `resources/app/package.json` `version` field from known install
   paths (Windows: `%LOCALAPPDATA%\Programs\Microsoft VS Code`,
   `%LOCALAPPDATA%\Programs\VSCodium`; Linux: `/usr/share/code`,
   `/usr/share/codium`, `~/.local/share/VSCodium`).

## Error handling

- Missing/invalid `releases.json`: hard `[ERROR]` + exit 1 for release commands
  (install/update/uninstall/list-versions). Plain apply (config/reset) keeps
  working without the file.
- Network failure on latest lookup: dashboard shows `unknown`, menu still works.
- Network failure on actual install/update: `[ERROR]` + exit 1, nothing mutated.
- No package manager (Linux): fall back to tarball install.
- `--install` on already-installed fork: report "already installed", skip.

## Testing

- `bash -n` and PowerShell parser check on all new/modified files.
- `version.sh`/`version.ps1` comparator is a pure function — directly testable
  with a tiny assert harness (no machine state).
- Dry-run of each flag (`-d`) — no mutation.
- Manual smoke: dashboard on machine with/without editors; install → dashboard
  shows not-synced; config → synced; reset/uninstall typed confirmation.

## Out of scope

- macOS (syncode.sh Linux-only, syncode.ps1 Windows-only by design).
- Editors beyond code + codium.
- Architecture variants (x64 only).
- Winget as install/update path (stale; uninstall fallback only).
