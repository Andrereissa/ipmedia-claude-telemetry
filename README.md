# ipmedia-claude-telemetry

Public one-click installer to enable Claude Code OpenTelemetry on macOS, Linux,
and Windows. Points Claude Code at the IPMedia monitoring stack at
`https://claude-roi.ipmedia.com.br`.

The script writes a `managed-settings.json` with the OTel env vars Claude Code
reads at startup. Token is provided at install time (env var or interactive
prompt) and is never committed anywhere.

| Pinned artifact | Tag | SHA256 |
|---|---|---|
| `install-telemetry.sh` (macOS/Linux) | `v3` | `cb53ddffa475add9fe5f6960e73e64f2724763ae8794cd3205b420677e2ea2ae` |
| `install-telemetry.ps1` (Windows) | `v3` | `b3e77bea643693cf21da49b8886cbaccf89bdebe675885e89d9e084f0bd659eb` |

## Install — macOS / Linux

You need:

- macOS or Linux
- `python3` (used to JSON-encode the token safely)
- The **OTLP token** — ask the IPMedia admin

### Recommended (token via interactive prompt — never enters shell history)

```bash
REF=v3
SHA256=cb53ddffa475add9fe5f6960e73e64f2724763ae8794cd3205b420677e2ea2ae

curl -fsSLO "https://raw.githubusercontent.com/Andrereissa/ipmedia-claude-telemetry/${REF}/install-telemetry.sh"
echo "${SHA256}  install-telemetry.sh" | shasum -a 256 -c -
chmod +x install-telemetry.sh
sudo ./install-telemetry.sh
```

> On Linux, if `shasum` is missing use `sha256sum -c -` instead.

The script will prompt:

```
OTLP token: <hidden input>
```

After install, **restart Claude Code** (close all windows and reopen).

### CI / fleet (token via env var)

```bash
sudo OTLP_TOKEN='<token>' ./install-telemetry.sh
```

## Install — Windows

You need:

- Windows 10 1803+ (ships `curl.exe`, used for the connectivity test)
- An **elevated PowerShell** (Run as Administrator)
- The **OTLP token** — ask the IPMedia admin

### Recommended (token via interactive prompt)

Open PowerShell **as Administrator**, then:

```powershell
$ref = 'v3'
$sha = 'b3e77bea643693cf21da49b8886cbaccf89bdebe675885e89d9e084f0bd659eb'

Invoke-WebRequest -UseBasicParsing `
  -Uri "https://raw.githubusercontent.com/Andrereissa/ipmedia-claude-telemetry/$ref/install-telemetry.ps1" `
  -OutFile install-telemetry.ps1
if ((Get-FileHash -Algorithm SHA256 install-telemetry.ps1).Hash -ne $sha.ToUpper()) {
  throw "checksum mismatch - do not run"
}
powershell -ExecutionPolicy Bypass -File .\install-telemetry.ps1
```

The script prompts `OTLP token:` (hidden), writes
`%ProgramData%\ClaudeCode\managed-settings.json`, resets its ACL so it inherits
the ProgramData default (Administrators+SYSTEM full, Users read), and tests
connectivity. **Restart Claude Code** after it finishes.

### CI / fleet (token via env var)

```powershell
$env:OTLP_TOKEN = '<token>'; .\install-telemetry.ps1
```

## Verify

```bash
# macOS
sudo grep OTEL_EXPORTER_OTLP_ENDPOINT "/Library/Application Support/ClaudeCode/managed-settings.json"

# Linux
sudo grep OTEL_EXPORTER_OTLP_ENDPOINT /etc/claude-code/managed-settings.json
```

```powershell
# Windows
Get-Content "$env:ProgramData\ClaudeCode\managed-settings.json" | Select-String OTEL_EXPORTER_OTLP_ENDPOINT
```

Should print the line containing `https://claude-roi.ipmedia.com.br`. Data
appears in the dashboard within ~60 s of restarting Claude Code.

## Uninstall

```bash
# macOS
sudo rm "/Library/Application Support/ClaudeCode/managed-settings.json"

# Linux
sudo rm /etc/claude-code/managed-settings.json
```

```powershell
# Windows (elevated)
Remove-Item "$env:ProgramData\ClaudeCode\managed-settings.json"
```

Restart Claude Code to take effect.

## What gets captured

The team monitoring captures: your email (via OAuth), prompt text, tool
inputs, and tool outputs (truncated at 60 KB in trace spans).

It does **not** capture: Claude's response text, local env vars, or file
contents you don't pass to Claude.

## Security notes

- `managed-settings.json` must be readable by the **non-privileged user** that
  runs Claude Code — it cannot be locked to root/admin only, or Claude Code
  never sees it and the telemetry config silently never applies. So:
  - **macOS/Linux:** `root`-owned, mode `0644` (world-readable).
  - **Windows:** ACL reset to inherit ProgramData's default (Administrators +
    SYSTEM full, Users read).
  The price is the same on all three: the bearer token in this file is readable
  by any local user — treat every installed machine as having the shared OTLP
  token exposed locally.
- The script verifies a real OTLP POST to `/v1/traces` after install — fails
  loudly on bad token, network, or stack misconfiguration.
- Always pin `REF` to a tag (or a commit SHA) and check the `SHA256` so a
  future repo compromise can't push malicious code into your install command.

## Differences from upstream

This is a public mirror of the installer maintained internally in
`meupatrocinio/team-ai-infra/monitoring/scripts/install-telemetry.sh` (private).
Changes:

- macOS ownership: `root:wheel` (Darwin has no `root` group; upstream's
  `chown root:root` fails there).
- Mode `0644` instead of `0600` so Claude Code (running as the user) can read
  the policy file. See Security notes for the tradeoff.
- Added `install-telemetry.ps1` for Windows (writes to `%ProgramData%`, resets
  ACL to inherit the ProgramData default). Not present upstream.
- URL in the curl-pipe usage comment points to this public repo.
