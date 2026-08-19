# ============================================================
#  syncode.ps1 - Sync and manage your VSCode and VSCodium editors.
#  Windows / PowerShell version (Windows only).
#  Version: 1.4.0
# ============================================================
$ErrorActionPreference = "Stop"
$Revert = $false

# syncode takes no arguments - the interactive dashboard is the whole tool.
if ($args.Count -gt 0) {
    Write-Host "[ERROR] syncode takes no arguments" -ForegroundColor Red
    exit 1
}

$VERSION_STR = "1.4.0"
$TOOL_NAME = "syncode"
$DESCRIPTION = "Sync and manage your VSCode and VSCodium editors"

$BANNER = @'
:'######::'##:::'##:'##::: ##::'######:::'#######::'########::'########:
'##... ##:. ##:'##:: ###:: ##:'##... ##:'##.... ##: ##.... ##: ##.....::
 ##:::..:::. ####::: ####: ##: ##:::..:: ##:::: ##: ##:::: ##: ##:::::::
. ######::::. ##:::: ## ## ##: ##::::::: ##:::: ##: ##:::: ##: ######:::
:..... ##:::: ##:::: ##. ####: ##::::::: ##:::: ##: ##:::: ##: ##...::::
'##::: ##:::: ##:::: ##:. ###: ##::: ##: ##:::: ##: ##:::: ##: ##:::::::
. ######::::: ##:::: ##::. ##:. ######::. #######:: ########:: ########:
:......::::::..:::::..::::..:::......::::.......:::........:::........::
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
    # Real console: force UTF-8 output so [Console]::Write can carry Unicode
    # glyphs. Legacy codepages (cp437/850) convert anything outside their set
    # to '?' - VT-era conhost and Windows Terminal both decode UTF-8 fine.
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
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

# The braille ring needs a Unicode-capable console output encoding, not just
# ANSI/VT (cp437/850 would render the glyphs as '?'), so gate it separately.
# The OutputEncoding set above makes this true whenever we have a real console.
$script:CanUnicode = $false
if (-not [Console]::IsOutputRedirected) {
    try { $script:CanUnicode = ([Console]::OutputEncoding.CodePage -eq 65001) } catch { $script:CanUnicode = $false }
}

# Braille dot-ring spinner (U+2800 block). Built from codepoints so this file
# stays pure ASCII (CI enforces ASCII ps1; 5.1 reads BOM-less UTF-8 as ANSI).
$script:SpinnerFrames = -join (0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F | ForEach-Object { [char]$_ })
$script:Check = if ($script:CanUnicode) { [char]0x2713 } else { "[OK]" }

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
    $frames = if ($script:CanUnicode) { $script:SpinnerFrames } else { "|/-\" }
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
                Write-ProgressLine $label $name $pct $frames[$i % $frames.Length]
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
    $frames = if ($script:CanUnicode) { $script:SpinnerFrames } else { "|/-\" }
    $i = 0
    while (-not $p.HasExited) {
        Write-ProgressLine $label "" -1 $frames[$i % $frames.Length]
        $i++
        Start-Sleep -Milliseconds 120
    }
    Write-ProgressLine $label "" -1 " "
    Write-Output ""
}

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
    code      = "VSCode"
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

$script:ExtCache = @{}

function Get-InstalledExts($fork) {
    if ($script:ExtCache.ContainsKey($fork)) { return $script:ExtCache[$fork] }
    $cli = Get-Command -Name $fork -ErrorAction SilentlyContinue
    if (-not $cli) { $script:ExtCache[$fork] = @(); return @() }
    # $null | closes stdin on the native CLI so it can't eat interactive input;
    # .Trim() strips the trailing CR from Windows CRLF output
    $exts = @($null | & $cli.Source --list-extensions 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $script:ExtCache[$fork] = $exts
    return $exts
}

function Reset-ExtCache($fork) { $script:ExtCache.Remove($fork) | Out-Null }

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
                Write-Output "${fork}: restored settings.json from .bak"
            } elseif (Test-Path $sp) {
                Remove-Item -Force $sp
                Write-Output "${fork}: deleted settings.json (factory defaults)"
            } else {
                Write-Output "${fork}: no settings.json to revert"
            }
        } else {
            if ((Test-Path $sp) -and (Test-SameSettings $sp $settingsSrc)) {
                Write-Output "${fork}: settings already in sync"
            } else {
                if (Test-Path $sp) { Copy-Item -Force $sp $bd }
                Copy-Item -Force $settingsSrc $sp
                Write-Output "${fork}: settings copied (backup -> .bak)"
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
                        Write-Output "${fork}: uninstalled $id"
                    }
                }
            } else {
                foreach ($id in @(Get-MissingExts $fork)) {
                    $null | & $cli.Source --install-extension $id --force 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) { Write-Output "${fork}: installed $id" }
                    else                     { Write-LogWarn "${fork}: FAILED to install $id" }
                }
            }
        } else {
            if ($Scope -eq "all") { Write-Output "${fork}: no CLI found - settings handled, extensions skipped" }
            else                  { Write-Output "${fork}: no CLI found - extensions skipped" }
        }
    }
    Reset-ExtCache $fork
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

# Show-Dashboard - one row per fork: name / installed / latest / settings / extensions
function Show-Dashboard {
    # Boxed grid: column width = longest cell (header or value) + 2 padding so
    # nothing ever overflows; ASCII-only box (5.1 can't render box-drawing
    # glyphs, and output stays byte-identical with the bash port). The header
    # row is bold when the console supports VT.
    $hdr = @("Name", "Installed", "Latest", "Settings", "Extensions")
    $rows = @()
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
        $rows += ,@($FORK_FULL[$f], $inst, $latest, $settings, $ext)
    }
    $w = @()
    for ($i = 0; $i -lt 5; $i++) {
        $len = $hdr[$i].Length
        foreach ($r in $rows) { if ($r[$i].Length -gt $len) { $len = $r[$i].Length } }
        $w += ($len + 2)
    }
    $b = ""; $R = ""
    if ($script:CanAnsi) { $e = [char]27; $b = "$e[1m"; $R = "$e[0m" }
    $line = "+"
    foreach ($wi in $w) { $line += ("-" * $wi) + "+" }
    Write-Output $line
    $out = "|"
    for ($i = 0; $i -lt 5; $i++) {
        $out += (" {0}{1,-$($w[$i] - 2)}{2} |" -f $b, $hdr[$i], $R)
    }
    Write-Output $out
    Write-Output $line
    foreach ($r in $rows) {
        $out = "|"
        for ($i = 0; $i -lt 5; $i++) {
            $out += (" {0,-$($w[$i] - 2)} |" -f $r[$i])
        }
        Write-Output $out
    }
    Write-Output $line
}

# Show-Banner - ASCII art + version + description header.
function Show-Banner {
    Write-Output ""
    Write-Output $BANNER
    Write-Output ""
    Write-Output "$TOOL_NAME v$VERSION_STR - $DESCRIPTION"
}

# Show-Frame <notice> - repaint the whole dashboard: clear (interactive only),
# banner, status table, optional notice line. Called at the top of every menu
# loop so each pick swaps the view instead of stacking. No clear when output is
# redirected (CI, pipes) so the transcript stays readable.
function Show-Frame($notice) {
    if (-not [Console]::IsOutputRedirected) { try { [Console]::Clear() } catch {} }
    Show-Banner
    Write-Output ""
    Show-Dashboard
    # blank line between the status table and the notice, matching the
    # blank line before the menu, so notices read as their own line.
    if ($notice) {
        Write-Output ""
        Write-Output $notice
    }
    Write-Output ""
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
    Wait-ProcessSpinner "  ${fork}: Installing $ver" $p
    Remove-Item -Force $tmp
    if ($p.ExitCode -ne 0) { throw "${fork}: installer failed (exit $($p.ExitCode))" }
    Write-Output "$script:Check $($FORK_FULL[$fork]) installed successfully."
    Reset-InstalledCache $fork
    Reset-ExtCache $fork
    Reset-LatestCache $fork
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
        Wait-ProcessSpinner "  ${fork}: Uninstalling" $p
        if ($p.ExitCode -ne 0) { Write-LogWarn "${fork}: uninstaller exit $($p.ExitCode)" }
    } else {
        $id = Get-ReleaseWinget $fork
        Write-Output "${fork}: unins000.exe not found - winget fallback: $id"
        winget uninstall --id $id --silent --accept-source-agreements | Out-Null
    }
    Remove-Item -Recurse -Force (Join-Path $DATA_ROOT $FORK_DIR[$fork]) -ErrorAction SilentlyContinue
    Write-Output "$fork removed"
    Reset-InstalledCache $fork
    Reset-ExtCache $fork
    Reset-LatestCache $fork
}

# Select-InstallVariant <fork> - dashboard sub-prompt for installer variant.
# Same framed layout as the other menus (header, gap, numbered options, gap,
# "Enter an option: "); returns a releases.json installer key, or "menu"/
# "quit" for the nav options. Enter/empty/invalid = "win" (user, default).
# Write-Host, not Write-Output: the caller assigns the result, so
# Write-Output lines would leak into $variant.
function Select-InstallVariant($fork) {
    $opts = @()
    $opts += ,@("User Installer", "win")
    $opts += ,@("System Installer", "winSystem")
    if ($fork -eq "codium") { $opts += ,@("Microsoft Software Installer", "winMsi") }
    $opts += @("Menu", "menu"), @("Quit", "quit")
    Write-Host "Select an installer variant for $($FORK_FULL[$fork]):"
    Write-Host ""
    for ($i = 0; $i -lt $opts.Count; $i++) {
        Write-Host ("{0}. {1}" -f ($i + 1), $opts[$i][0])
    }
    Write-Host ""
    $line = Read-Line "Enter an option: "
    if ($null -ne $line) { $line = $line.Trim() }
    if ($line -match '^\d+$') {
        $n = [int]$line - 1
        if ($n -ge 0 -and $n -lt $opts.Count) { return $opts[$n][1] }
        return "win"
    }
    switch ($line.ToLower()) {
        "user"   { return "win" }
        "system" { return "winSystem" }
        "msi"    { return "winMsi" }
        "menu"   { return "menu" }
        "quit"   { return "quit" }
        "q"      { return "quit" }
        default  { return "win" }
    }
}

# Pick-Extensions <fork> - multiselect extension manager: toggle with numbers,
# a=all, n=none, i=install selected, u=uninstall selected, m=back to
# the config menu, q=quit. Only toggle state lives here; i/u run the CLI.
# Feedback goes to $script:Notice so the repainted frame keeps showing it.
function Pick-Extensions($fork) {
    $ids = @(Get-ExtIds)
    if ($ids.Count -eq 0) { $script:Notice = "no extensions in extensions.json"; return }
    $sel = @{}
    :extpick while ($true) {
        Show-Frame $script:Notice
        Write-Output "Pick extensions for $($FORK_FULL[$fork]):"
        Write-Output ""
        for ($i = 0; $i -lt $ids.Count; $i++) {
            $mark = if ($sel[$ids[$i]]) { "x" } else { " " }
            Write-Output ("{0}. [{1}] {2}" -f ($i + 1), $mark, $ids[$i])
        }
        Write-Output "a. All  n. None  i. Install selected  u. Uninstall selected"
        Write-Output "m. Menu  q. Quit"
        Write-Output ""
        $line = Read-Line "Enter an option: "
        if ($null -eq $line) { Write-Output "bye."; exit 0 }
        $line = $line.Trim()
        if ($line -match '^\d+$') {
            $n = [int]$line - 1
            if ($n -ge 0 -and $n -lt $ids.Count) {
                $id = $ids[$n]
                $sel[$id] = -not $sel[$id]
                $script:Notice = ""
            } else { $script:Notice = "invalid: $line" }
            continue extpick
        }
        switch ($line.ToLower()) {
            "a" {
                foreach ($id in $ids) { $sel[$id] = $true }
                $script:Notice = "all selected"
            }
            "n" {
                foreach ($id in $ids) { $sel[$id] = $false }
                $script:Notice = "none selected"
            }
            "i" {
                $picked = @($ids | Where-Object { $sel[$_] })
                if ($picked.Count -eq 0) { $script:Notice = "nothing selected"; continue extpick }
                $cli = Get-Command -Name $fork -ErrorAction SilentlyContinue
                if (-not $cli) { $script:Notice = "$fork not on PATH - cannot install"; continue extpick }
                $out = @()
                foreach ($id in $picked) {
                    $null | & $cli.Source --install-extension $id --force 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) { $out += "installed $id" }
                    else                     { Write-LogWarn "${fork}: FAILED to install $id" }
                }
                $sel.Clear()
                $script:Notice = $out -join "`n"
                Reset-ExtCache $fork
            }
            "u" {
                $picked = @($ids | Where-Object { $sel[$_] })
                if ($picked.Count -eq 0) { $script:Notice = "nothing selected"; continue extpick }
                $cli = Get-Command -Name $fork -ErrorAction SilentlyContinue
                if (-not $cli) { $script:Notice = "$fork not on PATH - cannot uninstall"; continue extpick }
                $out = @()
                foreach ($id in $picked) {
                    $null | & $cli.Source --uninstall-extension $id 2>$null | Out-Null
                    $out += "uninstalled $id"
                }
                $sel.Clear()
                $script:Notice = $out -join "`n"
                Reset-ExtCache $fork
            }
            "m" { return }
            "q" { Write-Output "bye."; exit 0 }
            default { $script:Notice = "invalid: $line" }
        }
    }
}

# Run-Dashboard - interactive hub: pick editor, pick action, loop. Numbered
# menus; every menu offers Quit, non-first menus add Menu (back to the
# editor picker). The editor's full name is folded into the menu prompt.
# Each loop iteration repaints the full frame (banner + table + notice + menu).
function Run-Dashboard {
    $script:Notice = ""
    :main while ($true) {
        $editor = ""
        :editorpick while ($true) {
            Show-Frame $script:Notice
            Write-Output "Pick an editor:"
            Write-Output ""
            Write-Output "1. VSCode"
            Write-Output "2. VSCodium"
            Write-Output "3. Quit"
            Write-Output ""
            $line = Read-Line "Enter an option: "
            if ($null -eq $line) { Write-Output "bye."; exit 0 }
            $line = $line.Trim()
            switch ($line) {
                "1"      { $editor = "code"; break editorpick }
                "2"      { $editor = "codium"; break editorpick }
                "3"      { Write-Output "bye."; exit 0 }
                "q"      { Write-Output "bye."; exit 0 }
                "Q"      { Write-Output "bye."; exit 0 }
                "code"   { $editor = "code"; break editorpick }
                "codium" { $editor = "codium"; break editorpick }
                default  { $script:Notice = "invalid: $line"; continue editorpick }
            }
        }
        :actionpick while ($true) {
            # Config/Reset only make sense when the editor is installed
            $opts = @()
            $opts += ,@("Install", "install")
            if (Get-InstalledVersion $editor) {
                $opts += ,@("Config", "config")
                $opts += ,@("Reset", "reset")
            }
            $opts += @("Uninstall", "uninstall"), @("Menu", "menu"), @("Quit", "quit")
            Show-Frame $script:Notice
            Write-Output "Pick an option for $($FORK_FULL[$editor]):"
            Write-Output ""
            for ($i = 0; $i -lt $opts.Count; $i++) {
                Write-Output ("{0}. {1}" -f ($i + 1), $opts[$i][0])
            }
            Write-Output ""
            $line = Read-Line "Enter an option: "
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
                "install" {
                    # handlers run inside the actionpick loop so the frame
                    # repaints in place (same editor's action menu); only
                    # Menu/Quit leave it. The stale action menu is cleared
                    # before the variant pick, then again before the download,
                    # so each stage renders on a fresh frame.
                    if (Get-InstalledVersion $editor) {
                        $script:Notice = "$editor already installed"
                    } else {
                        Show-Frame ""
                        $variant = Select-InstallVariant $editor
                        if ($variant -eq "menu") { continue actionpick }
                        if ($variant -eq "quit") { Write-Output "bye."; exit 0 }
                        $script:Notice = "Installing $($FORK_FULL[$editor])..."
                        Show-Frame $script:Notice
                        try { Install-Editor $editor $variant; $script:Notice = "$script:Check $($FORK_FULL[$editor]) installed successfully." }
                        catch { $script:Notice = "[ERROR] $($_.Exception.Message)" }
                    }
                    continue actionpick
                }
                "config" {
                    :configpick while ($true) {
                        Show-Frame $script:Notice
                        Write-Output "Pick a config for $($FORK_FULL[$editor]):"
                        Write-Output ""
                        Write-Output "1. Settings"
                        Write-Output "2. Extensions"
                        Write-Output "3. Menu"
                        Write-Output "4. Quit"
                        Write-Output ""
                        $line = Read-Line "Enter an option: "
                        if ($null -eq $line) { Write-Output "bye."; exit 0 }
                        $line = $line.Trim()
                        switch ($line) {
                            "1" {
                                $script:Notice = "Applying $($FORK_FULL[$editor])..."
                                Show-Frame $script:Notice
                                try { Apply-Fork $editor "settings"; $script:Notice = "$editor settings applied" }
                                catch { $script:Notice = "[ERROR] $($_.Exception.Message)" }
                                continue configpick
                            }
                            "2" { Pick-Extensions $editor; continue configpick }
                            "3" { continue main }
                            "4" { Write-Output "bye."; exit 0 }
                            "q" { Write-Output "bye."; exit 0 }
                            "Q" { Write-Output "bye."; exit 0 }
                            default { $script:Notice = "invalid: $line"; continue configpick }
                        }
                    }
                }
                "reset" {
                    Show-Frame ""
                    $line = Read-Line 'Type "reset" to confirm: '
                    if ($null -ne $line -and $line.Trim() -eq "reset") {
                        $script:Notice = "Resetting $($FORK_FULL[$editor])..."
                        Show-Frame $script:Notice
                        try {
                            $Revert = $true; Apply-Fork $editor; $Revert = $false
                            $script:Notice = "$editor reset to factory defaults"
                        } catch {
                            $Revert = $false
                            $script:Notice = "[ERROR] $($_.Exception.Message)"
                        }
                    } else {
                        $script:Notice = "not confirmed - skipped"
                    }
                    continue actionpick
                }
                "uninstall" {
                    Show-Frame ""
                    $line = Read-Line 'Type "uninstall" to confirm: '
                    if ($null -ne $line -and $line.Trim() -eq "uninstall") {
                        $script:Notice = "Uninstalling $($FORK_FULL[$editor])..."
                        Show-Frame $script:Notice
                        try { Uninstall-Editor $editor; $script:Notice = "$editor uninstalled" }
                        catch { $script:Notice = "[ERROR] $($_.Exception.Message)" }
                    } else {
                        $script:Notice = "not confirmed - skipped"
                    }
                    continue actionpick
                }
                "menu"      { continue main }
                "quit"      { Write-Output "bye."; exit 0 }
                "q"         { Write-Output "bye."; exit 0 }
                default     { $script:Notice = "invalid: $line"; continue actionpick }
            }
        }
    }
}

# ------------------------------------------------------------
#  Main
# ------------------------------------------------------------
# syncode takes no arguments - the interactive dashboard is the whole tool:
# pick an editor, then install (with a variant picker), config, reset,
# uninstall. Run-Dashboard loops until Quit.
Run-Dashboard
