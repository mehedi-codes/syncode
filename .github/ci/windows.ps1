# CI checks for the Windows port. Run under BOTH PowerShell 5.1 and 7:
#   pwsh -NoProfile -File .github/ci/windows.ps1
#   powershell.exe -NoProfile -File .github/ci/windows.ps1
#
# Runs syncode.ps1 as a CHILD process (it calls exit on many paths) using the
# engine this script runs under, so each invocation tests the matching engine.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot | Split-Path -Parent  # .github/ci -> repo root
Set-Location $root

Write-Host "== ps parse + ASCII check =="
$psFiles = @('windows/syncode.ps1', 'windows/release.ps1')
foreach ($f in $psFiles) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
    if ($errors.Count) {
        $errors | ForEach-Object { Write-Host ("{0} line {1}: {2}" -f $f, $_.Extent.StartLineNumber, $_.Message) }
        exit 1
    }
}
# ASCII-only across ALL tool scripts: ps1 must stay ASCII (5.1 reads BOM-less
# files as ANSI) and bash must match ps1 byte-for-byte in output (lockstep).
$asciiFiles = @('windows/syncode.ps1', 'windows/release.ps1', 'windows/version.ps1',
                'linux/syncode.sh', 'linux/release.sh', 'linux/version.sh',
                'install.ps1', 'install.sh')
foreach ($f in $asciiFiles) {
    foreach ($ch in ([IO.File]::ReadAllText($f)).ToCharArray()) {
        if ([int]$ch -gt 127) { Write-Host "non-ASCII char in $f (breaks 5.1 / port lockstep)"; exit 1 }
    }
}
Write-Host "ps parse + ASCII check OK"

# Engine to run syncode.ps1 under (matches this script's engine)
if ($PSVersionTable.PSVersion.Major -ge 7) { $engine = "pwsh" } else { $engine = "powershell.exe" }

function Invoke-DryRun([string]$scriptPath) {
    $out = & $engine -NoProfile -File $scriptPath -d 2>&1 | Out-String
    Write-Host $out
    if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: dry-run exit $LASTEXITCODE"; exit 1 }
    return $out
}

Write-Host "== sandbox dry-run (checkout layout, ../shared configs) =="
$sandbox = Join-Path $env:TEMP "ci-sandbox-checkout"
if (Test-Path $sandbox) { Remove-Item $sandbox -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $sandbox "Code\User"), (Join-Path $sandbox "VSCodium\User"), (Join-Path $sandbox "bin") | Out-Null
@'
@echo off
if "%1"=="--version" echo 1.2.3
if "%1"=="--list-extensions" echo aaron-bond.better-comments & echo editorconfig.editorconfig
'@ | Set-Content (Join-Path $sandbox "bin\code.cmd") -Encoding ascii
Copy-Item (Join-Path $sandbox "bin\code.cmd") (Join-Path $sandbox "bin\codium.cmd")
Copy-Item shared/settings.json (Join-Path $sandbox "Code\User\settings.json")
'{"workbench.colorTheme":"Not Synced"}' | Set-Content (Join-Path $sandbox "VSCodium\User\settings.json") -Encoding ascii
$env:APPDATA = $sandbox
$env:Path = (Join-Path $sandbox "bin") + ";" + $env:Path
$out = Invoke-DryRun "windows/syncode.ps1"
if ($out -notmatch "settings already in sync") { Write-Host "FAIL: missing 'settings already in sync'"; exit 1 }
if ($out -notmatch "copy settings") { Write-Host "FAIL: missing 'copy settings'"; exit 1 }
if ($out -notmatch "DRY RUN") { Write-Host "FAIL: missing 'DRY RUN'"; exit 1 }
Remove-Item $sandbox -Recurse -Force

Write-Host "== sandbox dry-run (flattened install layout, beside-script configs) =="
$sandbox = Join-Path $env:TEMP "ci-sandbox-flat"
if (Test-Path $sandbox) { Remove-Item $sandbox -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $sandbox "Code\User"), (Join-Path $sandbox "bin") | Out-Null
Copy-Item windows/syncode.ps1, windows/version.ps1, windows/release.ps1, shared/settings.json, shared/extensions.json, shared/releases.json $sandbox
@'
@echo off
if "%1"=="--version" echo 1.2.3
if "%1"=="--list-extensions" echo aaron-bond.better-comments
'@ | Set-Content (Join-Path $sandbox "bin\code.cmd") -Encoding ascii
Copy-Item (Join-Path $sandbox "bin\code.cmd") (Join-Path $sandbox "bin\codium.cmd")
$env:APPDATA = $sandbox
$env:Path = (Join-Path $sandbox "bin") + ";" + $env:Path
$out = Invoke-DryRun (Join-Path $sandbox "syncode.ps1")
if ($out -notmatch "DRY RUN") { Write-Host "FAIL: missing 'DRY RUN'"; exit 1 }
Remove-Item $sandbox -Recurse -Force

Write-Host "ALL WINDOWS CHECKS PASSED"