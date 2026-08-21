# ============================================================
#  syncode version module (Windows/PowerShell)
#  Compare-Version + Get-InstalledVersion.
#  Dot-sourced by syncode.ps1; self-checks when run directly.
# ============================================================

function Compare-Version($a, $b) {
    if ([string]::IsNullOrEmpty($a) -and [string]::IsNullOrEmpty($b)) { return 0 }
    if ([string]::IsNullOrEmpty($a)) { return -1 }
    if ([string]::IsNullOrEmpty($b)) { return 1 }
    $sa = @($a -split '\.')
    $sb = @($b -split '\.')
    $n = [Math]::Min($sa.Count, $sb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $ia = [int]$sa[$i]; $ib = [int]$sb[$i]
        if ($ia -lt $ib) { return -1 }
        if ($ia -gt $ib) { return 1 }
    }
    if ($sa.Count -lt $sb.Count) { return -1 }
    if ($sa.Count -gt $sb.Count) { return 1 }
    return 0
}

$script:InstalledCache = @{}

function Get-InstalledVersion($fork) {
    if ($script:InstalledCache.ContainsKey($fork)) { return $script:InstalledCache[$fork] }
    $v = ""
    # CLI on PATH first
    $cli = Get-Command -Name $fork -ErrorAction SilentlyContinue
    if ($cli) {
        $v = $null | & $cli.Source --version 2>$null | Select-Object -First 1
        if ($v) { $v = $v.Trim() } else { $v = "" }
    }
    # else resources/app/package.json from known install paths (regex, like the bash port)
    if (-not $v) {
        $paths = @{
            code   = @(
                (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code"),
                (Join-Path ${env:ProgramFiles(x86)} "Microsoft VS Code"),
                (Join-Path $env:ProgramFiles "Microsoft VS Code")
            )
            codium = @(
                (Join-Path $env:LOCALAPPDATA "Programs\VSCodium"),
                (Join-Path ${env:ProgramFiles(x86)} "VSCodium"),
                (Join-Path $env:ProgramFiles "VSCodium")
            )
            zed    = @()
        }
        foreach ($p in $paths[$fork]) {
            $pj = Join-Path $p "resources\app\package.json"
            if (Test-Path $pj) {
                $text = [IO.File]::ReadAllText($pj, [Text.Encoding]::UTF8)
                $m = [regex]::Match($text, '"version"\s*:\s*"([^"]+)"')
                if ($m.Success) { $v = $m.Groups[1].Value; break }
            }
        }
    }
    $script:InstalledCache[$fork] = $v
    return $v
}

function Reset-InstalledCache($fork) { $script:InstalledCache.Remove($fork) | Out-Null }

# ------------------------------------------------------------
#  Self-check (runs only when executed directly, not dot-sourced)
# ------------------------------------------------------------
function Test-VersionModule {
    $cases = @(
        @(-1, '1.126.04524', '1.133.0'),
        @(1,  '1.10.0',      '1.9.0'),
        @(0,  '1.133.0',     '1.133.0'),
        @(0,  '1.126.04524', '1.126.04524'),
        @(-1, '1.126.04524', '1.126.04525'),
        @(-1, '1.133',       '1.133.0'),
        @(1,  '1.133.0',     '1.133'),
        @(-1, '',            '1.0.0'),
        @(1,  '1.0.0',       ''),
        @(0,  '',            '')
    )
    $fail = 0
    foreach ($c in $cases) {
        $got = Compare-Version $c[1] $c[2]
        if ($got -ne $c[0]) {
            Write-Host "FAIL: Compare-Version($($c[1]), $($c[2])) = $got, want $($c[0])"
            $fail = 1
        }
    }
    if ($fail -eq 0) { Write-Host "version selfcheck: OK" }
    return $fail
}

if ($MyInvocation.InvocationName -ne '.') { exit (Test-VersionModule) }