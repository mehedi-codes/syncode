# ============================================================
#  syncode.ps1 - sync your editor setup to every VS Code-family
#  editor. Windows / PowerShell version (Windows only).
#  Version: 1.0.0
# ============================================================
param(
    [Alias('h')][switch]$Help,
    [Alias('v')][switch]$Version,
    [Alias('d')][switch]$DryRun,
    [Alias('r')][switch]$Revert
)

$ErrorActionPreference = "Stop"

$VERSION_STR = "1.0.0"
$TOOL_NAME = "syncode"
$DESCRIPTION = "sync your editor setup to every VS Code-family editor"

$BANNER = @'
:'######:'##:::'##'##::: ##:'######:'#######:'########:'########:
'##... ##. ##:'##::###:: ##'##... ##'##.... ##:##.... ##:##.....::
 ##:::..::. ####:::####: ##:##:::..::##:::: ##:##:::: ##:##:::::::
. ######:::. ##::::## ## ##:##:::::::##:::: ##:##:::: ##:######:::
:..... ##::: ##::::##. ####:##:::::::##:::: ##:##:::: ##:##...::::
'##::: ##::: ##::::##:. ###:##::: ##:##:::: ##:##:::: ##:##:::::::
. ######:::: ##::::##::. ##. ######:. #######::########::########:
:......:::::..::::..::::..::......:::.......::........::........::
'@

# Script directory (install.ps1 runs this from a temp dir with the configs beside it)
$SCRIPT_DIR = $PSScriptRoot

# Config dir: beside the script (install temp dir) or ..\shared (repo checkout)
if ((Test-Path (Join-Path $SCRIPT_DIR "settings.json")) -and (Test-Path (Join-Path $SCRIPT_DIR "extensions.json"))) {
    $CONFIG_DIR = $SCRIPT_DIR
} else {
    $CONFIG_DIR = Join-Path $SCRIPT_DIR "..\shared"
}

function Write-LogInfo  { Write-Host "[INFO ] $args" }
function Write-LogWarn  { Write-Warning $args }
function Write-LogError { Write-Error $args }

function Show-Usage {
    Write-Output @"

$BANNER

$TOOL_NAME v$VERSION_STR - $DESCRIPTION

USAGE:
    .\$SCRIPT_NAME [OPTIONS]

OPTIONS:
    -h, --help      show this help and exit
    -v, --version   show version and exit
    -d, --dry-run   show the plan, change nothing
    -r, --revert    restore editors to factory defaults:
                    settings.json.bak -> settings.json if it exists,
                    else delete settings.json; uninstall $TOOL_NAME-installed
                    extensions. With -d: applies to all detected editors;
                    without -d: interactive selection like apply.

WHAT IT DOES:
    Detects installed editors (VS Code, VSCodium, Cursor, Windsurf, Positron),
    then for each: backs up settings.json, copies the repo settings, and
    installs missing extensions. Shows a toggle menu when multiple editors
    are detected.

EXAMPLES:
    .\$SCRIPT_NAME           apply to selected editors (menu)
    .\$SCRIPT_NAME -d        preview the plan, change nothing
    .\$SCRIPT_NAME -r        restore editors to factory defaults
"@
    exit 0
}

if ($Help)    { Show-Usage }
if ($Version) { Write-Output "$TOOL_NAME v$VERSION_STR"; exit 0 }

# ------------------------------------------------------------
#  OS / platform (Windows only: APPDATA is the config root)
# ------------------------------------------------------------
$DATA_ROOT = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $HOME "AppData\Roaming" }

$FORK_DIR = @{
    code      = "Code"
    codium    = "VSCodium"
    cursor    = "Cursor"
    windsurf  = "Windsurf"
    positron  = "Positron"
}
$FORK_ORDER = @("code", "codium", "cursor", "windsurf", "positron")

function Get-SettingsPath($fork) { Join-Path $DATA_ROOT "$($FORK_DIR[$fork])\User\settings.json" }
function Get-BackupPath($fork)   { Join-Path $DATA_ROOT "$($FORK_DIR[$fork])\User\settings.json.bak" }

# ------------------------------------------------------------
#  Detection
# ------------------------------------------------------------
function Test-Fork($fork) {
    if (Get-Command -Name $fork -ErrorAction SilentlyContinue) { return $true }
    if (Test-Path (Join-Path $DATA_ROOT "$($FORK_DIR[$fork])\User")) { return $true }
    return $false
}

# ------------------------------------------------------------
#  Extension helpers
# ------------------------------------------------------------
function Get-ExtIds {
    # extract "publisher.name" entries from extensions.json (regex, like the bash version)
    $text = [IO.File]::ReadAllText((Join-Path $CONFIG_DIR "extensions.json"), [Text.Encoding]::UTF8)
    @([regex]::Matches($text, '"[a-z0-9-]+\.[a-z0-9-]+"')) | ForEach-Object { $_.Value.Trim('"') }
}

function Get-InstalledExts($fork) {
    $cli = Get-Command -Name $fork -ErrorAction SilentlyContinue
    if (-not $cli) { return @() }
    @(& $cli.Source --list-extensions 2>$null | Where-Object { $_ })
}

function Get-EditorVersion($fork) {
    $cli = Get-Command -Name $fork -ErrorAction SilentlyContinue
    if (-not $cli) { return "n/a" }
    $v = & $cli.Source --version 2>$null | Select-Object -First 1
    if ($v) { return $v } else { return "n/a" }
}

function Get-MissingExts($fork) {
    $have = @(Get-InstalledExts $fork)
    @(Get-ExtIds) | Where-Object { $have -notcontains $_ }
}

function Test-SameSettings($a, $b) {
    if (-not (Test-Path $a) -or -not (Test-Path $b)) { return $false }
    return (Get-FileHash $a).Hash -eq (Get-FileHash $b).Hash
}

# ------------------------------------------------------------
#  Plan / apply
# ------------------------------------------------------------
function Get-Plan($fork) {
    $sp = Get-SettingsPath $fork
    $bd = Get-BackupPath $fork
    $settingsSrc = Join-Path $CONFIG_DIR "settings.json"

    if ($Revert) {
        if (Test-Path $bd) { $out = "restore settings.json from .bak" }
        else               { $out = "delete settings.json (factory defaults)" }
        $out += ", uninstall $TOOL_NAME extensions"
    } else {
        if ((Test-Path $sp) -and (Test-SameSettings $sp $settingsSrc)) {
            $out = "settings already in sync"
        } else {
            $out = "copy settings (backup -> .bak)"
            if (Test-Path $bd) { $out += " (overwrite .bak)" }
        }
        $cli = Get-Command -Name $fork -ErrorAction SilentlyContinue
        if ($cli) {
            $missing = @(Get-MissingExts $fork)
            if ($missing.Count -gt 0) { $out += ", install missing extensions: $($missing -join ' ')" }
            else                      { $out += ", extensions up to date" }
        } else {
            $out += ", no CLI found - extensions skipped"
        }
    }
    return $out
}

function Apply-Fork($fork) {
    $sp = Get-SettingsPath $fork
    $bd = Get-BackupPath $fork
    $settingsSrc = Join-Path $CONFIG_DIR "settings.json"

    New-Item -ItemType Directory -Force -Path (Split-Path $sp) | Out-Null

    if ($Revert) {
        if (Test-Path $bd) {
            Move-Item -Force $bd $sp
            Write-Output "    ${fork}: restored settings.json from .bak"
        } elseif (Test-Path $sp) {
            Remove-Item -Force $sp
            Write-Output "    ${fork}: deleted settings.json (factory defaults)"
        } else {
            Write-Output "    ${fork}: no settings.json to revert"
        }
    } else {
        if ((Test-Path $sp) -and (Test-SameSettings $sp $settingsSrc)) {
            Write-Output "    ${fork}: settings already in sync"
        } else {
            if (Test-Path $sp) { Copy-Item -Force $sp $bd }
            Copy-Item -Force $settingsSrc $sp
            Write-Output "    ${fork}: settings copied (backup -> .bak)"
        }
    }

    # extensions: install missing / uninstall syncode-installed
    $cli = Get-Command -Name $fork -ErrorAction SilentlyContinue
    if ($cli) {
        if ($Revert) {
            foreach ($id in @(Get-ExtIds)) {
                if (@(Get-InstalledExts $fork) -contains $id) {
                    & $cli.Source --uninstall-extension $id 2>$null | Out-Null
                    Write-Output "    ${fork}: uninstalled $id"
                }
            }
        } else {
            foreach ($id in @(Get-MissingExts $fork)) {
                & $cli.Source --install-extension $id --force 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-Output "    ${fork}: installed $id" }
                else                     { Write-LogWarn "${fork}: FAILED to install $id" }
            }
        }
    } else {
        Write-Output "    ${fork}: no CLI found - settings handled, extensions skipped"
    }
}

# ------------------------------------------------------------
#  Main
# ------------------------------------------------------------
Write-Output ""
Write-Output $BANNER
Write-Output ""
Write-Output "$TOOL_NAME v$VERSION_STR - $DESCRIPTION"
Write-Output ""

$detected = @()
foreach ($fork in $FORK_ORDER) {
    if (Test-Fork $fork) { $detected += $fork }
}

Write-Output "Plan:"
if ($Revert) { Write-Output "  mode: revert to factory defaults" }
"{0,-10} {1,-12} {2}" -f "name", "version", "status"
"{0,-10} {1,-12} {2}" -f "----", "-------", "------"
foreach ($f in $FORK_ORDER) {
    if ($detected -contains $f) {
        "{0,-10} {1,-12} {2}" -f $f, (Get-EditorVersion $f), (Get-Plan $f)
    } else {
        "{0,-10} {1,-12} {2}" -f $f, "n/a", "not installed"
    }
}
Write-Output ""

# selection (menu only when not dry-run and more than one fork)
$selected = @($detected)
if (-not $DryRun -and $detected.Count -gt 1) {
    $checked = @{}
    foreach ($f in $detected) { $checked[$f] = $true }

    :menu while ($true) {
        Write-Output "Detected editors:"
        for ($i = 0; $i -lt $detected.Count; $i++) {
            $mark = " "
            if ($checked[$detected[$i]]) { $mark = "x" }
            "  {0}) [{1}] {2}" -f ($i + 1), $mark, $detected[$i]
        }
        Write-Output "  a) select all     n) select none     <enter> = apply checked"
        $input = (Read-Host "toggle (e.g. 1 3), a=all, n=none, enter=apply").Trim()

        switch ($input) {
            ""  { break menu }
            "a" { foreach ($f in $detected) { $checked[$f] = $true } }
            "A" { foreach ($f in $detected) { $checked[$f] = $true } }
            "n" { foreach ($f in $detected) { $checked[$f] = $false } }
            "N" { foreach ($f in $detected) { $checked[$f] = $false } }
            default {
                foreach ($tok in ($input -split "\s+")) {
                    if ($tok -match "^\d+$") {
                        $num = [int]$tok
                        if ($num -ge 1 -and $num -le $detected.Count) {
                            $f = $detected[$num - 1]
                            $checked[$f] = -not $checked[$f]
                        } else {
                            Write-Output "  invalid: $num"
                        }
                    } else {
                        Write-Output "  invalid: $tok"
                    }
                }
            }
        }
    }

    $selected = @()
    foreach ($f in $detected) { if ($checked[$f]) { $selected += $f } }
}

if ($DryRun) {
    Write-Output "DRY RUN - nothing applied."
    exit 0
}

if ($selected.Count -eq 0) {
    Write-Output "nothing to apply."
    exit 0
}

Write-Output ""
$ans = (Read-Host "Apply? [Y/n]").Trim()
if ($ans -match "^n") { Write-Output "aborted."; exit 0 }

Write-Output ""
foreach ($f in $selected) {
    Write-Output "${f}:"
    Apply-Fork $f
    Write-Output ""
}
Write-Output "done."
