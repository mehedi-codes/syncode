```
:'######:'##:::'##'##::: ##:'######::'#######:'########:'########:
'##... ##. ##:'##::###:: ##'##... ##'##.... ##:##.... ##:##.....::
 ##:::..::. ####:::####: ##:##:::..::##:::: ##:##:::: ##:##:::::::
. ######:::. ##::::## ## ##:##:::::::##:::: ##:##:::: ##:######:::
:..... ##::: ##::::##. ####:##:::::::##:::: ##:##:::: ##:##...::::
'##::: ##::: ##::::##:. ###:##::: ##:##:::: ##:##:::: ##:##:::::::
. ######:::: ##::::##::. ##. ######:. #######::########::########:
:......:::::..::::..::::..::......:::.......::........::........::
```
> Sync your editor setup to every VS Code-family editor, in one command.

`syncode` detects which editors are installed, shows you a plan, and — with
your confirmation — copies `settings.json` and installs the extensions listed
in `extensions.json`. Run it once to set up a new machine, or re-run it any
time to bring an editor back in sync.

## Supported editors

| Fork | Config dir |
| --- | --- |
| VS Code | `Code` |
| VSCodium | `VSCodium` |
| Cursor | `Cursor` |
| Windsurf | `Windsurf` |
| Positron | `Positron` |

Works on **Windows (Git Bash or WSL)**, **macOS**, and **Linux**. Platforms
are detected automatically via `$OSTYPE`; under WSL, syncode targets your
**Windows** editor installs.

## Usage

```bash
bash syncode.sh            # detect → plan → select → confirm → apply
bash syncode.sh -d         # preview the plan, change nothing
bash syncode.sh -r         # restore editors to factory defaults
```

### Options

| Flag | Description |
| --- | --- |
| `-h`, `--help` | Show help and exit |
| `-v`, `--version` | Show version and exit |
| `-d`, `--dry-run` | Show the plan for all editor families, apply nothing |
| `-r`, `--revert` | Restore editors to factory defaults (see below) |

## What it does

1. **Detect** — checks for `code`, `codium`, `cursor`, `windsurf`, `positron`
   on PATH or by config directory (in parallel).
2. **Plan** — prints a table (name / version / status) for all editor
   families, marking not-installed ones.
3. **Select** — when multiple editors are found, a toggle menu lets you pick
   (numbers toggle, `a` = all, `n` = none, Enter = apply checked). With
   `-d`, all detected editors are selected by default.
4. **Confirm** — asks for confirmation (`Y/n`, defaults to yes).
5. **Apply** — per editor, in order:
   - **Settings**: if `settings.json` differs, the current one is backed up
     to `settings.json.bak` and the repo copy is installed.
   - **Extensions**: only missing extensions are installed (never
     re-installs, never touches extensions you added yourself).

### Idempotent & safe

- Running it twice is a no-op — settings already in sync and extensions
  already installed are skipped.
- The previous settings are always preserved in `settings.json.bak` before
  any overwrite.
- Extensions you install on top of syncode's list are left alone.

## Reverting (factory defaults)

```bash
bash syncode.sh -r           # interactive selection, then confirm
bash syncode.sh -r -d        # plan for all editor families, apply nothing
```

For each selected editor, revert:

1. Restores `settings.json.bak` → `settings.json` if a backup exists,
   otherwise deletes `settings.json` (editor returns to built-in defaults).
2. Uninstalls the extensions listed in `extensions.json` (only the ones
   syncode manages).

## Files

```
syncode.sh        the deploy script
settings.json     your editor settings (applied to every editor)
extensions.json   extension IDs (installed when missing)
extensions.md     usage guides for every managed extension
```

## Notes

- Requires **bash 4+** — on Windows, Git Bash or WSL (run from within the repo
  or call by absolute path). macOS ships bash 3.2 by default; install a newer
  bash via Homebrew (`brew install bash`) and use it to run syncode.
- Extensions are installed from the marketplace your editor uses (e.g.
  Open VSX for VSCodium). Proprietary extensions (GitHub Copilot) that have
  no marketplace equivalent will fail to install — syncode reports the
  failure and continues.
- Fonts, terminal default profiles, and other machine-specific settings are
  not portable across OSes; keep those out of `settings.json` or expect to
  adjust per machine.
