# Deploy via Hexnode MDM

Ready-to-paste Hexnode policy bodies that auto-install the Claude Code
telemetry config on every enrolled laptop (macOS, Windows, Linux).

All three snippets pull a pinned, SHA256-verified copy of the installer from
this repo and run it with `SKIP_CONN_TEST=1` — the laptop may have no network
at the exact moment of policy execution, but the `managed-settings.json` is
still written and telemetry starts flowing on the next Claude Code launch
with network.

## Before you start

- Get the OTLP token from AWS SSM:
  ```bash
  aws ssm get-parameter --name /monitoring/otlp-auth-token \
    --with-decryption --query Parameter.Value --output text \
    --region us-east-2 --profile ipmedia-ai
  ```
- Decide policy scope per OS (macOS / Windows / Linux device groups).
- Decide execution cadence — **one-time on enrollment** is the right default.
  `managed-settings.json` is the same file every time; re-running on every
  reboot just overwrites it identically and adds noise to logs.

## Pinning

The snippets below pin the current tag and check the SHA256. After cutting a
new tag in this repo, update both `REF` and `SHA256` in the policy body —
otherwise the SHA check fails and the policy errors out (intended: a SHA
mismatch means the script changed underneath you, and you want to review
before deploying).

| Artifact | Tag | SHA256 |
|---|---|---|
| `install-telemetry.sh` | `v7` | `62a70abb861cd94bbe81a8281cfd77ab02a07c99618b23b10dcb95646c0a11e9` |
| `install-telemetry.ps1` | `v6` | `5b0e717d002da686df5f5639fb471f71dd0b5418ed3e0c414eae644aec43c3b4` |

`v7` bumps the shell installer to derive a `machine.id` from the computer
name and inject it into `OTEL_RESOURCE_ATTRIBUTES`, so shared Claude accounts
split per device in the dashboard. The PowerShell installer is unchanged and
stays pinned at `v6`.

## macOS — Hexnode "Execute Custom Script"

**Policy type:** Scripts → macOS → Execute Custom Script
**Run as:** Root (default)
**Execution:** Once per device

**Pre-requisite policy:** Xcode Command Line Tools must be installed first
(provides `python3` and `curl`). Hexnode supports this with an "Install Package
/ Run Custom Script" policy — apply it to the same device group with a higher
priority than this one.

Paste this into the policy body, replacing `<OTLP_TOKEN_HERE>`:

```bash
#!/bin/bash
set -euo pipefail

REF=v7
SHA256=62a70abb861cd94bbe81a8281cfd77ab02a07c99618b23b10dcb95646c0a11e9
URL="https://raw.githubusercontent.com/Andrereissa/ipmedia-claude-telemetry/${REF}/install-telemetry.sh"

TMP=$(mktemp -t install-telemetry.XXXXXX.sh)
trap 'rm -f "$TMP"' EXIT

curl -fsSL "$URL" -o "$TMP"
echo "${SHA256}  ${TMP}" | shasum -a 256 -c -

chmod +x "$TMP"
OTLP_TOKEN='<OTLP_TOKEN_HERE>' SKIP_CONN_TEST=1 "$TMP"
```

## Linux — Hexnode "Execute Custom Script"

**Policy type:** Scripts → Linux → Execute Custom Script
**Run as:** Root
**Execution:** Once per device
**Supported distros:** Ubuntu / Debian (per Hexnode Linux MDM scope as of 2026)

`python3` and `curl` ship by default on Ubuntu/Debian, so no pre-req policy
is needed. The body is identical to macOS except `shasum` → `sha256sum`:

```bash
#!/bin/bash
set -euo pipefail

REF=v7
SHA256=62a70abb861cd94bbe81a8281cfd77ab02a07c99618b23b10dcb95646c0a11e9
URL="https://raw.githubusercontent.com/Andrereissa/ipmedia-claude-telemetry/${REF}/install-telemetry.sh"

TMP=$(mktemp -t install-telemetry.XXXXXX.sh)
trap 'rm -f "$TMP"' EXIT

curl -fsSL "$URL" -o "$TMP"
echo "${SHA256}  ${TMP}" | sha256sum -c -

chmod +x "$TMP"
OTLP_TOKEN='<OTLP_TOKEN_HERE>' SKIP_CONN_TEST=1 "$TMP"
```

## Windows — Hexnode "Execute Custom Script"

**Policy type:** Scripts → Windows → Execute Custom Script
**Run as:** System (default — equivalent to elevated)
**Execution:** Once per device

PowerShell 5.1 ships with Windows 10/11, so no pre-req policy is needed.

```powershell
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ref = 'v6'
$sha = '5b0e717d002da686df5f5639fb471f71dd0b5418ed3e0c414eae644aec43c3b4'
$url = "https://raw.githubusercontent.com/Andrereissa/ipmedia-claude-telemetry/$ref/install-telemetry.ps1"

$tmp = Join-Path $env:TEMP "install-telemetry-$([guid]::NewGuid()).ps1"
try {
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp
    if ((Get-FileHash -Algorithm SHA256 $tmp).Hash -ne $sha.ToUpper()) {
        throw "checksum mismatch - aborting"
    }
    $env:OTLP_TOKEN     = '<OTLP_TOKEN_HERE>'
    $env:SKIP_CONN_TEST = '1'
    powershell -ExecutionPolicy Bypass -File $tmp
} finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}
```

## Notes & tradeoffs

- **Token is plaintext in the policy body.** Hexnode does not have a real
  secrets store for script env vars — any Hexnode admin who can view the policy
  can read the token. This is the same exposure model as the installed
  `managed-settings.json` (any local user reads it), so it's not net-new risk,
  but it does mean rotating the token requires updating each policy body.
- **Skipping the connectivity probe is a deliberate tradeoff.** Without it,
  laptops enrolled with no network at policy run time would fail the policy
  and would need a manual retry. With it, the file is written and Claude Code
  picks it up next launch, but a bad token or misconfigured stack won't be
  caught at install time — it'll just show up as "no data in dashboard"
  later. Pair the rollout with running `verify-telemetry.sh` on a few devices
  after enrollment, or have devs run it themselves.
- **Re-running is idempotent.** The script overwrites `managed-settings.json`
  with the same contents; no harm in running it more than once. So if you
  switch to repeating execution later (e.g. weekly) for self-healing, that
  works — it just adds log noise.
- **Token rotation** requires updating the policy body and re-running it on
  enrolled devices (or waiting for the next cycle, if you set it to repeat).
