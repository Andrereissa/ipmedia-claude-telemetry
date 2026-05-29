<#
.SYNOPSIS
  Claude Code Monitoring - One-Click Telemetry Installer (Windows)

.DESCRIPTION
  Enables Claude Code to send metrics, events, and traces to the team
  monitoring stack at https://claude-roi.ipmedia.com.br

  Writes %ProgramData%\ClaudeCode\managed-settings.json with the OTel env
  vars Claude Code reads at startup, then resets the file ACL so it inherits
  ProgramData's default (Administrators+SYSTEM full, Users read) - readable by
  the non-admin user that runs Claude Code.

.EXAMPLE
  # Interactive prompt (most secure - token never enters history)
  powershell -ExecutionPolicy Bypass -File .\install-telemetry.ps1

.EXAMPLE
  # Env var (CI / fleet)
  $env:OTLP_TOKEN = '<token>'; .\install-telemetry.ps1

.NOTES
  Must run in an elevated PowerShell (Run as Administrator).
  Requires curl.exe (ships with Windows 10 1803+).
#>

[CmdletBinding()]
param(
    [string]$Token = $env:OTLP_TOKEN
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Endpoint     = 'https://claude-roi.ipmedia.com.br'
$SettingsDir  = Join-Path $env:ProgramData 'ClaudeCode'
$SettingsFile = Join-Path $SettingsDir 'managed-settings.json'

# Require elevation: we write under ProgramData and reset its ACL.
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run this in an elevated PowerShell (Run as Administrator)."
    exit 1
}

# Resolve token: param/env var -> interactive hidden prompt.
if ([string]::IsNullOrEmpty($Token)) {
    $secure = Read-Host -AsSecureString "OTLP token"
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
if ([string]::IsNullOrEmpty($Token)) {
    Write-Error ("OTLP token required. Get it from your team admin or AWS SSM " +
        "/monitoring/otlp-auth-token (region us-east-2, profile ipmedia-ai).")
    exit 1
}

Write-Host "Installing Claude Code telemetry config..."
Write-Host "  Endpoint: $Endpoint"
Write-Host "  Settings: $SettingsFile"
Write-Host ""

# Build the settings object. ConvertTo-Json escapes the token safely (no
# python3 needed as on Unix); [ordered] keeps the keys in a stable order.
$settings = [ordered]@{
    env = [ordered]@{
        CLAUDE_CODE_ENABLE_TELEMETRY        = '1'
        OTEL_METRICS_EXPORTER               = 'otlp'
        OTEL_LOGS_EXPORTER                  = 'otlp'
        OTEL_TRACES_EXPORTER                = 'otlp'
        OTEL_EXPORTER_OTLP_PROTOCOL         = 'http/protobuf'
        OTEL_EXPORTER_OTLP_ENDPOINT         = $Endpoint
        OTEL_EXPORTER_OTLP_HEADERS          = "Authorization=Bearer $Token"
        OTEL_LOG_USER_PROMPTS               = '1'
        OTEL_LOG_TOOL_DETAILS               = '1'
        CLAUDE_CODE_ENHANCED_TELEMETRY_BETA = '1'
        OTEL_LOG_TOOL_CONTENT               = '1'
    }
}

New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null

# Write UTF-8 without BOM (Claude Code expects plain UTF-8 JSON).
$json = $settings | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($SettingsFile, $json,
    (New-Object System.Text.UTF8Encoding($false)))

# Reset ACL -> inherit ProgramData default (Admins+SYSTEM full, Users read).
# This is the Windows equivalent of 0644 on Unix: readable by the non-admin
# user running Claude Code. Tradeoff: the bearer token is readable locally.
& icacls "$SettingsFile" /reset | Out-Null

# Verify the endpoint is reachable (real OTLP POST, mirrors the bash installer).
Write-Host "Testing connection to $Endpoint..."
$code = & curl.exe -sS -o NUL -w "%{http_code}" `
    -X POST "$Endpoint/v1/traces" `
    -H "Authorization: Bearer $Token" `
    -H "Content-Type: application/x-protobuf" `
    --data-binary "" `
    --connect-timeout 5 --max-time 10
if ($LASTEXITCODE -ne 0) { $code = "000" }

if ($code -match '^2\d\d$') {
    Write-Host "  Connection: OK ($code)"
} else {
    Write-Host "  Connection: FAILED (HTTP $code)"
    Write-Host "  Check the token or your network."
    exit 1
}

Write-Host ""
Write-Host "Done! Restart Claude Code (close and reopen) to start sending telemetry."
Write-Host ""
Write-Host "View dashboards at: $Endpoint"
