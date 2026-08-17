# ============================================================
#  install.ps1 - syncode one-time runner (Windows / PowerShell)
#  Fetches the latest syncode.ps1 + config via Invoke-WebRequest
#  (no git, no cache) and runs it immediately from a temp dir.
#  Version: 1.0.0
# ============================================================
param(
    [Alias('h')][switch]$Help,
    [Alias('v')][switch]$Version,
    [Alias('d')][switch]$DryRun,
    [Alias('r')][switch]$Revert
)

$ErrorActionPreference = "Stop"

$REPO_RAW = "https://raw.githubusercontent.com/mehedi-codes/syncode/main"
# src-path -> flat dst (syncode.ps1 expects configs beside it in the temp dir)
$FILES = @(
    @{ Src = "src/windows/syncode.ps1";      Dst = "syncode.ps1" },
    @{ Src = "src/shared/settings.json";     Dst = "settings.json" },
    @{ Src = "src/shared/extensions.json";   Dst = "extensions.json" }
)

# TLS 1.2+ required for GitHub on Windows PowerShell 5.1 (defaults to TLS 1.0)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$tmp = Join-Path ([IO.Path]::GetTempPath()) (".syncode." + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    foreach ($f in $FILES) {
        Invoke-WebRequest -Uri "$REPO_RAW/$($f.Src)" -OutFile (Join-Path $tmp $f.Dst) -UseBasicParsing
    }

    # pass flags through to syncode.ps1
    $psb = @{}
    if ($Help)    { $psb.Help = $true }
    if ($Version) { $psb.Version = $true }
    if ($DryRun)  { $psb.DryRun = $true }
    if ($Revert)  { $psb.Revert = $true }

    & (Join-Path $tmp "syncode.ps1") @psb
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}