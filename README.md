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

> Sync and manage your VSCode and VSCodium editors.

**syncode** keeps your VS Code-style editors in sync from one command. It
detects which editors you have, copies your settings in, and installs your
extensions — so a fresh machine ends up with the same editor setup.

- **New machine?** Run it once and your editors are configured.
- **Changed something?** Run it again — it only fills in what's missing.
- **Everything lives in one interactive dashboard** — no flags, no options to
  memorize. Pick an editor, pick an action.

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

Prefer cloning? The repo runs directly as well — see [Usage](#usage).

## Quick start

Run it to open the interactive dashboard:

```bash
bash linux/syncode.sh            # Linux
```

```powershell
.\windows\syncode.ps1            # Windows
```

What happens next:

1. The dashboard shows a **status table** — what's installed, what's out of
   date, what's in sync, what extensions are missing.
2. You **pick an editor** (VSCode or VSCodium).
3. You **pick an action**: Install (with an installer-variant picker on
   Windows), Config (settings / extensions), Reset, or Uninstall.
4. Destructive actions (**Reset**, **Uninstall**) ask you to type the word to
   confirm. Settings are backed up to `settings.json.bak` before overwrite.

There are no flags. If you ever need help, `Menu` and `Quit` are at the
bottom of every menu, and invalid input just re-prompts.

## The interactive dashboard

Every pick repaints the screen (banner, status table, menu); the last result
stays visible as a notice line:

```
  +----------+-----------+-------------+----------+------------+
  | Name     | Installed | Latest      | Settings | Extensions |
  +----------+-----------+-------------+----------+------------+
  | VSCode   | 1.132.0   | 1.133.0     | synced   | 2 missing  |
  | VSCodium | 1.126.0   | 1.126.04524 | diverged | 1 missing  |
  +----------+-----------+-------------+----------+------------+

  Pick an editor:

  1. VSCode
  2. VSCodium
  3. Quit

  Enter an option: 1

  Pick an option for VSCode:

  1. Install
  2. Config
  3. Reset
  4. Uninstall
  5. Menu
  6. Quit

  Enter an option: 2

  Pick a config for VSCode:

  1. Settings
  2. Extensions
  3. Menu
  4. Quit

  Enter an option: 2

  Pick extensions for VSCode:

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
- **Install** downloads the latest stable release. On Windows you first pick
  an installer variant (User / System / MSI).
- **Reset** and **Uninstall** are destructive; syncode asks you to type the
  word to confirm.
- `Menu` returns to the editor list; `Quit` (or `q`) exits. Invalid input
  just re-prompts.

When the output isn't a terminal (piped, CI), the screen-clear is skipped and
frames stack so transcripts stay readable.

## Managing editors

Everything runs from the dashboard — install, config, reset, and uninstall
are actions on the per-editor menu.

### Check versions

The dashboard's status table shows installed vs latest for every editor —
no separate command needed.

### Install an editor

Pick the editor from the dashboard, then `Install`. On Windows you'll pick
an installer variant (User / System / MSI for VSCodium); Linux installs via
your package manager (apt, dnf/yum, or a tarball).

### Uninstall an editor

Pick the editor, then `Uninstall` — type `uninstall` to confirm. Removes the
editor binary *and* its config directory. Windows installs run
`/VERYSILENT /NORESTART /mergetasks=!runcode` so the editor never launches on
its own.

### Reset to factory defaults

Pick the editor, then `Reset` — type `reset` to confirm. Per editor:

1. Restores `settings.json.bak` → `settings.json` if a backup exists,
   otherwise deletes `settings.json` (back to built-in defaults).
2. Uninstalls every extension listed in `extensions.json` (only the ones
   syncode manages — never yours).

## How it works

The tool is an interactive **repaint loop**: detect → render → pick → act.

1. **Render** — the status table reads installed/latest versions, settings
   sync state, and missing-extension counts for both editor forks (detection
   runs in parallel).
2. **Pick** — an editor, then an action: install, config, reset, uninstall.
3. **Act** — settings are copied (backed up to `.bak` first), only *missing*
   extensions are installed, and the result appears as a notice line on the
   repainted frame.

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
uninstall method, and winget id — it powers the dashboard's install/uninstall
and latest column. Version comparison lives in `version.sh`/`version.ps1`;
release lookups in `release.sh`/`release.ps1`. Each module self-checks when
run directly (e.g. `bash linux/release.sh`).

## Requirements & notes

- **Linux** needs bash 4+ and curl. **Windows** needs PowerShell 5.1+
  (no curl).
- The dashboard is interactive — it needs a terminal (stdin + stdout).
- Extensions are installed from the marketplace your editor uses (e.g.
  Open VSX for VSCodium). Proprietary extensions like GitHub Copilot that
  have no marketplace equivalent will fail to install — syncode reports the
  failure and continues.
- Fonts, terminal default profiles, and other machine-specific settings
  aren't portable across OSes — keep them out of `settings.json` or expect
  to adjust per machine.
