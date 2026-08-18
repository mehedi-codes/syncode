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
> Sync and manage your VS Code and VSCodium editors.

**Settings sync for VS Code and VSCodium, from one command.** `syncode`
detects which editors are installed, shows you a plan, and — with
your confirmation — copies `settings.json` and installs the extensions listed
in `extensions.json`. Run it once to set up a new machine, or re-run it any
time to bring an editor back in sync. It can also install or
uninstall the editors themselves.

## Supported editors

| Fork | Config dir |
| --- | --- |
| VS Code | `Code` |
| VSCodium | `VSCodium` |

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
curl -fsSL https://raw.githubusercontent.com/mehedi-codes/syncode/main/install.sh -o /tmp/syncode-install.sh && bash /tmp/syncode-install.sh
```

**Windows** (PowerShell; needs no curl — uses `Invoke-RestMethod`):

```powershell
$p="$env:temp\s.ps1";irm https://raw.githubusercontent.com/mehedi-codes/syncode/main/install.ps1 -OutFile $p;& $p
```

Flags pass through to the runner (`-d`, `-r`, `-v`, `-h`, `-i`, `-rm`),
e.g. append `-d` to the Windows one-liner (`...; & $p -d`) for a dry-run.
Prefer cloning? The repo runs directly too — see [Usage](#usage).

## Usage

**Linux:**

```bash
bash linux/syncode.sh        # interactive dashboard (no flags)
bash linux/syncode.sh -d     # preview the plan, change nothing
bash linux/syncode.sh -r     # restore editors to factory defaults
bash linux/syncode.sh -l     # show installed vs latest versions
bash linux/syncode.sh -i     # install latest stable for all editors
bash linux/syncode.sh -i codium   # install just VSCodium
bash linux/syncode.sh -rm    # uninstall all editors + config dirs
```

**Windows (PowerShell):**

```powershell
.\windows\syncode.ps1        # interactive dashboard (no flags)
.\windows\syncode.ps1 -d     # preview the plan, change nothing
.\windows\syncode.ps1 -r     # restore editors to factory defaults
.\windows\syncode.ps1 -l     # show installed vs latest versions
.\windows\syncode.ps1 -i     # install latest stable for all editors
.\windows\syncode.ps1 -i codium       # install just VSCodium
.\windows\syncode.ps1 -rm    # uninstall all editors + config dirs
```

### Options

| Flag | Description |
| --- | --- |
| `-h`, `--help` | Show help and exit |
| `-v`, `--version` | Show version and exit |
| `-d`, `--dry-run` | Show the plan for all editor families, apply nothing |
| `-r`, `--revert` | Restore editors to factory defaults (see below) |
| `-i`, `--install [fork]` | Install latest stable. Bare `-i` = all editors; `-i codium` = one fork (same for `-rm`) |
| `-rm`, `--uninstall [fork]` | Remove the editor and its config dir |
| `-l`, `--list-versions` | Show installed vs latest versions, then exit |

> **Windows note:** PowerShell is case-insensitive, so `-l` (lowercase L) is
> the list-versions flag; the version flag is `-v`. The long form
> `-ListVersions` also works.

### Interactive dashboard

Run with no flags to get a live dashboard instead of the one-shot plan:

```
  name     installed    latest      settings  extensions
  code     1.132.0      1.133.0     synced    2 missing
  codium   1.126.04524  1.126.04524 diverged  1 missing

  pick editor (1=code 2=codium, q=quit)
  action for code (install/config/reset/uninstall/help, q=quit)
```

Each row shows installed vs latest version (fetched live from the official
release APIs, cached per session), whether settings are in sync, and the
missing-extension count. Pick an editor, then an action — `config` syncs
settings + extensions, `install`/`uninstall` manage the editor
itself (downloads are written to a `syncode-*` temp file; Windows installs
run `/VERYSILENT /NORESTART /mergetasks=!runcode` so the editor never
launches on its own). `reset` and `uninstall` require typing the word to
confirm. `q` quits; invalid input just re-prompts.

## What it does

1. **Detect** — checks for `code`, `codium` on PATH or by config directory
   (in parallel).
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
bash linux/syncode.sh -r      # interactive selection, then confirm
bash linux/syncode.sh -r -d   # plan for all editor families, apply nothing
```

```powershell
.\windows\syncode.ps1 -r      # interactive selection, then confirm
.\windows\syncode.ps1 -r -d   # plan for all editor families, apply nothing
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
linux/            syncode.sh + version.sh + release.sh — Linux deploy (bash)
windows/          syncode.ps1 + version.ps1 + release.ps1 — Windows (PowerShell)
shared/           settings.json + extensions.json + releases.json + extensions.md
                  (configs live in shared/; scripts find them via ../shared in a
                  checkout, or beside the script in the install temp dir)
```

`releases.json` maps each editor fork to its release API, installer URLs,
uninstall method, and winget id — it's what powers `-i/-rm/-l` and the
dashboard's latest column. Version comparison lives in `version.sh`/`.ps1`;
release lookups in `release.sh`/`.ps1`. Each module has a self-check that
runs when executed directly (e.g. `bash linux/release.sh`).

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
