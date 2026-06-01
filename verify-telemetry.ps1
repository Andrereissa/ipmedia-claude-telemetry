<#
.SYNOPSIS
  Claude Code Monitoring - Telemetry diagnostic (Windows)

.DESCRIPTION
  Reads the installed %ProgramData%\ClaudeCode\managed-settings.json,
  extracts the endpoint and token, and runs the same OTLP /v1/traces probe
  the installer does. Useful when a dev reports "telemetry doesn't show up" -
  tells you whether the file is missing, unreadable by the user, or the
  backend is unreachable.

  Run AS YOUR NORMAL USER (not elevated) - the whole point is to verify that
  Claude Code (which runs as your user, not Administrator) can read the file.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\verify-telemetry.ps1
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$SettingsFile = Join-Path $env:ProgramData 'ClaudeCode\managed-settings.json'

if (-not (Test-Path $SettingsFile)) {
    Write-Host "NOT INSTALLED: $SettingsFile does not exist."
    Write-Host "Run install-telemetry.ps1 (elevated)."
    exit 1
}

# Test that *this* user can read it (mirrors what Claude Code does).
try {
    $cfg = Get-Content $SettingsFile -Raw -ErrorAction Stop | ConvertFrom-Json
} catch [System.UnauthorizedAccessException] {
    Write-Host "BROKEN INSTALL: $SettingsFile exists but you ($env:USERNAME) can't read it."
    Write-Host "Claude Code (which runs as your user) can't read it either -- "
    Write-Host "telemetry silently never applies. Reinstall with v4+ (resets ACL via icacls)."
    exit 1
} catch {
    Write-Host "ERROR: Failed to parse $SettingsFile : $($_.Exception.Message)"
    exit 1
}

$endpoint = $cfg.env.OTEL_EXPORTER_OTLP_ENDPOINT
$token    = ($cfg.env.OTEL_EXPORTER_OTLP_HEADERS -split 'Bearer ', 2)[1]

if (-not $endpoint -or -not $token) {
    Write-Host "BROKEN CONFIG: endpoint or token missing in $SettingsFile."
    exit 1
}

Write-Host "Endpoint: $endpoint"
Write-Host "Token:    $($token.Length) chars loaded from $SettingsFile"
Write-Host "Testing connection..."

$code = 0
try {
    $resp = Invoke-WebRequest -Uri "$endpoint/v1/traces" -Method Post `
        -Headers @{ Authorization = "Bearer $token" } `
        -ContentType 'application/x-protobuf' `
        -Body ([byte[]]::new(0)) `
        -TimeoutSec 10 -UseBasicParsing
    $code = [int]$resp.StatusCode
} catch {
    $r = $_.Exception.Response
    if ($r -and $r.StatusCode) { $code = [int]$r.StatusCode } else { $code = 0 }
}

if ($code -ge 200 -and $code -lt 300) {
    Write-Host "Connection: OK ($code)"
    exit 0
} else {
    Write-Host "Connection: FAILED (HTTP $code)"
    switch -Regex ($code.ToString()) {
        '^(401|403)$' { Write-Host "  -> Token rejected. Reinstall with the correct token." }
        '^0$'         { Write-Host "  -> Network/DNS/firewall blocking $endpoint." }
        default       { Write-Host "  -> Backend returned an unexpected status." }
    }
    exit 1
}
