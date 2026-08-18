```
:'######::'##:::'##:'##::: ##::'######:::'#######::'########::'########:
'##... ##:. ##:'##:: ###:: ##:'##... ##:'##.... ##: ##.... ##: ##.....::
 ##:::..:::. ####::: ####: ##: ##:::..:: ##:::: ##: ##:::: ##: ##:::::::
. ######::::. ##:::: ## ## ##: ##::::::: ##:::: ##: ##:::: ##: ######:::
:..... ##:::: ##:::: ##. ####: ##::::::: ##:::: ##: ##:::: ##: ##...::::
'##::: ##:::: ##:::: ##:. ###: ##::: ##: ##:::: ##: ##:::: ##: ##:::::::
. ######::::: ##:::: ##::. ##:. ######::. #######:: ########:: ########:
:......::::::..:::::..::::..:::......::::.......:::........:::........::
```

# syncode

> Sync and manage your VS Code and VSCodium editors.

**syncode** keeps your VS Code-style editors in sync from one command. It
detects which editors you have, copies your settings in, and installs your
extensions — so a fresh machine ends up with the same editor setup.

- **New machine?** Run it once and your editors are configured.
- **Changed something?** Run it again — it only fills in what's missing.
- **Curious?** Preview everything with `-d` before it touches anything.

## Install

One-line installers fetch the latest tool and config, then run from a temp
folder (no git, no cache, nothing installed on your system).

**Linux** — needs bash 4+ and curl:

```bash
curl -fsSL https://raw.githubusercontent.com/mehedi-codes/syncode/main/install.sh -o /tmp/syncode-install.sh && bash /tmp/syncode-install.sh
```

**Windows** — needs PowerShell 5.1+ (no curl):

```powershell
$p="$env:temp\s.ps1";irm https://raw.githubusercontent.com/mehedi-codes/syncode/main/install.ps1 -OutFile $p;& $p
```

Flags pass through to the installer too — append `-d` for a safe dry-run,
e.g. Windows: `...; & $p -d`.

Prefer cloning? The repo runs directly as well — see [Usage](#usage).

## Quick start

Run it with no flags to open the interactive dashboard:

```bash
bash linux/syncode.sh            # Linux
```

```powershell
.\windows\syncode.ps1            # Windows
```

What happens next:

1. syncode **detects** your editors (VS Code, VSCodium).
2. It shows you a **plan** — what's installed, what's out of date, what's out
   of sync.
3. If more than one editor is found, you **pick** which ones to apply to
   (numbers toggle, `a` = all, `n` = none, Enter = apply).
4. It **asks for confirmation** before changing anything.
5. It **applies**: copies settings (backing up the old ones to
   `settings.json.bak` first) and installs only the *missing* extensions.

**Not sure yet?** `-d` shows the full plan and changes nothing — safe to run
anywhere:

```bash
bash linux/syncode.sh -d         # Linux: preview the plan
```

```powershell
.\windows\syncode.ps1 -d         # Windows: preview the plan
```

## Options

| Flag | Long form (bash) | What it does |
| --- | --- | --- |
| `-h` | `--help` | Show help and exit |
| `-v` | `--version` | Show version and exit |
| `-d` | `--dry-run` | Show the plan, change nothing |
| `-r` | `--revert` | Restore editors to factory defaults |
| `-i` | `--install [fork]` | Install the latest stable editor (all forks by default) |
| `-u` | `--uninstall [fork]` | Remove an editor and its config dir |
| `-l` | `--list-versions` | Show installed vs latest versions, then exit |

> **Windows note:** PowerShell is case-insensitive, so `-l` (lowercase L) is
> the list-versions flag and `-v` is version; the long forms
> `-Help`, `-ListVersions`, etc. also work there.

`[fork]` is `code` (VS Code) or `codium` (VSCodium). Bare `-i` / `-u` applies
to every detected fork; `-i codium` targets just VSCodium.

### Examples

```bash
bash linux/syncode.sh            # interactive dashboard (no flags)
bash linux/syncode.sh -d         # preview the plan, change nothing
bash linux/syncode.sh -r         # restore editors to factory defaults
bash linux/syncode.sh -l         # show installed vs latest versions
bash linux/syncode.sh -i         # install latest stable for all editors
bash linux/syncode.sh -i codium  # install just VSCodium
bash linux/syncode.sh -u         # uninstall all editors + config dirs
```

```powershell
.\windows\syncode.ps1            # interactive dashboard (no flags)
.\windows\syncode.ps1 -d         # preview the plan, change nothing
.\windows\syncode.ps1 -r         # restore editors to factory defaults
.\windows\syncode.ps1 -l         # show installed vs latest versions
.\windows\syncode.ps1 -i         # install latest stable for all editors
.\windows\syncode.ps1 -i codium  # install just VSCodium
.\windows\syncode.ps1 -u         # uninstall all editors + config dirs
```

## The interactive dashboard

Run with no flags for a live dashboard. Every pick repaints the screen
(banner, status table, menu); the last result stays visible as a notice line:

```
  +--------+-----------+-------------+----------+------------+
  | Name   | Installed | Latest      | Settings | Extensions |
  +--------+-----------+-------------+----------+------------+
  | code   | 1.132.0   | 1.133.0     | synced   | 2 missing  |
  | codium | 1.126.0   | 1.126.04524 | diverged | 1 missing  |
  +--------+-----------+-------------+----------+------------+

  Pick an option:

  1. Visual Studio Code
  2. VSCodium
  3. Quit

  Enter an option: 1

  Pick an option for Visual Studio Code:

  1. Install
  2. Config
  3. Reset
  4. Uninstall
  5. Menu
  6. Quit

  Enter an option: 2

  Pick an option for Visual Studio Code:

  1. Settings
  2. Extensions
  3. Menu
  4. Quit

  Enter an option: 2

  Visual Studio Code extensions
  Pick an option:

  1. [x] ms-python.python
  2. [ ] esbenp.prettier-vscode
  3. [ ] bradlc.vscode-tailwindcss
  a. All  n. None  i. Install selected  u. Uninstall selected
  m. Menu  q. Quit

  Enter an option:
```

- The status table reads per editor: **Installed** and **Latest** versions
  (fetched live, cached per session), **Settings** sync state, and the
  **Extensions** count of what's missing. Columns grow to fit; the header is
  bold on a terminal.
- **Config** (only offered when the editor is installed) splits into
  **Settings** — copy the shared settings file, backing up to `.bak` — and
  **Extensions** — the multiselect picker above.
- **Reset** and **Uninstall** are destructive; syncode asks you to type the
  word to confirm.
- `Menu` returns to the editor list; `Quit` (or `q`) exits. Invalid input
  just re-prompts.

When the output isn't a terminal (piped, CI), the screen-clear is skipped and
frames stack so transcripts stay readable.

## Managing editors

### Check versions (`-l`)

Shows installed vs latest for every fork, then exits.

```bash
bash linux/syncode.sh -l
```

```powershell
.\windows\syncode.ps1 -l
```

### Install an editor (`-i`)

Downloads and installs the latest stable release (VS Code or VSCodium) —
needed if you only have one of the two.

```bash
bash linux/syncode.sh -i codium   # install just VSCodium
```

```powershell
.\windows\syncode.ps1 -i codium   # install just VSCodium
```

### Uninstall an editor (`-u`)

Removes the editor binary *and* its config directory. Windows installs run
`/VERYSILENT /NORESTART /mergetasks=!runcode` so the editor never launches on
its own.

```bash
bash linux/syncode.sh -u code
```

```powershell
.\windows\syncode.ps1 -u code
```

### Revert to factory defaults (`-r`)

For each selected editor:

1. Restores `settings.json.bak` → `settings.json` if a backup exists,
   otherwise deletes `settings.json` (back to built-in defaults).
2. Uninstalls every extension listed in `extensions.json` (only the ones
   syncode manages — never yours).

```bash
bash linux/syncode.sh -r        # interactive selection, then confirm
bash linux/syncode.sh -r -d     # plan for all editor families, apply nothing
```

```powershell
.\windows\syncode.ps1 -r        # interactive selection, then confirm
.\windows\syncode.ps1 -r -d     # plan for all editor families, apply nothing
```

## How it works

Flow: **detect → plan → select → confirm → apply.**

1. **Detect** — checks for `code`, `codium` on PATH or by config directory
   (in parallel).
2. **Plan** — prints a name / version / status table, marking what's not
   installed.
3. **Select** — a toggle menu when multiple editors are found.
4. **Confirm** — asks for confirmation (`Y/n`, defaults to yes).
5. **Apply** — per editor: copy settings (backing up to `.bak` first), then
   install only *missing* extensions.

### Idempotent & safe

- Running it twice is a no-op — anything already in sync is skipped.
- Previous settings are always preserved in `settings.json.bak` before an
  overwrite.
- Extensions you install on top of syncode's list are left alone.
- Every subprocess that could eat your keystrokes runs with stdin closed, so
  interactive prompts are never swallowed.

## Project layout

```
install.sh        one-time runner (root — curl-fetches tool + configs)
install.ps1       one-time runner (root — irm/Invoke-WebRequest fetches + runs)
linux/            syncode.sh + version.sh + release.sh — Linux (bash 4+)
windows/          syncode.ps1 + version.ps1 + release.ps1 — Windows (PowerShell)
shared/           settings.json + extensions.json + releases.json + extensions.md
                  (configs live in shared/; scripts find them via ../shared in a
                  checkout, or beside the script in the install temp dir)
```

`releases.json` maps each editor fork to its release API, installer URLs,
uninstall method, and winget id — it powers `-i/-u/-l` and the dashboard's
latest column. Version comparison lives in `version.sh`/`version.ps1`;
release lookups in `release.sh`/`release.ps1`. Each module self-checks when
run directly (e.g. `bash linux/release.sh`).

## Requirements & notes

- **Linux** needs bash 4+ and curl. **Windows** needs PowerShell 5.1+
  (no curl).
- Extensions are installed from the marketplace your editor uses (e.g.
  Open VSX for VSCodium). Proprietary extensions like GitHub Copilot that
  have no marketplace equivalent will fail to install — syncode reports the
  failure and continues.
- Fonts, terminal default profiles, and other machine-specific settings
  aren't portable across OSes — keep them out of `settings.json` or expect
  to adjust per machine.
