# ============================================================
#  syncode.ps1 - Sync and manage your VS Code and VSCodium editors.
#  Windows / PowerShell version (Windows only).
#  Version: 1.3.0
# ============================================================
param(
    [Alias('h')][switch]$Help,
    [Alias('v')][switch]$Version,
    [Alias('d')][switch]$DryRun,
    [Alias('r')][switch]$Revert,
    [Alias('i')][switch]$Install,
    [Alias('u')][switch]$Uninstall,
    [Alias('l')][switch]$ListVersions,
    # optional fork name after -i/-u, e.g. "-i codium" (bare -i = all forks)
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = "Stop"

$VERSION_STR = "1.3.0"
$TOOL_NAME = "syncode"
$DESCRIPTION = "Sync and manage your VS Code and VSCodium editors"

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

# ------------------------------------------------------------
#  Progress/spinner renderers (download % + indeterminate spinners)
# ------------------------------------------------------------

# Best-effort VT processing: needed for ANSI colors on Windows PowerShell 5.1's
# conhost; pwsh 7 / Windows Terminal handle them natively. Redirected output
# (pipes, CI) falls back to plain text.
$script:CanAnsi = $false
if (-not [Console]::IsOutputRedirected) {
    try {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $script:CanAnsi = $true
        } elseif ($Host.Name -eq "ConsoleHost") {
            Add-Type -Namespace Syncode -Name Vt -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern System.IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
'@
            $h = [Syncode.Vt]::GetStdHandle(-11)
            $mode = 0
            if ([Syncode.Vt]::GetConsoleMode($h, [ref]$mode)) {
                $script:CanAnsi = [Syncode.Vt]::SetConsoleMode($h, $mode -bor 0x4)
            }
        }
    } catch {
        $script:CanAnsi = $false
    }
}

# Write-ProgressLine <label> <name> <pct> <frame> - single \r line: spinner at
# start, a solid white background block behind the centered temp filename, real
# % at the end. pct -1 = indeterminate (spinner only, no box).
function Write-ProgressLine($label, $name, $pct, $frame) {
    $e = [char]27
    if (-not $script:CanAnsi) {
        if ($pct -lt 0) { [Console]::Write("`r$frame  $label") }
        else            { [Console]::Write("`r$frame  $label  $name  $pct%") }
        return
    }
    if ($pct -lt 0) {
        [Console]::Write("`r$frame  $label")
        return
    }
    $box = 44
    if ($name.Length -gt $box) { $name = $name.Substring($name.Length - $box) }
    $left = [int][Math]::Floor(($box - $name.Length) / 2)
    $right = $left + $name.Length
    $fill = [int][Math]::Floor($box * $pct / 100)
    if ($fill -gt $box) { $fill = $box }
    if ($fill -lt 0) { $fill = 0 }
    $W  = "$e[37m"; $K = "$e[30m"; $WB = "$e[47m"; $R = "$e[0m"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("`r$frame [$R")
    $pre = [Math]::Min($fill, $left)
    if ($pre -gt 0) { [void]$sb.Append($WB + $W + (" " * $pre) + $R) }
    $onFill = [Math]::Max(0, [Math]::Min($fill, $right) - $left)
    if ($onFill -gt 0) { [void]$sb.Append($WB + $K + $name.Substring(0, $onFill) + $R) }
    if ($name.Length -gt $onFill) { [void]$sb.Append($W + $name.Substring($onFill) + $R) }
    $after = $fill - $right
    if ($after -gt 0) { [void]$sb.Append($WB + $W + (" " * $after) + $R) }
    [void]$sb.Append("$R]  ${pct}%")
    [Console]::Write($sb.ToString())
}

# Get-Download <fork> <ver> <url> <tmp> - synchronous streaming download with a
# live progress line (real % from Content-Length; spinner-only if the server
# omits it). Throws on failure (temp file cleaned up).
function Get-Download($fork, $ver, $url, $tmp) {
    $frames = "|/-\"
    $i = 0
    $label = "  ${fork}: downloading"
    $name = Split-Path $tmp -Leaf
    $pct = -1
    try {
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.AllowAutoRedirect = $true
        $req.Timeout = 600000
        $req.ReadWriteTimeout = 600000
        $resp = $req.GetResponse()
        $total = [long]$resp.ContentLength
        $in = $resp.GetResponseStream()
        $out = [System.IO.File]::Create($tmp)
        $buf = New-Object byte[] 65536
        $done = 0L
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $out.Write($buf, 0, $n)
            $done += $n
            if ($sw.ElapsedMilliseconds -ge 100) {
                if ($total -gt 0) { $pct = [int](($done * 100) / $total) }
                Write-ProgressLine $label $name $pct $frames[$i % 4]
                $i++
                $sw.Restart()
            }
        }
        $out.Close(); $in.Close(); $resp.Close()
    } catch {
        Remove-Item -Force $tmp -ErrorAction SilentlyContinue
        throw "${fork}: download failed ($($_.Exception.Message))"
    }
    if ($pct -lt 0) { $pct = 0 }
    Write-ProgressLine $label $name $pct " "
    Write-Output ""
}

# Wait-ProcessSpinner <label> <proc> - spinner while an installer/uninstaller
# runs (no % available for silent installers; editors self-update).
function Wait-ProcessSpinner($label, $p) {
    $frames = "|/-\"
    $i = 0
    while (-not $p.HasExited) {
        Write-ProgressLine $label "" -1 $frames[$i % 4]
        $i++
        Start-Sleep -Milliseconds 120
    }
    Write-ProgressLine $label "" -1 " "
    Write-Output ""
}

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
    -u, --uninstall [fork] remove editor and its config dir
    -l, --list-versions     show installed vs latest versions, then exit

WHAT IT DOES:
    Detects installed editors (VS Code, VSCodium),
    then for each: backs up settings.json, copies the repo settings, and
    installs missing extensions. Shows a toggle menu when multiple editors
    are detected. With no flags, opens the interactive dashboard
    (pick editor, then install/config/reset/uninstall/help).

EXAMPLES:
    .\$SCRIPT_NAME           apply to selected editors (menu)
    .\$SCRIPT_NAME           interactive dashboard (no flags)
    .\$SCRIPT_NAME -d        preview the plan, change nothing
    .\$SCRIPT_NAME -r        restore editors to factory defaults
    .\$SCRIPT_NAME -l        show installed vs latest versions
    .\$SCRIPT_NAME -i codium install latest VSCodium
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
$FORK_FULL = @{
    code      = "Visual Studio Code"
    codium    = "VSCodium"
}

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

function Apply-Fork($fork, $Scope = "all") {
    $sp = Get-SettingsPath $fork
    $bd = Get-BackupPath $fork
    $settingsSrc = Join-Path $CONFIG_DIR "settings.json"

    New-Item -ItemType Directory -Force -Path (Split-Path $sp) | Out-Null

    if ($Scope -in @("all", "settings")) {
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
    }

    if ($Scope -in @("all", "extensions")) {
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
            if ($Scope -eq "all") { Write-Output "    ${fork}: no CLI found - settings handled, extensions skipped" }
            else                  { Write-Output "    ${fork}: no CLI found - extensions skipped" }
        }
    }
}

# ------------------------------------------------------------
#  Release-driven actions (install/uninstall) + dashboard
# ------------------------------------------------------------
. (Join-Path $PSScriptRoot "version.ps1")
. (Join-Path $PSScriptRoot "release.ps1")

$script:LatestCache = @{}

# Get-LatestCached <fork> - latest version (or "unknown"), cached per session.
function Get-LatestCached($fork) {
    if ($script:LatestCache.ContainsKey($fork)) { return $script:LatestCache[$fork] }
    $v = "unknown"
    try { $v = Get-LatestVersion $fork } catch { $v = "unknown" }
    $script:LatestCache[$fork] = $v
    return $v
}
function Reset-LatestCache($fork) { $script:LatestCache.Remove($fork) | Out-Null }

# Resolve-Cli <fork> - PATH first, else known install-path binary
# (closes the fresh-install dead-end: install -> config in the same session).
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

# Show-ListVersions - -l / --list-versions table
function Show-ListVersions {
    Write-Output ""
    "{0,-10} {1,-12} {2}" -f "name", "installed", "latest"
    foreach ($f in $FORK_ORDER) {
        $inst = Get-InstalledVersion $f
        if (-not $inst) { $inst = "-" }
        "{0,-10} {1,-12} {2}" -f $f, $inst, (Get-LatestCached $f)
    }
}

# Show-Dashboard - one row per fork: name / installed / latest / settings / extensions
function Show-Dashboard {
    "{0,-8} {1,-12} {2,-12} {3,-9} {4}" -f "name", "installed", "latest", "settings", "extensions"
    foreach ($f in $FORK_ORDER) {
        $inst = Get-InstalledVersion $f
        if (-not $inst) { $inst = "-" }
        $latest = Get-LatestCached $f
        $sp = Get-SettingsPath $f
        if (Test-Path $sp) {
            if (Test-SameSettings $sp (Join-Path $CONFIG_DIR "settings.json")) {
                $settings = "synced"
            } else {
                $settings = "diverged"
            }
        } else {
            $settings = "-"
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

# Install-Editor <fork> [<variant>] - download (syncode temp name) + silent
# install. Variant is a releases.json installer key: "win" (user exe, default),
# "winSystem" (system exe), "winMsi" (VSCodium MSI). exe installers run Inno
# (/VERYSILENT /NORESTART /mergetasks=!runcode so the editor doesn't relaunch);
# msi installers run msiexec. The download renders a live progress line; the
# installer run renders a spinner. "already installed" check lives at the call
# sites; installs are always fresh (no update path - editors self-update).
function Install-Editor($fork, $variant = "win") {
    $ver = Get-LatestCached $fork
    if ($ver -eq "unknown") { throw "${fork}: can't determine latest version" }
    $url = Get-ReleaseUrl $fork $variant $ver
    $ext = if ($variant -match "msi") { "msi" } else { "exe" }
    $tmp = Join-Path $env:TEMP ("syncode-{0}-{1}.{2}" -f $fork, [guid]::NewGuid().ToString("N"), $ext)
    Get-Download $fork $ver $url $tmp
    if ($ext -eq "msi") {
        $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", $tmp, "/qn", "/norestart" -PassThru
    } else {
        $p = Start-Process -FilePath $tmp -ArgumentList "/VERYSILENT", "/NORESTART", "/mergetasks=!runcode" -PassThru
    }
    Wait-ProcessSpinner "  ${fork}: installing $ver" $p
    Remove-Item -Force $tmp
    if ($p.ExitCode -ne 0) { throw "${fork}: installer failed (exit $($p.ExitCode))" }
    Write-Output "  $fork installed"
}

# Uninstall-Editor <fork> - unins000.exe /VERYSILENT, winget fallback, config dir.
# Checks both user (%LOCALAPPDATA%\Programs) and system ($env:ProgramFiles) install
# dirs; MSI installs have no unins000.exe and fall through to winget by design.
function Uninstall-Editor($fork) {
    # install dir name differs from config dir name for code (Microsoft VS Code)
    $installDir = if ($fork -eq "code") { "Microsoft VS Code" } else { "VSCodium" }
    $dirs = @(
        (Join-Path $env:LOCALAPPDATA "Programs\$installDir"),
        (Join-Path ${env:ProgramFiles(x86)} "$installDir"),
        (Join-Path $env:ProgramFiles "$installDir")
    )
    $un = $null
    foreach ($d in $dirs) {
        $candidate = Join-Path $d "unins000.exe"
        if (Test-Path $candidate) { $un = $candidate; break }
    }
    if ($un) {
        $p = Start-Process -FilePath $un -ArgumentList "/VERYSILENT", "/NORESTART" -PassThru
        Wait-ProcessSpinner "  ${fork}: uninstalling" $p
        if ($p.ExitCode -ne 0) { Write-LogWarn "${fork}: uninstaller exit $($p.ExitCode)" }
    } else {
        $id = Get-ReleaseWinget $fork
        Write-Output "  ${fork}: unins000.exe not found - winget fallback: $id"
        winget uninstall --id $id --silent --accept-source-agreements | Out-Null
    }
    Remove-Item -Recurse -Force (Join-Path $DATA_ROOT $FORK_DIR[$fork]) -ErrorAction SilentlyContinue
    Write-Output "  $fork removed"
}

# Select-InstallVariant <fork> - dashboard sub-prompt for installer variant.
# Returns a releases.json installer key; Enter/empty = "win" (user, current default).
function Select-InstallVariant($fork) {
    if ($fork -eq "code") {
        Write-Output "  installer variant:"
        Write-Output "    1. User Installer"
        Write-Output "    2. System Installer"
        $line = Read-Line "  pick (default 1=User): "
        if ($null -ne $line) { $line = $line.Trim() }
        switch ($line) {
            "2" { return "winSystem" }
            "1" { return "win" }
            default { return "win" }
        }
    }
    Write-Output "  installer variant:"
    Write-Output "    1. User Installer"
    Write-Output "    2. System Installer"
    Write-Output "    3. MSI (updates enabled)"
    $line = Read-Line "  pick (default 1=User): "
    if ($null -ne $line) { $line = $line.Trim() }
    switch ($line) {
        "2" { return "winSystem" }
        "3" { return "winMsi" }
        "1" { return "win" }
        default { return "win" }
    }
}

# Show-ActionHelp - shared help text offered by the Help option in every menu.
function Show-ActionHelp {
    Write-Output "  install    install latest stable if not installed"
    Write-Output "  settings   copy settings.json (backup .bak) to the editor"
    Write-Output "  extensions pick which extensions to install/uninstall"
    Write-Output '  reset      restore factory defaults  (type "reset" to confirm)'
    Write-Output '  uninstall  remove editor and its config dir  (type "uninstall" to confirm)'
}

# Pick-Extensions <fork> - multiselect extension manager: toggle with numbers,
# a=all, n=none, i=install selected, u=uninstall selected, h=help, m=back to
# the config menu, q=quit. Only toggle state lives here; i/u run the CLI.
function Pick-Extensions($fork) {
    $ids = @(Get-ExtIds)
    if ($ids.Count -eq 0) { Write-Output "  no extensions in extensions.json"; return }
    $sel = @{}
    :extpick while ($true) {
        Write-Output "  $($FORK_FULL[$fork]) extensions"
        for ($i = 0; $i -lt $ids.Count; $i++) {
            $mark = if ($sel[$ids[$i]]) { "x" } else { " " }
            Write-Output ("    {0}. [{1}] {2}" -f ($i + 1), $mark, $ids[$i])
        }
        Write-Output "  a. All  n. None  i. Install selected  u. Uninstall selected"
        Write-Output "  h. Help  m. Menu  q. Quit"
        $line = Read-Line "  Enter an option: "
        if ($null -eq $line) { Write-Output "bye."; exit 0 }
        $line = $line.Trim()
        if ($line -match '^\d+$') {
            $n = [int]$line - 1
            if ($n -ge 0 -and $n -lt $ids.Count) {
                $id = $ids[$n]
                $sel[$id] = -not $sel[$id]
            } else { Write-Output "invalid: $line" }
            continue extpick
        }
        switch ($line.ToLower()) {
            "a" {
                foreach ($id in $ids) { $sel[$id] = $true }
            }
            "n" {
                foreach ($id in $ids) { $sel[$id] = $false }
            }
            "i" {
                $picked = @($ids | Where-Object { $sel[$_] })
                if ($picked.Count -eq 0) { Write-Output "  nothing selected"; continue extpick }
                $cli = Get-Command -Name $fork -ErrorAction SilentlyContinue
                if (-not $cli) { Write-Output "  $fork not on PATH - cannot install"; continue extpick }
                foreach ($id in $picked) {
                    $null | & $cli.Source --install-extension $id --force 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) { Write-Output "    installed $id" }
                    else                     { Write-LogWarn "${fork}: FAILED to install $id" }
                }
                $sel.Clear()
            }
            "u" {
                $picked = @($ids | Where-Object { $sel[$_] })
                if ($picked.Count -eq 0) { Write-Output "  nothing selected"; continue extpick }
                $cli = Get-Command -Name $fork -ErrorAction SilentlyContinue
                if (-not $cli) { Write-Output "  $fork not on PATH - cannot uninstall"; continue extpick }
                foreach ($id in $picked) {
                    $null | & $cli.Source --uninstall-extension $id 2>$null | Out-Null
                    Write-Output "    uninstalled $id"
                }
                $sel.Clear()
            }
            "h" { Show-ActionHelp; continue extpick }
            "m" { return }
            "q" { Write-Output "bye."; exit 0 }
            default { Write-Output "invalid: $line" }
        }
    }
}

# Run-Dashboard - interactive hub: pick editor, pick action, loop. Numbered
# menus; every menu offers Help + Quit, non-first menus add Menu (back to the
# editor picker). The editor's full name is shown above the action menu.
function Run-Dashboard {
    :main while ($true) {
        Write-Output ""
        Show-Dashboard
        Write-Output ""
        $editor = ""
        :editorpick while ($true) {
            Write-Output "  Pick an option:"
            Write-Output "    1. Visual Studio Code"
            Write-Output "    2. VSCodium"
            Write-Output "    3. Help"
            Write-Output "    4. Quit"
            $line = Read-Line "  Enter an option: "
            if ($null -eq $line) { Write-Output "bye."; exit 0 }
            $line = $line.Trim()
            switch ($line) {
                "1"      { $editor = "code"; break editorpick }
                "2"      { $editor = "codium"; break editorpick }
                "3"      { Show-ActionHelp; continue editorpick }
                "4"      { Write-Output "bye."; exit 0 }
                "q"      { Write-Output "bye."; exit 0 }
                "Q"      { Write-Output "bye."; exit 0 }
                "code"   { $editor = "code"; break editorpick }
                "codium" { $editor = "codium"; break editorpick }
                default  { Write-Output "invalid: $line" }
            }
        }
        $action = ""
        :actionpick while ($true) {
            # Config only makes sense when the editor is installed
            $opts = @()
            $opts += ,@("Install", "install")
            if (Get-InstalledVersion $editor) { $opts += ,@("Config", "config") }
            $opts += @("Reset", "reset"), @("Uninstall", "uninstall"), @("Help", "help"), @("Menu", "menu"), @("Quit", "quit")
            Write-Output "  $($FORK_FULL[$editor])"
            Write-Output "  Pick an option:"
            for ($i = 0; $i -lt $opts.Count; $i++) {
                Write-Output ("    {0}. {1}" -f ($i + 1), $opts[$i][0])
            }
            $line = Read-Line "  Enter an option: "
            if ($null -eq $line) { Write-Output "bye."; exit 0 }
            $line = $line.Trim()
            $sel = ""
            if ($line -match '^\d+$') {
                $n = [int]$line - 1
                if ($n -ge 0 -and $n -lt $opts.Count) { $sel = $opts[$n][1] } else { $sel = "invalid" }
            } else {
                $sel = $line.ToLower()
            }
            switch ($sel) {
                "install"   { $action = "install"; break actionpick }
                "config"    { $action = "config"; break actionpick }
                "reset"     { $action = "reset"; break actionpick }
                "uninstall" { $action = "uninstall"; break actionpick }
                "help"      { Show-ActionHelp; continue actionpick }
                "menu"      { continue main }
                "quit"      { Write-Output "bye."; exit 0 }
                "q"         { Write-Output "bye."; exit 0 }
                default     { Write-Output "invalid: $line" }
            }
        }
        switch ($action) {
            "config" {
                :configpick while ($true) {
                    Write-Output "  $($FORK_FULL[$editor])"
                    Write-Output "  Pick an option:"
                    Write-Output "    1. Settings"
                    Write-Output "    2. Extensions"
                    Write-Output "    3. Help"
                    Write-Output "    4. Menu"
                    Write-Output "    5. Quit"
                    $line = Read-Line "  Enter an option: "
                    if ($null -eq $line) { Write-Output "bye."; exit 0 }
                    $line = $line.Trim()
                    switch ($line) {
                        "1" {
                            try { Apply-Fork $editor "settings" }
                            catch { Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red }
                            continue configpick
                        }
                        "2" { Pick-Extensions $editor; continue configpick }
                        "3" { Show-ActionHelp; continue configpick }
                        "4" { continue main }
                        "5" { Write-Output "bye."; exit 0 }
                        "q" { Write-Output "bye."; exit 0 }
                        "Q" { Write-Output "bye."; exit 0 }
                        default { Write-Output "invalid: $line" }
                    }
                }
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
                    Write-Output "  not confirmed - skipped"
                }
            }
            "uninstall" {
                $line = Read-Line 'Type "uninstall" to confirm: '
                if ($null -ne $line -and $line.Trim() -eq "uninstall") {
                    try { Uninstall-Editor $editor }
                    catch { Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red }
                    Reset-LatestCache $editor
                } else {
                    Write-Output "  not confirmed - skipped"
                }
            }
            "install" {
                if (Get-InstalledVersion $editor) {
                    Write-Output "  $editor already installed"
                } else {
                    try { Install-Editor $editor (Select-InstallVariant $editor) }
                    catch { Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red }
                    Reset-LatestCache $editor
                }
            }
        }
    }
}

# Resolve-ActionForks <arg> - empty = all forks, else one fork (code|codium).
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

# action flags take priority (list-versions / install / uninstall)
$action = ""
$actionForks = @()
$forkArg = if ($Rest.Count -gt 0) { $Rest -join " " } else { "" }
if ($Install) { $action = "install"; $actionForks = Resolve-ActionForks $forkArg }
if ($Uninstall) {
    if ($action) { Write-Host "[ERROR] conflicting actions: only one of -i/-u allowed" -ForegroundColor Red; exit 1 }
    $action = "uninstall"; $actionForks = Resolve-ActionForks $forkArg
}
if ($ListVersions) {
    if ($action) { Write-Host "[ERROR] conflicting actions: only one of -i/-u allowed" -ForegroundColor Red; exit 1 }
    $action = "list-versions"; $actionForks = @()
}

if ($action) {
    if ($action -eq "list-versions") {
        Show-ListVersions
        exit 0
    }
    if ($DryRun) {
        Write-Output ""
        "{0,-10} {1,-12} {2,-12} {3}" -f "name", "installed", "latest", "action"
        foreach ($f in $actionForks) {
            $inst = Get-InstalledVersion $f
            if (-not $inst) { $inst = "none" }
            $latest = Get-LatestCached $f
            $desc = switch ($action) {
                "install"   { "install $latest" }
                "uninstall" { "remove editor + config" }
            }
            "{0,-10} {1,-12} {2,-12} {3}" -f $f, $inst, $latest, $desc
        }
        Write-Output "DRY RUN - nothing applied."
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

# no flags -> interactive dashboard
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
