# ============================================================
#  syncode.ps1 - sync your editor setup to every VS Code-family
#  editor. Windows / PowerShell version (Windows only).
#  Version: 1.1.0
# ============================================================
param(
    [Alias('h')][switch]$Help,
    [Alias('v')][switch]$Version,
    [Alias('d')][switch]$DryRun,
    [Alias('r')][switch]$Revert,
    [Alias('i')][switch]$Install,
    [Alias('u')][switch]$Update,
    [Alias('rm')][switch]$Uninstall,
    [Alias('l')][switch]$ListVersions,
    # optional fork name after -i/-u/-rm, e.g. "-i codium" (bare -i = all forks)
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = "Stop"

$VERSION_STR = "1.1.0"
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
    -i, --install [fork]    install latest stable (code/codium; default all)
    -u, --update [fork]     upgrade if installed version is older than latest
    -rm, --uninstall [fork] remove editor and its config dir
    -l, --list-versions     show installed vs latest versions, then exit

WHAT IT DOES:
    Detects installed editors (VS Code, VSCodium),
    then for each: backs up settings.json, copies the repo settings, and
    installs missing extensions. Shows a toggle menu when multiple editors
    are detected. With no flags, opens the interactive dashboard
    (pick editor, then install/update/config/reset/uninstall/help).

EXAMPLES:
    .\$SCRIPT_NAME           apply to selected editors (menu)
    .\$SCRIPT_NAME           interactive dashboard (no flags)
    .\$SCRIPT_NAME -d        preview the plan, change nothing
    .\$SCRIPT_NAME -r        restore editors to factory defaults
    .\$SCRIPT_NAME -l        show installed vs latest versions
    .\$SCRIPT_NAME -i codium install latest VSCodium
    .\$SCRIPT_NAME -u        update all editors
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
}
$FORK_ORDER = @("code", "codium")

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
    # $null | closes stdin on the native CLI so it can't eat interactive input;
    # .Trim() strips the trailing CR from Windows CRLF output
    @($null | & $cli.Source --list-extensions 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-EditorVersion($fork) {
    $cli = Get-Command -Name $fork -ErrorAction SilentlyContinue
    if (-not $cli) { return "n/a" }
    $v = $null | & $cli.Source --version 2>$null | Select-Object -First 1
    if ($v) { return $v.Trim() } else { return "n/a" }
}

function Get-MissingExts($fork) {
    $have = @(Get-InstalledExts $fork)
    @(Get-ExtIds) | Where-Object { $have -notcontains $_ }
}

function Test-SameSettings($a, $b) {
    if (-not (Test-Path $a) -or -not (Test-Path $b)) { return $false }
    return (Get-FileHash $a).Hash -eq (Get-FileHash $b).Hash
}

# Prompt reader. [Console]::In.ReadLine() (not Read-Host) so piped/redirected
# stdin works too; returns $null on EOF (matches bash "read || ans=n").
function Read-Line($prompt) {
    Write-Host -NoNewline $prompt
    return [Console]::In.ReadLine()
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
                    $null | & $cli.Source --uninstall-extension $id 2>$null | Out-Null
                    Write-Output "    ${fork}: uninstalled $id"
                }
            }
        } else {
            foreach ($id in @(Get-MissingExts $fork)) {
                $null | & $cli.Source --install-extension $id --force 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-Output "    ${fork}: installed $id" }
                else                     { Write-LogWarn "${fork}: FAILED to install $id" }
            }
        }
    } else {
        Write-Output "    ${fork}: no CLI found - settings handled, extensions skipped"
    }
}

# ------------------------------------------------------------
#  Release-driven actions (install/update/uninstall) + dashboard
# ------------------------------------------------------------
. (Join-Path $PSScriptRoot "version.ps1")
. (Join-Path $PSScriptRoot "release.ps1")

$script:LatestCache = @{}

# Get-LatestCached <fork> — latest version (or "unknown"), cached per session.
function Get-LatestCached($fork) {
    if ($script:LatestCache.ContainsKey($fork)) { return $script:LatestCache[$fork] }
    $v = "unknown"
    try { $v = Get-LatestVersion $fork } catch { $v = "unknown" }
    $script:LatestCache[$fork] = $v
    return $v
}
function Reset-LatestCache($fork) { $script:LatestCache.Remove($fork) | Out-Null }

# Resolve-Cli <fork> — PATH first, else known install-path binary
# (closes the fresh-install dead-end: install → config in the same session).
function Resolve-Cli($fork) {
    $cli = Get-Command -Name $fork -ErrorAction SilentlyContinue
    if ($cli) { return $cli.Source }
    $p = ""
    switch ($fork) {
        "code"   { $p = Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin\code.cmd" }
        "codium" { $p = Join-Path $env:LOCALAPPDATA "Programs\VSCodium\bin\codium.cmd" }
    }
    if (Test-Path $p) { return $p }
    return ""
}

# Show-ListVersions — -l / --list-versions table
function Show-ListVersions {
    "{0,-10} {1,-12} {2}" -f "name", "installed", "latest"
    foreach ($f in $FORK_ORDER) {
        $inst = Get-InstalledVersion $f
        if (-not $inst) { $inst = "—" }
        "{0,-10} {1,-12} {2}" -f $f, $inst, (Get-LatestCached $f)
    }
}

# Show-Dashboard — one row per fork: name / installed / latest / settings / extensions
function Show-Dashboard {
    "{0,-8} {1,-12} {2,-12} {3,-9} {4}" -f "name", "installed", "latest", "settings", "extensions"
    foreach ($f in $FORK_ORDER) {
        $inst = Get-InstalledVersion $f
        if (-not $inst) { $inst = "—" }
        $latest = Get-LatestCached $f
        $sp = Get-SettingsPath $f
        if (Test-Path $sp) {
            if (Test-SameSettings $sp (Join-Path $CONFIG_DIR "settings.json")) {
                $settings = "✓ synced"
            } else {
                $settings = "diverged"
            }
        } else {
            $settings = "—"
        }
        $cli = Resolve-Cli $f
        if ($cli) {
            $missing = @(Get-MissingExts $f)
            $ext = if ($missing.Count -eq 0) { "up to date" } else { "$($missing.Count) missing" }
        } else {
            $ext = "n/a"
        }
        "{0,-8} {1,-12} {2,-12} {3,-9} {4}" -f $f, $inst, $latest, $settings, $ext
    }
}

# Install-Editor <fork> — download (syncode temp name) + silent install
# (/VERYSILENT /NORESTART /mergetasks=!runcode so the editor doesn't relaunch).
# "already installed" check lives at the call sites; update calls straight
# through so the Inno installer can upgrade in place.
function Install-Editor($fork) {
    $ver = Get-LatestCached $fork
    if ($ver -eq "unknown") { throw "${fork}: can't determine latest version" }
    $url = Get-ReleaseUrl $fork "win" $ver
    $tmp = Join-Path $env:TEMP ("syncode-{0}-{1}.exe" -f $fork, [guid]::NewGuid().ToString("N"))
    Write-Output "  ${fork}: downloading $ver ..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp -TimeoutSec 600
    } catch {
        Remove-Item -Force $tmp -ErrorAction SilentlyContinue
        throw "${fork}: download failed ($($_.Exception.Message))"
    }
    $p = Start-Process -FilePath $tmp -ArgumentList "/VERYSILENT", "/NORESTART", "/mergetasks=!runcode" -Wait -PassThru
    Remove-Item -Force $tmp
    if ($p.ExitCode -ne 0) { throw "${fork}: installer failed (exit $($p.ExitCode))" }
    Write-Output "  $fork installed"
}

# Update-Editor <fork> — upgrade if installed < latest; no-op if current.
# Failures throw (flag mode → exit 1; dashboard → caught, loop continues).
function Update-Editor($fork) {
    $inst = Get-InstalledVersion $fork
    $latest = Get-LatestCached $fork
    if (-not $inst) { Write-Output "  $fork not installed — use install"; return }
    if ($latest -eq "unknown") {
        if ($script:RateLimited) { throw "${fork}: GitHub API rate limit hit — try later" }
        else                     { throw "${fork}: can't check for updates (network unavailable)" }
    }
    if ((Compare-Version $inst $latest) -lt 0) {
        Write-Output "  ${fork}: updating $inst -> $latest"
        Install-Editor $fork
    } else {
        Write-Output "  ${fork}: already latest ($inst)"
    }
}

# Uninstall-Editor <fork> — unins000.exe /VERYSILENT, winget fallback, config dir.
function Uninstall-Editor($fork) {
    $dir = Join-Path $env:LOCALAPPDATA "Programs\$($FORK_DIR[$fork])"
    $un = Join-Path $dir "unins000.exe"
    if (Test-Path $un) {
        Write-Output "  ${fork}: running unins000.exe ..."
        $p = Start-Process -FilePath $un -ArgumentList "/VERYSILENT", "/NORESTART" -Wait -PassThru
        if ($p.ExitCode -ne 0) { Write-LogWarn "${fork}: uninstaller exit $($p.ExitCode)" }
    } else {
        $id = Get-ReleaseWinget $fork
        Write-Output "  ${fork}: unins000.exe not found — winget fallback: $id"
        winget uninstall --id $id --silent --accept-source-agreements | Out-Null
    }
    Remove-Item -Recurse -Force (Join-Path $DATA_ROOT $FORK_DIR[$fork]) -ErrorAction SilentlyContinue
    Write-Output "  $fork removed"
}

# Run-Dashboard — interactive hub: pick editor, pick action, loop. q quits.
function Run-Dashboard {
    while ($true) {
        Write-Output ""
        Show-Dashboard
        Write-Output ""
        :editorpick while ($true) {
            $line = Read-Line "pick editor (1=code 2=codium, q=quit) "
            if ($null -eq $line) { Write-Output "bye."; exit 0 }
            $line = $line.Trim()
            switch ($line) {
                "q" { Write-Output "bye."; exit 0 }
                "Q" { Write-Output "bye."; exit 0 }
                "1" { $editor = "code"; break editorpick }
                "2" { $editor = "codium"; break editorpick }
                "code"   { $editor = "code"; break editorpick }
                "codium" { $editor = "codium"; break editorpick }
                default { Write-Output "invalid: $line" }
            }
        }
        $action = ""
        while ($true) {
            $line = Read-Line "action for $editor (install/update/config/reset/uninstall/help, q=quit) "
            if ($null -eq $line) { Write-Output "bye."; exit 0 }
            $action = $line.Trim()
            switch ($action) {
                "q" { Write-Output "bye."; exit 0 }
                "Q" { Write-Output "bye."; exit 0 }
                "install" { $ok = $true }
                "update"  { $ok = $true }
                "config"  { $ok = $true }
                "reset"   { $ok = $true }
                "uninstall" { $ok = $true }
                "help"    { $ok = $true }
                default   { Write-Output "invalid: $action"; $ok = $false }
            }
            if ($ok) { break }
        }
        switch ($action) {
            "help" {
                Write-Output "  install    install latest stable if not installed"
                Write-Output "  update     upgrade if installed version is older than latest"
                Write-Output "  config     copy settings (backup .bak) + install missing extensions"
                Write-Output '  reset      restore factory defaults  (type "reset" to confirm)'
                Write-Output '  uninstall  remove editor and its config dir  (type "uninstall" to confirm)'
            }
            "config" {
                try { Apply-Fork $editor }
                catch { Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red }
            }
            "reset" {
                $line = Read-Line 'Type "reset" to confirm: '
                if ($null -ne $line -and $line.Trim() -eq "reset") {
                    try {
                        $Revert = $true; Apply-Fork $editor; $Revert = $false
                    } catch {
                        $Revert = $false
                        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
                    }
                } else {
                    Write-Output "  not confirmed — skipped"
                }
            }
            "uninstall" {
                $line = Read-Line 'Type "uninstall" to confirm: '
                if ($null -ne $line -and $line.Trim() -eq "uninstall") {
                    try { Uninstall-Editor $editor }
                    catch { Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red }
                    Reset-LatestCache $editor
                } else {
                    Write-Output "  not confirmed — skipped"
                }
            }
            "install" {
                if (Get-InstalledVersion $editor) {
                    Write-Output "  $editor already installed"
                } else {
                    try { Install-Editor $editor }
                    catch { Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red }
                    Reset-LatestCache $editor
                }
            }
            "update" {
                try { Update-Editor $editor }
                catch { Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red }
            }
        }
    }
}

# Resolve-ActionForks <arg> — empty = all forks, else one fork (code|codium).
function Resolve-ActionForks($arg) {
    if (-not $arg) { return @($FORK_ORDER) }
    switch ($arg) {
        "code"   { return @("code") }
        "codium" { return @("codium") }
        default  { Write-Host "[ERROR] unknown fork: $arg" -ForegroundColor Red; exit 1 }
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

# action flags take priority (list-versions / install / update / uninstall)
$action = ""
$actionForks = @()
$forkArg = if ($Rest.Count -gt 0) { $Rest -join " " } else { "" }
if ($Install) { $action = "install"; $actionForks = Resolve-ActionForks $forkArg }
if ($Update) {
    if ($action) { Write-Host "[ERROR] conflicting actions: only one of -i/-u/-rm allowed" -ForegroundColor Red; exit 1 }
    $action = "update"; $actionForks = Resolve-ActionForks $forkArg
}
if ($Uninstall) {
    if ($action) { Write-Host "[ERROR] conflicting actions: only one of -i/-u/-rm allowed" -ForegroundColor Red; exit 1 }
    $action = "uninstall"; $actionForks = Resolve-ActionForks $forkArg
}
if ($ListVersions) {
    if ($action) { Write-Host "[ERROR] conflicting actions: only one of -i/-u/-rm allowed" -ForegroundColor Red; exit 1 }
    $action = "list-versions"; $actionForks = @()
}

if ($action) {
    if ($action -eq "list-versions") {
        Show-ListVersions
        exit 0
    }
    if ($DryRun) {
        "{0,-10} {1,-12} {2,-12} {3}" -f "name", "installed", "latest", "action"
        foreach ($f in $actionForks) {
            $inst = Get-InstalledVersion $f
            if (-not $inst) { $inst = "none" }
            $latest = Get-LatestCached $f
            $desc = switch ($action) {
                "install"   { "install $latest" }
                "update"    { if ($inst -eq "none") { "not installed (install first)" } else { "update to $latest" } }
                "uninstall" { "remove editor + config" }
            }
            "{0,-10} {1,-12} {2,-12} {3}" -f $f, $inst, $latest, $desc
        }
        Write-Output "DRY RUN — nothing applied."
        exit 0
    }
    Write-Output ""
    $line = Read-Line "Apply? [Y/n] "
    $ans = if ($null -eq $line) { "n" } else { $line.Trim() }
    if ($ans -match "^n") { Write-Output "aborted."; exit 0 }
    Write-Output ""
    try {
        foreach ($f in $actionForks) {
            Write-Output "${f}:"
            switch ($action) {
                "install" {
                    if (Get-InstalledVersion $f) { Write-Output "  $f already installed" }
                    else { Install-Editor $f }
                }
                "update"    { Update-Editor $f }
                "uninstall" { Uninstall-Editor $f }
            }
            Write-Output ""
        }
    } catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    exit 0
}

# no flags → interactive dashboard
if (-not $Revert -and -not $DryRun) {
    Run-Dashboard
    exit 0
}

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
        $line = Read-Line "toggle (e.g. 1 3), a=all, n=none, enter=apply "
        $choice = if ($null -eq $line) { "" } else { $line.Trim() }

        switch ($choice) {
            ""  { break menu }
            "a" { foreach ($f in $detected) { $checked[$f] = $true } }
            "A" { foreach ($f in $detected) { $checked[$f] = $true } }
            "n" { foreach ($f in $detected) { $checked[$f] = $false } }
            "N" { foreach ($f in $detected) { $checked[$f] = $false } }
            default {
                foreach ($tok in ($choice -split "\s+")) {
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
$line = Read-Line "Apply? [Y/n] "
$ans = if ($null -eq $line) { "n" } else { $line.Trim() }
if ($ans -match "^n") { Write-Output "aborted."; exit 0 }

Write-Output ""
foreach ($f in $selected) {
    Write-Output "${f}:"
    Apply-Fork $f
    Write-Output ""
}
Write-Output "done."
