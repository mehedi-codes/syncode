# AGENTS.md

Guidance for AI agents working in this repository.

## What this project is

**syncode** — a one-command tool that syncs your VS Code-family editor setup
(settings + extensions) to every installed editor fork. It detects which
editors are present, shows a plan, asks for confirmation, then copies
`settings.json` and installs missing extensions. It can also revert editors
to factory defaults, install/update/uninstall editor binaries (VS Code,
VSCodium) via release-channel lookups, and show installed-vs-latest versions.
No flags opens an interactive dashboard.

There is **no build step, no package manager, no unit tests**. The tool is
three bash + three PowerShell scripts under `linux/`/`windows/`, plus config
data under `shared/`; everything else is docs. CI (GitHub Actions) runs
sandboxed dry-runs + syntax/parse checks — see the layout table.

## Repository layout

| File | Role |
| --- | --- |
| `install.sh` | Linux one-time runner (root): curl-fetches `linux/syncode.sh` + configs into a temp dir and runs them. Requires curl. |
| `install.ps1` | Windows one-time runner (root): `Invoke-WebRequest` fetches `windows/syncode.ps1` + configs into a temp dir and runs them. |
| `linux/syncode.sh` | The whole Linux tool (~740 lines, bash). |
| `linux/version.sh` | Linux version comparison module (sourced by `syncode.sh`). |
| `linux/release.sh` | Linux release lookups: reads `releases.json`, fetches latest versions, builds installer URLs (sourced by `syncode.sh`). |
| `windows/syncode.ps1` | The whole Windows tool (PowerShell). |
| `windows/version.ps1` | Windows version comparison module (dot-sourced by `syncode.ps1`). |
| `windows/release.ps1` | Windows release lookups (dot-sourced by `syncode.ps1`). |
| `shared/settings.json` | Source-of-truth editor settings (JSONC). Applied to every selected editor. |
| `shared/extensions.json` | Extension IDs to install (JSONC). Only `"publisher.name"` strings matter. |
| `shared/releases.json` | Per-fork release facts: latest-API URL, installer URLs, uninstall method, winget id. Powers `-i/-u/-rm/-l` and the dashboard's latest column. |
| `shared/extensions.md` | Usage guides for every extension listed in `extensions.json`. |
| `.github/workflows/ci.yml` | GitHub Actions entrypoint: Linux checks (`bash .github/ci/linux.sh`) + Windows checks (`.github/ci/windows.ps1` under pwsh 7 and 5.1). |
| `.github/ci/linux.sh` | Linux CI: bash syntax, release self-check, sandbox dry-runs (checkout + flattened layouts), extensions.md coverage, version lockstep. |
| `.github/ci/windows.ps1` | Windows CI: ps1 parse (7 + 5.1) + ASCII check, sandbox dry-runs (checkout + flattened layouts). |
| `README.md` | User-facing docs. Keep in sync if CLI behavior changes. |

Platform dirs (`linux/`, `windows/`) hold the scripts; `shared/` holds the
configs. Scripts resolve configs beside themselves (install temp dir, where
the installers flatten everything) or via `../shared` (repo checkout).

## Technology

- **Linux: pure bash 4+** — no external dependencies beyond standard
  coreutils (`grep`, `sed`, `cmp`, `cp`, `mv`, `rm`, `mktemp`, `printf`,
  `tr`, `uname`). Uses associative arrays, `[[ ]]`, background jobs for
  parallel detection. `install.sh` additionally needs `curl` (no git
  involved); `release.sh` uses `curl` for latest-version lookups.
- **Windows: PowerShell 5.1+** — `syncode.ps1` uses built-in cmdlets only
  (`Invoke-WebRequest`, `Get-Command`, `Get-FileHash`, `[Console]::In`); no
  modules, no curl. `install.ps1` pins TLS 1.2 for 5.1.
- The two implementations are **feature-identical ports**; keep them in
  lockstep (same flags, same output, same version string).
- **JSONC** (`settings.json`, `extensions.json`, `releases.json`) — comments
  are valid and used as section headers (`//! Visual / UI`, etc.).
- **No Makefile, no lockfile, no npm/pip/anything.** Running the script IS the
  usage; there's nothing to install.

## How it works

Flow (apply/revert): `detect → plan → select → confirm → apply`.

1. **Detect** (`detect_forks`): checks each of `code codium` on PATH or by its
   config directory, in parallel background jobs.
2. **Plan** (`plan_fork`): prints name/version/status table for all 2 forks,
   marking not-installed ones.
3. **Select**: interactive toggle menu only when >1 editor detected
   (numbers toggle, `a`=all, `n`=none, Enter=apply). Skipped in dry-run.
4. **Confirm**: `Y/n` prompt (defaults to yes).
5. **Apply** (`apply_fork`): per editor — copy settings (backing up existing
   to `settings.json.bak`), install only *missing* extensions.

Beyond apply/revert there are **release-driven actions** (`-i` install,
`-u` update, `-rm` uninstall, `-l` list-versions) powered by the
`version.*`/`release.*` modules and `releases.json`, and a **dashboard**
(no flags) that wraps apply/reset/install/update/uninstall behind an
interactive picker. Keep both ports in lockstep for these too.

### Platform handling

| OS | Tool | `DATA_ROOT` |
| --- | --- | --- |
| Linux | `syncode.sh` | `~/.config` |
| Windows | `syncode.ps1` | `$env:APPDATA` |

`syncode.sh` refuses to run on anything but Linux (`$OSTYPE` guard) — Windows
uses `syncode.ps1`, no Git Bash/WSL involved.

Every subprocess that doesn't need stdin (`code --version`,
`--list-extensions`, `--install-extension`, detection subshells) gets
`</dev/null` so nothing can consume the script's interactive input — this was
the root cause of the confirm-prompt bug (interactive runs exited 1 when a
piped editor CLI ate the buffered answer). Keep this discipline for new
subprocess calls. The PowerShell port has the same concern: native CLI calls
get `$null |` piped in to close stdin, and prompts read via `[Console]::In`
(read-lines return `$null` on EOF, mirroring bash `read || ans=n`).

`FORK_DIR` maps fork → config dir name (`Code`, `VSCodium`).

### Revert mode (`-r`)

Per selected editor: restore `settings.json.bak` → `settings.json` (or delete
`settings.json` if no backup), then uninstall every extension listed in
`extensions.json`.

## How to run

```bash
# Linux (no git, no cache — curl-fetches latest + runs from a temp dir)
curl -fsSL https://raw.githubusercontent.com/mehedi-codes/syncode/main/install.sh -o syncode-install.sh && bash syncode-install.sh

bash linux/syncode.sh   # apply (interactive selection when >1 editor)
bash linux/syncode.sh -d   # dry-run: plan only, changes nothing — safe to run anywhere
bash linux/syncode.sh -r   # revert to factory defaults
bash linux/syncode.sh -r -d  # revert plan only
bash linux/syncode.sh -l   # installed vs latest versions
bash linux/syncode.sh -i   # install latest stable (code/codium; -i codium = one fork)
bash linux/syncode.sh -u   # update installed editors
bash linux/syncode.sh -rm  # uninstall editors + config dirs
bash linux/syncode.sh -h | -v  # help / version
```

```powershell
# Windows (irm fetches latest + runs from a temp dir)
irm https://raw.githubusercontent.com/mehedi-codes/syncode/main/install.ps1 -OutFile install.ps1; .\install.ps1

.\windows\syncode.ps1    # apply (interactive selection when >1 editor)
.\windows\syncode.ps1 -d # dry-run: plan only, changes nothing
.\windows\syncode.ps1 -r # revert to factory defaults
.\windows\syncode.ps1 -r -d  # revert plan only
.\windows\syncode.ps1 -l # installed vs latest versions
.\windows\syncode.ps1 -i # install latest stable (code/codium; -i codium = one fork)
.\windows\syncode.ps1 -u # update installed editors
.\windows\syncode.ps1 -rm # uninstall editors + config dirs
.\windows\syncode.ps1 -h | -v  # help / version
```

`install.sh`/`install.ps1` pass flags through to the tool (e.g. `-d` for a
dry-run). The tools resolve `settings.json`/`extensions.json` beside the
script (install temp dir) or via `../shared` (repo checkout).

**Testing / verification without touching a real machine:**

- CI (`.github/workflows/ci.yml`) runs on every push/PR: bash syntax check,
  sandboxed `-d` dry-runs for both config layouts (checkout `../shared` and
  flattened install), PowerShell parse checks on pwsh 7 + 5.1, ASCII-only
  source check across all tool scripts (5.1 misreads non-ASCII ps1 as ANSI —
  a real regression source; bash must stay ASCII too so the ports' output
  stays byte-identical), `extensions.md` coverage of every `extensions.json`
  ID, and bash/ps1 version lockstep.
- Locally: Linux — `bash -n linux/syncode.sh`; `bash linux/syncode.sh -d`.
  `bash linux/release.sh` runs the release module self-check (no network).
- Windows: `windows/syncode.ps1 -d` in pwsh;
  `powershell.exe -File windows/syncode.ps1 -d` for the 5.1 path. Parse
  check: `[System.Management.Automation.Language.Parser]::ParseFile('windows/syncode.ps1',[ref]$null,[ref]$err)`.
- `shellcheck linux/syncode.sh` if available (not a repo dependency).
- ⚠️ Running without `-d` **writes to real editor config dirs** and can
  overwrite `settings.json` (backed up first). Never run it in
  automated/CI contexts or against machines you don't own unless asked.

## Conventions & rules for agents

- **Never edit code with `set -euo pipefail` semantics in mind** — the script
  relies on `set -Eeuo pipefail`; every subshell, background job, and `wait`
  already tolerates individual failures (`|| true`). Keep that discipline.
- **Logging goes to stderr** via `log_info`/`log_warn`/`log_error` with
  `[INFO ]`-style prefixes. User-facing progress (`echo`) goes to stdout.
- **No new dependencies.** Prefer a few lines of coreutils + bash builtins
  over adding tools. This is a deliberate zero-dependency design.
- **`extensions.json` is parsed by regex**, not a JSON parser:
  `grep -oE '"[a-z0-9-]+\.[a-z0-9-]+"'` (`ext_ids`). Consequences:
  - IDs must be lowercase `publisher.name` (no uppercase, no dots inside the
    name beyond the publisher separator).
  - Comments are fine, but keep values quoted strings.
  - Any string that *looks* like `publisher.name` anywhere in the file counts
    as an extension — don't add prose text with that shape.
- **`settings.json` is applied verbatim** to every editor. Keep it portable:
  no absolute paths, no OS-specific keys (fonts, terminal default profiles,
  machine paths). VSCodium-only keys like `workbench.experimental.*` are
  tolerated by other forks, but know they exist.
- **`extensions.md` must stay in sync with `extensions.json`** — every ID in
  the JSON is documented there; they're grouped by the same `//!` section
  comments.
- **Verified against Open VSX** — extension IDs in this repo are chosen
  because they exist on Open VSX (the VSCodium marketplace). VS Code installs
  the same IDs from the Microsoft Marketplace. Proprietary extensions
  (e.g. GitHub Copilot) don't exist on Open VSX and will fail to install —
  `syncode` reports and continues by design.
- **Idempotency is a feature**: running twice is a no-op. Settings compared
  with `cmp -s`; only missing extensions are installed; never uninstall
  extensions the user added themselves (except in `-r` mode, which only
  removes extensions syncode manages).
- Commit style is Conventional Commits (`feat:`, `fix:`, `docs:`, `style:`).

## Pros

- **Zero dependencies** — pure bash 4+ on Linux, built-in cmdlets only on
  Windows PowerShell. The one-liners need curl (Linux) or nothing extra
  (Windows).
- **Idempotent & safe** — double-run is a no-op; settings are backed up to
  `.bak` before overwrite; user-installed extensions are never touched.
- **Six small files** — `syncode.sh` (~740 lines) + `version.sh`/`release.sh`
  modules + `install.sh` runner on Linux, the matching PowerShell trio on
  Windows, no build/install step.
- **Native per platform** — bash on Linux, PowerShell on Windows; no
  Git Bash, WSL, or cross-shell shims.
- **Cross-fork** — one config drives VS Code and VSCodium.
- **Dry-run & revert** built in, so it's auditable and undoable.
- Parallel editor detection keeps startup fast (bash version).

## Cons / gotchas

- **Two implementations to keep in lockstep** — the bash and PowerShell
  ports must stay feature-identical (same flags, output, version string).
  Change both in the same commit.
- **macOS unsupported** — `syncode.sh` is Linux-only by design; macOS users
  get the Linux tool only via bash if they install a bash 4+.
- **No JSON parser** — `extensions.json` parsing is regex-based; silently
  wrong if the format drifts (see conventions above).
- **Proprietary extensions can't be synced** — anything not on Open VSX
  fails to install (by design, reported as a warning).
- **Machine-specific settings aren't portable** — fonts, terminal profiles,
  absolute paths must be excluded from `settings.json` or they'll break on
  other OSes.
- **`custom-ui-style` patches editor installation files** — the one managed
  extension with real side effects; rollback exists but it's the riskiest
  piece of the setup.
- **No unit tests** — CI runs sandboxed `-d` dry-runs, syntax/parse checks,
  doc coverage, and version lockstep; it doesn't exercise full behavioral
  coverage (interactive apply/revert, network release lookups).
- **Monolithic script** — all logic lives in one file; changes are
  low-risk individually but there's no unit isolation.