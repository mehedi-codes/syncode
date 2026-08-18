# Runs under BOTH PowerShell 5.1 and 7 (CI invokes this via -File).
# 1. Parse-checks the ps1 sources (5.1 catches what pwsh 7 misses).
# 2. Enforces ASCII-only source (5.1 reads BOM-less files as ANSI, so
#    non-ASCII chars corrupt string literals and break parsing).
$files = @('windows/syncode.ps1', 'windows/release.ps1')
foreach ($f in $files) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
    if ($errors.Count) {
        $errors | ForEach-Object { Write-Host ("{0} line {1}: {2}" -f $f, $_.Extent.StartLineNumber, $_.Message) }
        exit 1
    }
}
foreach ($f in $files) {
    foreach ($ch in ([IO.File]::ReadAllText($f)).ToCharArray()) {
        if ([int]$ch -gt 127) { Write-Host "non-ASCII char in $f (breaks 5.1)"; exit 1 }
    }
}
Write-Host "ps parse + ASCII check OK (engine $($PSVersionTable.PSVersion))"