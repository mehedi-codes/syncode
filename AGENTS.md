# AGENTS.md

Guidance for AI agents working in this repository.

## What this project is

**syncode** — a one-command tool that syncs your VS Code-family editor setup
(settings + extensions) to every installed editor fork. It detects which
editors are present, shows a plan, asks for confirmation, then copies
`settings.json` and installs missing extensions. It can also revert editors
to factory defaults.

There is **no build step, no package manager, no tests, no CI**. The tool is
two bash scripts; everything else is data or docs.

## Repository layout

| File | Role |
| --- | --- |
| `install.sh` | One-time runner: curl-fetches `syncode.sh` + configs into a temp dir and runs them. Requires curl. |
| `syncode.sh` | The whole tool (441 lines). Everything else is data or docs. |
| `settings.json` | Source-of-truth editor settings (JSONC). Applied to every selected editor. |
| `extensions.json` | Extension IDs to install (JSONC). Only `"publisher.name"` strings matter. |
| `extensions.md` | Usage guides for every extension listed in `extensions.json`. |
| `README.md` | User-facing docs. Keep in sync if CLI behavior changes. |

## Technology

- **Pure bash 4+** — no external dependencies beyond standard coreutils
  (`grep`, `cmp`, `cp`, `mv`, `rm`, `mktemp`, `printf`, `tr`, `uname`).
  Uses associative arrays, `[[ ]]`, background jobs for parallel detection.
  `install.sh` additionally needs `curl` (no git involved).
- **JSONC** (`settings.json`, `extensions.json`) — comments are valid and used
  as section headers (`//! Visual / UI`, etc.).
- **No Makefile, no lockfile, no npm/pip/anything.** Running the script IS the
  usage; there's nothing to install.

## How it works

Flow: `detect → plan → select → confirm → apply`.

1. **Detect** (`detect_forks`): checks each of `code codium cursor windsurf
   positron` on PATH or by its config directory, in parallel background jobs.
2. **Plan** (`plan_fork`): prints name/version/status table for all 5 forks,
   marking not-installed ones.
3. **Select**: interactive toggle menu only when >1 editor detected
   (numbers toggle, `a`=all, `n`=none, Enter=apply). Skipped in dry-run.
4. **Confirm**: `Y/n` prompt (defaults to yes).
5. **Apply** (`apply_fork`): per editor — copy settings (backing up existing
   to `settings.json.bak`), install only *missing* extensions.

### Platform handling (`$OSTYPE`)

| OS | `DATA_ROOT` | Notes |
| --- | --- | --- |
| `msys*`/`mingw*` (Git Bash) | `$APPDATA` | Windows |
| `linux*` + WSL marker | Windows AppData via `powershell.exe` | Targets **Windows** editor installs; stdin is redirected from `/dev/null` so `powershell.exe` can't eat interactive input |
| `linux*` (native) | `~/.config` | |
| `darwin*` | `~/Library/Application Support` | |

Every subprocess that doesn't need stdin (`powershell.exe`, `code --version`,
`--list-extensions`, `--install-extension`, detection subshells) gets
`</dev/null` so nothing can consume the script's interactive input — this was
the root cause of the confirm-prompt bug (interactive runs exited 1 when a
piped editor CLI ate the buffered answer). Keep this discipline for new
subprocess calls.

`FORK_DIR` maps fork → config dir name (`Code`, `VSCodium`, `Cursor`,
`Windsurf`, `Positron`).

### Revert mode (`-r`)

Per selected editor: restore `settings.json.bak` → `settings.json` (or delete
`settings.json` if no backup), then uninstall every extension listed in
`extensions.json`.

## How to run

```bash
# One-time (no git, no cache — curl-fetches latest + runs from a temp dir)
curl -fsSL https://raw.githubusercontent.com/mehedi-codes/syncode/main/install.sh -o /tmp/syncode-install.sh && bash /tmp/syncode-install.sh

bash syncode.sh            # apply (interactive selection when >1 editor)
bash syncode.sh -d         # dry-run: plan only, changes nothing — safe to run anywhere
bash syncode.sh -r         # revert to factory defaults
bash syncode.sh -r -d      # revert plan only
bash syncode.sh -h | -v    # help / version
```

`install.sh` passes flags through to `syncode.sh` (e.g. `-d` for a dry-run).

**Testing / verification without touching a real machine:**

- `bash -n syncode.sh` — syntax check.
- `bash syncode.sh -d` — dry run; runs detection + plan, applies nothing.
- `shellcheck syncode.sh` if available (not a repo dependency).
- ⚠️ `bash syncode.sh` (without `-d`) **writes to real editor config dirs**
  and can overwrite `settings.json` (backed up first). Never run it in
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

- **Zero dependencies** — pure bash 4+, runs anywhere bash exists (Git Bash,
  WSL, macOS, Linux). The one-liner additionally needs curl (no git).
- **Idempotent & safe** — double-run is a no-op; settings are backed up to
  `.bak` before overwrite; user-installed extensions are never touched.
- **Two small files** — the whole tool is `syncode.sh` (441 lines) plus a
  ~30-line `install.sh` runner, with no build/install step.
- **Cross-fork** — one config drives VS Code, VSCodium, Cursor, Windsurf,
  and Positron.
- **Dry-run & revert** built in, so it's auditable and undoable.
- Parallel editor detection keeps startup fast.

## Cons / gotchas

- **macOS ships bash 3.2** — script refuses to run (`bash 4+` guard) until
  the user installs bash via Homebrew. This is the #1 user friction point.
- **WSL only syncs Windows installs** — it resolves Windows AppData and
  ignores Linux-native editor installs under WSL.
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
- **No tests** — verification is manual (`bash -n`, `-d` dry-run). Don't
  assume behavior is covered by anything automated.
- **Monolithic script** — all logic lives in one file; changes are
  low-risk individually but there's no unit isolation.