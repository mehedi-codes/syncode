# ============================================================
#  install.ps1 - syncode one-time runner (Windows / PowerShell)
#  Fetches the latest syncode.ps1 + config via Invoke-WebRequest
#  (no git, no cache) and runs it immediately from a temp dir.
#  Version: 1.3.0
# ============================================================
$ErrorActionPreference = "Stop"

$REPO_RAW = "https://raw.githubusercontent.com/mehedi-codes/syncode/main"
# src-path -> flat dst (syncode.ps1 expects <editor>\settings.json beside it
# in the temp dir)
$FILES = @(
    @{ Src = "windows/syncode.ps1";        Dst = "syncode.ps1" },
    @{ Src = "windows/version.ps1";        Dst = "version.ps1" },
    @{ Src = "windows/release.ps1";        Dst = "release.ps1" },
    @{ Src = "shared/code/settings.json";  Dst = "code\settings.json" },
    @{ Src = "shared/code/extensions.json"; Dst = "code\extensions.json" },
    @{ Src = "shared/codium/settings.json"; Dst = "codium\settings.json" },
    @{ Src = "shared/codium/extensions.json"; Dst = "codium\extensions.json" },
    @{ Src = "shared/zed/settings.json";   Dst = "zed\settings.json" },
    @{ Src = "shared/zed/extensions.json"; Dst = "zed\extensions.json" },
    @{ Src = "shared/releases.json";       Dst = "releases.json" }
)

# TLS 1.2+ required for GitHub on Windows PowerShell 5.1 (defaults to TLS 1.0)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$tmp = Join-Path ([IO.Path]::GetTempPath()) (".syncode." + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp | Out-Null
foreach ($d in @("code", "codium", "zed")) {
    New-Item -ItemType Directory -Path (Join-Path $tmp $d) | Out-Null
}

try {
    foreach ($f in $FILES) {
        Invoke-WebRequest -Uri "$REPO_RAW/$($f.Src)" -OutFile (Join-Path $tmp $f.Dst) -UseBasicParsing
    }

    & (Join-Path $tmp "syncode.ps1")
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}