# ipmedia-claude-telemetry

Public one-click installer to enable Claude Code OpenTelemetry on macOS and
Linux. Points Claude Code at the IPMedia monitoring stack at
`https://claude-roi.ipmedia.com.br`.

The script writes a `managed-settings.json` with the OTel env vars Claude Code
reads at startup. Token is provided at install time (env var or interactive
prompt) and is never committed anywhere.

## Install

You need:

- macOS or Linux
- `python3` (used to JSON-encode the token safely)
- The **OTLP token** — ask the IPMedia admin

### Recommended (token via interactive prompt — never enters shell history)

```bash
REF=v1
SHA256=d8e4a9b8f47bb2214b11139a979c71517d2205b2f34ae8098d0328343d31409a

curl -fsSLO "https://raw.githubusercontent.com/Andrereissa/ipmedia-claude-telemetry/${REF}/install-telemetry.sh"
echo "${SHA256}  install-telemetry.sh" | shasum -a 256 -c -
chmod +x install-telemetry.sh
sudo ./install-telemetry.sh
```

The script will prompt:

```
OTLP token: <hidden input>
```

After install, **restart Claude Code** (close all windows and reopen).

### CI / fleet (token via env var)

```bash
sudo OTLP_TOKEN='<token>' ./install-telemetry.sh
```

## Verify

```bash
# macOS
sudo grep OTEL_EXPORTER_OTLP_ENDPOINT "/Library/Application Support/ClaudeCode/managed-settings.json"

# Linux
sudo grep OTEL_EXPORTER_OTLP_ENDPOINT /etc/claude-code/managed-settings.json
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

Restart Claude Code to take effect.

## What gets captured

The team monitoring captures: your email (via OAuth), prompt text, tool
inputs, and tool outputs (truncated at 60 KB in trace spans).

It does **not** capture: Claude's response text, local env vars, or file
contents you don't pass to Claude.

## Security notes

- The bearer token is stored in `managed-settings.json` with mode `0600`
  (root-only readable).
- The script verifies a real OTLP POST to `/v1/traces` after install — fails
  loudly on bad token, network, or stack misconfiguration.
- Always pin `REF` to a tag (or a commit SHA) and check the `SHA256` so a
  future repo compromise can't push malicious code into your install command.

## Differences from upstream

This is a public mirror of the installer maintained internally in
`meupatrocinio/team-ai-infra/monitoring/scripts/install-telemetry.sh` (private).
Changes:

- `chown root:root` → `chown root:` so it works on macOS (no `root` group on
  Darwin, just `wheel`).
- URL in the curl-pipe usage comment points to this public repo.
