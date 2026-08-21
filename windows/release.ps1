# ============================================================
#  syncode release module (Windows/PowerShell)
#  Loads shared/releases.json (via ..\shared), fetches latest versions,
#  builds installer URLs. Dot-sourced by syncode.ps1.
# ============================================================

if (-not $CONFIG_DIR) { $CONFIG_DIR = Join-Path $PSScriptRoot "..\shared" }
$RELEASES_FILE = Join-Path $CONFIG_DIR "releases.json"

$script:Releases = $null
$script:RateLimited = $false

function Get-Releases {
    if ($null -eq $script:Releases) {
        $script:Releases = Get-Content $RELEASES_FILE -Raw | ConvertFrom-Json
    }
    return $script:Releases
}

function Get-ReleaseLatestApi($fork)        { return (Get-Releases).$fork.latestApi }
function Get-ReleaseInstallerUrl($fork, $platform) { return (Get-Releases).$fork.installer.$platform }
function Get-ReleaseUrl($fork, $platform, $ver) {
    return (Get-ReleaseInstallerUrl $fork $platform).Replace('<ver>', $ver)
}
function Get-ReleaseUninstallType($fork, $platform) { return (Get-Releases).$fork.uninstall.$platform.type }
function Get-ReleaseUninstallExe($fork)     { return (Get-Releases).$fork.uninstall.win.exe }
function Get-ReleaseUninstallName($fork)    { return (Get-Releases).$fork.uninstall.linux.name }
function Get-ReleaseWinget($fork)           { return (Get-Releases).$fork.package.winget }

# Get-LatestVersion <fork> - latest version string.
# Sets $script:RateLimited = $true when codium hit GitHub's 403 rate limit.
function Get-LatestVersion($fork) {
    $script:RateLimited = $false
    if ($fork -eq "code") {
        # PS passes a top-level JSON array as ONE object; index it directly
        # ($arr = @(...) would nest it and [0] would be the whole array).
        $r = Invoke-RestMethod -Uri (Get-ReleaseLatestApi $fork) -TimeoutSec 10
        return ([string]$r[0])
    }
    try {
        $r = Invoke-RestMethod -Uri (Get-ReleaseLatestApi $fork) `
            -Headers @{ "User-Agent" = "syncode" } -TimeoutSec 10
        # zed tags carry a leading v (v1.16.1); normalize like the bash port
        return (($r.tag_name) -replace '^v', '')
    } catch {
        $resp = $_.Exception.Response
        if ($null -ne $resp -and [int]$resp.StatusCode -eq 403) {
            $limit = $resp.Headers["X-RateLimit-Remaining"]
            if ($limit -eq "0") { $script:RateLimited = $true }
        }
        throw
    }
}

# ------------------------------------------------------------
#  Self-check (runs only when executed directly, not dot-sourced)
# ------------------------------------------------------------
function Test-ReleaseModule {
    $cases = @(
        @("https://update.code.visualstudio.com/api/releases/stable", (Get-ReleaseLatestApi "code")),
        @("https://update.code.visualstudio.com/<ver>/win32-x64-user/stable", (Get-ReleaseInstallerUrl "code" "win")),
        @("https://update.code.visualstudio.com/<ver>/win32-x64/stable", (Get-ReleaseInstallerUrl "code" "winSystem")),
        @("https://update.code.visualstudio.com/<ver>/linux-deb-x64/stable", (Get-ReleaseInstallerUrl "code" "linux")),
        @("https://update.code.visualstudio.com/<ver>/linux-rpm-x64/stable", (Get-ReleaseInstallerUrl "code" "linuxRpm")),
        @("https://update.code.visualstudio.com/<ver>/linux-x64/stable", (Get-ReleaseInstallerUrl "code" "linuxTar")),
        @("https://github.com/VSCodium/vscodium/releases/download/<ver>/VSCodiumUserSetup-x64-<ver>.exe", (Get-ReleaseInstallerUrl "codium" "win")),
        @("https://github.com/VSCodium/vscodium/releases/download/<ver>/VSCodiumSetup-x64-<ver>.exe", (Get-ReleaseInstallerUrl "codium" "winSystem")),
        @("https://github.com/VSCodium/vscodium/releases/download/<ver>/VSCodium-x64-<ver>.msi", (Get-ReleaseInstallerUrl "codium" "winMsi")),
        @("https://github.com/VSCodium/vscodium/releases/download/<ver>/codium_<ver>_amd64.deb", (Get-ReleaseInstallerUrl "codium" "linux")),
        @("https://github.com/VSCodium/vscodium/releases/download/<ver>/codium-<ver>-el8.x86_64.rpm", (Get-ReleaseInstallerUrl "codium" "linuxRpm")),
        @("https://github.com/VSCodium/vscodium/releases/download/<ver>/VSCodium-linux-x64-<ver>.tar.gz", (Get-ReleaseInstallerUrl "codium" "linuxTar")),
        @("https://api.github.com/repos/zed-industries/zed/releases/latest", (Get-ReleaseLatestApi "zed")),
        @("https://github.com/zed-industries/zed/releases/download/v<ver>/Zed-x86_64.exe", (Get-ReleaseInstallerUrl "zed" "win")),
        @("https://github.com/zed-industries/zed/releases/download/v<ver>/zed-linux-x86_64.tar.gz", (Get-ReleaseInstallerUrl "zed" "linuxTar")),
        @("exe-dir", (Get-ReleaseUninstallType "zed" "win")),
        @("ZedIndustries.Zed", (Get-ReleaseWinget "zed")),
        @("inno", (Get-ReleaseUninstallType "code" "win")),
        @("pkg",  (Get-ReleaseUninstallType "code" "linux")),
        @("unins000.exe", (Get-ReleaseUninstallExe "code")),
        @("code",   (Get-ReleaseUninstallName "code")),
        @("codium", (Get-ReleaseUninstallName "codium")),
        @("Microsoft.VisualStudioCode", (Get-ReleaseWinget "code")),
        @("VSCodium.VSCodium", (Get-ReleaseWinget "codium")),
        @("https://update.code.visualstudio.com/1.133.0/win32-x64-user/stable", (Get-ReleaseUrl "code" "win" "1.133.0"))
    )
    $fail = 0
    foreach ($c in $cases) {
        if ($c[0] -ne $c[1]) {
            Write-Host "FAIL: expected '$($c[0])' got '$($c[1])'"
            $fail = 1
        }
    }
    if ($fail -eq 0) { Write-Host "release selfcheck: OK" }
    return $fail
}

if ($MyInvocation.InvocationName -ne '.') { exit (Test-ReleaseModule) }