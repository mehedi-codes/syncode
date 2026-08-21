# AGENTS.md

Guidance for AI agents working in this repository.

## What this project is

**syncode** — a one-command tool that syncs your editor setup (settings +
extensions) to every installed editor: VS Code, VSCodium, and Zed, each with
its own config. It is a single
**interactive dashboard**: a repaint loop that shows a status table
(installed / latest / settings / extensions) for each editor, then lets you
pick an editor and an action — install (with an installer-variant picker on
Windows), config (settings / extensions), reset to factory defaults, or
uninstall. There are **no CLI flags**; running the script opens the
dashboard, and that's the whole tool. The tool takes no arguments.

There is **no build step, no package manager, no unit tests**. The tool is
three bash + three PowerShell scripts under `linux/`/`windows/`, plus config
data under `shared/`; everything else is docs. CI (GitHub Actions) runs
sandboxed dashboard smoke tests + syntax/parse checks — see the layout table.

## Repository layout

| File | Role |
| --- | --- |
| `install.sh` | Linux one-time runner (root): curl-fetches `linux/syncode.sh` + configs into a temp dir and runs them. Requires curl. |
| `install.ps1` | Windows one-time runner (root): `Invoke-WebRequest` fetches `windows/syncode.ps1` + configs into a temp dir and runs them. |
| `linux/syncode.sh` | The whole Linux tool (~620 lines, bash). |
| `linux/version.sh` | Linux version comparison module (sourced by `syncode.sh`). |
| `linux/release.sh` | Linux release lookups: reads `releases.json`, fetches latest versions, builds installer URLs (sourced by `syncode.sh`). |
| `windows/syncode.ps1` | The whole Windows tool (PowerShell). |
| `windows/version.ps1` | Windows version comparison module (dot-sourced by `syncode.ps1`). |
| `windows/release.ps1` | Windows release lookups (dot-sourced by `syncode.ps1`). |
| `shared/<editor>/settings.json` | Source-of-truth settings per editor (`code/`, `codium/`, `zed/`), JSONC. Applied via the dashboard's config → Settings. |
| `shared/<editor>/extensions.json` | Extension IDs to install per editor (JSONC). Only quoted ID strings matter — see the parsing conventions below. |
| `shared/releases.json` | Per-editor release facts: latest-API URL, installer URLs, uninstall method, winget id. Powers the dashboard's install/uninstall and latest column. |
| `shared/extensions.md` | Usage guides for every extension listed in all three `extensions.json` files. |
| `.github/workflows/ci.yml` | GitHub Actions entrypoint: Linux checks (`bash .github/ci/linux.sh`) + Windows checks (`.github/ci/windows.ps1` under pwsh 7 and 5.1). |
| `.github/ci/linux.sh` | Linux CI: bash syntax, release self-check, sandbox dashboard smoke tests (checkout + flattened layouts), extensions.md coverage, version lockstep. |
| `.github/ci/windows.ps1` | Windows CI: ps1 parse (7 + 5.1) + ASCII check, sandbox dashboard smoke tests (checkout + flattened layouts). |
| `README.md` | User-facing docs. Keep in sync if CLI behavior changes. |

Platform dirs (`linux/`, `windows/`) hold the scripts; `shared/<editor>/`
holds each editor's configs. Scripts resolve configs beside themselves in
per-editor subdirs (install temp dir, where the installers flatten into
`<editor>/`) or via `../shared` (repo checkout).

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
  lockstep (same output, same version string). No flags — a stray argument
  is an error.
- **JSONC** (`settings.json`, `extensions.json`, `releases.json`) — comments
  are valid and used as section headers (`//! Visual / UI`, etc.).
- **No Makefile, no lockfile, no npm/pip/anything.** Running the script IS the
  usage; there's nothing to install.

## How it works

The tool is one **dashboard** — a repaint loop. There is no flag-driven plan
flow; everything (install, config, reset, uninstall) is a dashboard action.

1. **Render** (`render_dashboard`/`Show-Dashboard`): a boxed status table for
   all 3 editors — installed version, latest version, settings sync state,
   missing-extension count. Detection (`detect_forks`) runs in parallel and
   caches results per session.
2. **Pick** (`run_dashboard`/`Run-Dashboard`): pick an editor, then an
   action. The action menu offers Install, then Config / Reset only when the
   editor is installed, then Uninstall / Menu / Quit.
3. **Act**: `install_editor`/`Install-Editor` (Linux picks the variant by
   package manager; Windows asks for User / System / MSI; Zed skips the
   variant picker — one installer),
   `apply_fork`/`Apply-Fork` (settings + extensions, with `REVERT`/`$Revert`
   toggling factory-reset behavior), `uninstall_editor`/`Uninstall-Editor`.
   Extensions use a multiselect picker (toggle numbers, `a`=all, `n`=none,
   `i`/`u` install/uninstall selection). For Zed there is no extension CLI:
   install queues `"id": true` into the source template's
   `auto_install_extensions` and redeploys settings (`zed_ext_set`/
   `Set-ZedExtension`); uninstall marks it false and deletes the extension's
   folder under `%LOCALAPPDATA%\Zed\extensions\installed` /
   `~/.local/share/zed/extensions/installed`.

The dashboard is a **repaint loop**: every pick clears the screen (TTY only)
and redraws the banner + status table + a notice line + the active menu, all
flush-left with blank lines framing the option list. The status table is a
**boxed grid** (ASCII `+---+` only — 5.1 can't render box-drawing glyphs, and
output stays byte-identical between ports): column widths = longest cell
(header or value) + 2 padding so nothing overflows, headers are Title Case
and bold on a TTY, and the editor's name is folded into the menu prompt
(`Pick an option for VSCode:`). Feedback (installed
extensions, invalid input, skipped confirmations) goes to the
notice line so it survives the repaint; bash keeps it in `DASH_NOTICE`, ps1 in
`$script:Notice`. Non-terminal output skips the clear and stacks frames.
Keep both ports in lockstep for all of this.

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

`FORK_DIR` maps fork → config dir name (`Code`, `VSCodium`, `zed`).
`FORK_EXT_DIR[zed]` points at Zed's extension install dir (the VSCode-family
forks manage extensions through their CLI instead).

### Reset (dashboard action)

Per editor: restore `settings.json.bak` → `settings.json` (or delete
`settings.json` if no backup), then uninstall every extension listed in
`extensions.json`. Requires typing `reset` to confirm.

## How to run

```bash
# Linux (no git, no cache — curl-fetches latest + runs from a temp dir)
curl -fsSL https://raw.githubusercontent.com/mehedi-codes/syncode/main/install.sh -o syncode-install.sh && bash syncode-install.sh

bash linux/syncode.sh   # interactive dashboard (no arguments)
```

```powershell
# Windows (irm fetches latest + runs from a temp dir)
irm https://raw.githubusercontent.com/mehedi-codes/syncode/main/install.ps1 -OutFile install.ps1; .\install.ps1

.\windows\syncode.ps1   # interactive dashboard (no arguments)
```

The tools resolve `settings.json`/`extensions.json` beside the script
(install temp dir) or via `../shared` (repo checkout).

**Testing / verification without touching a real machine:**

- CI (`.github/workflows/ci.yml`) runs on every push/PR: bash syntax check,
  sandboxed dashboard smoke tests for both config layouts (checkout
  `../shared` and flattened install) — fake `code`/`codium`/`zed` on PATH,
  then `q` piped in and assertions on the rendered frame — PowerShell parse
  checks on pwsh 7 + 5.1, ASCII-only source check across all tool scripts (5.1
  misreads non-ASCII ps1 as ANSI — a real regression source; bash must stay
  ASCII too so the ports' output stays byte-identical), `extensions.md`
  coverage of every `extensions.json` ID (all three files), and bash/ps1
  version lockstep.
- Locally: Linux — `bash -n linux/syncode.sh`;
  `printf 'q\n' | bash linux/syncode.sh` (dashboard smoke run).
  `bash linux/release.sh` runs the release module self-check (no network).
- Windows: `"q" | pwsh -NoProfile -File windows/syncode.ps1` (dashboard smoke
  run); `powershell.exe -NoProfile -File windows/syncode.ps1` for the 5.1
  path. Parse check:
  `[System.Management.Automation.Language.Parser]::ParseFile('windows/syncode.ps1',[ref]$null,[ref]$err)`.
- `shellcheck linux/syncode.sh` if available (not a repo dependency).
- ⚠️ Running **writes to real editor config dirs** and can overwrite
  `settings.json` (backed up first). Never run it in automated/CI contexts
  or against machines you don't own unless asked.

## Conventions & rules for agents

- **Never edit code with `set -euo pipefail` semantics in mind** — the script
  relies on `set -Eeuo pipefail`; every subshell, background job, and `wait`
  already tolerates individual failures (`|| true`). Keep that discipline.
- **Logging goes to stderr** via `log_info`/`log_warn`/`log_error` with
  `[INFO ]`-style prefixes. User-facing progress (`echo`) goes to stdout.
- **No new dependencies.** Prefer a few lines of coreutils + bash builtins
  over adding tools. This is a deliberate zero-dependency design.
- **`extensions.json` is parsed by regex**, not a JSON parser:
  - `code`/`codium`: `grep -oE '"[a-z0-9-]+\.[a-z0-9-]+"'` (`ext_ids`) —
    IDs must be lowercase `publisher.name`; any string with that shape
    anywhere in the file counts as an extension, so no prose with that shape.
  - `zed`: line-based — each ID sits ALONE on its line as `"id"` with an
    optional trailing comma (`sed -n 's/.../p'`). No trailing comments on ID
    lines. The constraint is documented in the file header.
  - Comments are fine in both; keep values quoted strings.
- **Settings are per editor**: `<editor>/settings.json` is applied verbatim
  to that editor only. Keep every file portable: no absolute paths, no
  OS-specific keys (fonts, terminal default profiles, machine paths).
- **`extensions.md` must stay in sync with all three `extensions.json`
  files** — every ID is documented there; CI enforces it per file.
- **Verified against Open VSX / the Zed registry** — code/codium IDs exist on
  Open VSX (VS Code installs the same IDs from Microsoft Marketplace);
  zed IDs exist on the Zed extension registry. Proprietary extensions fail
  to install — `syncode` reports and continues by design.
- **Idempotency is a feature**: running twice is a no-op. Settings compared
  with `cmp -s`; only missing extensions are installed; never uninstall
  extensions the user added themselves (except in Reset mode, which only
  removes extensions syncode manages).
- Commit style is Conventional Commits (`feat:`, `fix:`, `docs:`, `style:`).

## Pros

- **Zero dependencies** — pure bash 4+ on Linux, built-in cmdlets only on
  Windows PowerShell. The one-liners need curl (Linux) or nothing extra
  (Windows).
- **Idempotent & safe** — double-run is a no-op; settings are backed up to
  `.bak` before overwrite; user-installed extensions are never touched.
- **Six small files** — `syncode.sh` (~620 lines) + `version.sh`/`release.sh`
  modules + `install.sh` runner on Linux, the matching PowerShell trio on
  Windows, no build/install step.
- **Native per platform** — bash on Linux, PowerShell on Windows; no
  Git Bash, WSL, or cross-shell shims.
- **Cross-editor** — one repo drives VS Code, VSCodium, and Zed (per-editor
  configs, shared release facts).
- **One surface** — a single interactive dashboard; nothing to memorize.
- Parallel editor detection keeps startup fast (bash version).

## Cons / gotchas

- **Two implementations to keep in lockstep** — the bash and PowerShell
  ports must stay feature-identical (same output, version string).
  Change both in the same commit.
- **macOS unsupported** — `syncode.sh` is Linux-only by design; macOS users
  get the Linux tool only via bash if they install a bash 4+.
- **Interactive only** — no flags means no non-interactive/scripted use;
  the dashboard needs a terminal.
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
- **No unit tests** — CI runs sandboxed dashboard smoke tests, syntax/parse
  checks, doc coverage, and version lockstep; it doesn't exercise full
  behavioral coverage (every action path, network release lookups).
- **Monolithic script** — all logic lives in one file; changes are
  low-risk individually but there's no unit isolation.
