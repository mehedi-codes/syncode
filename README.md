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

Two implementations, one per platform:

| Platform | Tooling |
| --- | --- |
| **Linux** | `syncode.sh` + `install.sh` (bash 4+) |
| **Windows** | `syncode.ps1` + `install.ps1` (PowerShell) |

## Install

One-time runner — fetches the latest tool + config (no git, no cache) and
runs it from a temp dir.

**Linux** (needs bash 4+ and curl):

```bash
curl -fsSL https://raw.githubusercontent.com/mehedi-codes/syncode/main/install.sh -o syncode-install.sh && bash syncode-install.sh
```

**Windows** (PowerShell; needs no curl — uses `Invoke-RestMethod`):

```powershell
irm https://raw.githubusercontent.com/mehedi-codes/syncode/main/install.ps1 -OutFile install.ps1; .\install.ps1
```

Flags pass through to the runner (`-d`, `-r`, `-v`, `-h`), e.g.
`bash syncode-install.sh -d` or `.\install.ps1 -d` for a dry-run.

Prefer cloning? The repo runs directly too — see [Usage](#usage).

## Usage

**Linux:**

```bash
bash src/linux/syncode.sh     # detect → plan → select → confirm → apply
bash src/linux/syncode.sh -d  # preview the plan, change nothing
bash src/linux/syncode.sh -r  # restore editors to factory defaults
```

**Windows (PowerShell):**

```powershell
.\src\windows\syncode.ps1    # detect → plan → select → confirm → apply
.\src\windows\syncode.ps1 -d # preview the plan, change nothing
.\src\windows\syncode.ps1 -r # restore editors to factory defaults
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
bash src/linux/syncode.sh -r      # interactive selection, then confirm
bash src/linux/syncode.sh -r -d   # plan for all editor families, apply nothing
```

```powershell
.\src\windows\syncode.ps1 -r      # interactive selection, then confirm
.\src\windows\syncode.ps1 -r -d   # plan for all editor families, apply nothing
```

For each selected editor, revert:

1. Restores `settings.json.bak` → `settings.json` if a backup exists,
   otherwise deletes `settings.json` (editor returns to built-in defaults).
2. Uninstalls the extensions listed in `extensions.json` (only the ones
   syncode manages).

## Files

```
install.sh        one-time runner (root — curl-fetches tool + configs)
install.ps1       one-time runner (root — irm/Invoke-WebRequest fetches + runs)
src/linux/        syncode.sh — the Linux deploy script (bash)
src/windows/      syncode.ps1 — the Windows deploy script (PowerShell)
src/shared/       settings.json + extensions.json + extensions.md
                  (shared by both platforms; configs are found via ../shared
                  from a checkout, or beside the script in the install temp dir)
```

## Notes

- **Linux** needs **bash 4+** and curl; **Windows** needs **PowerShell**
  (5.1 or 7+; no curl required).
- Extensions are installed from the marketplace your editor uses (e.g.
  Open VSX for VSCodium). Proprietary extensions (GitHub Copilot) that have
  no marketplace equivalent will fail to install — syncode reports the
  failure and continues.
- Fonts, terminal default profiles, and other machine-specific settings are
  not portable across OSes; keep those out of `settings.json` or expect to
  adjust per machine.
