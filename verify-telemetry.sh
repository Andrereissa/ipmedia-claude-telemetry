#!/usr/bin/env bash
# Claude Code Monitoring - Telemetry diagnostic (macOS/Linux)
#
# Reads the installed managed-settings.json, extracts the endpoint and token
# from it, and runs the same OTLP /v1/traces probe the installer does. Useful
# when a dev reports "telemetry doesn't show up" - tells you whether the file
# is missing, unreadable by your user, or the backend is unreachable.
#
# Run AS YOUR NORMAL USER (not sudo) - the whole point is to verify that
# Claude Code (which runs as your user) can read the file.

set -euo pipefail

case "$(uname -s)" in
  Linux*)   SETTINGS_FILE="/etc/claude-code/managed-settings.json" ;;
  Darwin*)  SETTINGS_FILE="/Library/Application Support/ClaudeCode/managed-settings.json" ;;
  *) echo "ERROR: Unsupported OS"; exit 1 ;;
esac

if [ ! -e "$SETTINGS_FILE" ]; then
    echo "NOT INSTALLED: $SETTINGS_FILE does not exist."
    echo "Run install-telemetry.sh."
    exit 1
fi

if [ ! -r "$SETTINGS_FILE" ]; then
    echo "BROKEN INSTALL: $SETTINGS_FILE exists but is not readable by you ($(id -un))."
    echo "Claude Code (which runs as your user, not root) can't read it either -- "
    echo "telemetry silently never applies. Reinstall with v2 or newer (mode 0644)."
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required to parse the config."
    exit 1
fi

ENDPOINT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["env"]["OTEL_EXPORTER_OTLP_ENDPOINT"])' "$SETTINGS_FILE")
TOKEN=$(python3 -c 'import json,sys; h=json.load(open(sys.argv[1]))["env"]["OTEL_EXPORTER_OTLP_HEADERS"]; print(h.split("Bearer ",1)[1])' "$SETTINGS_FILE")

echo "Endpoint: $ENDPOINT"
echo "Token:    ${#TOKEN} chars loaded from $SETTINGS_FILE"
echo "Testing connection..."

HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
    -X POST "$ENDPOINT/v1/traces" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/x-protobuf" \
    --data-binary '' \
    --connect-timeout 5 --max-time 10 || echo "000")

if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
    echo "Connection: OK ($HTTP_CODE)"
    exit 0
else
    echo "Connection: FAILED (HTTP $HTTP_CODE)"
    case "$HTTP_CODE" in
      401|403) echo "  -> Token rejected. Reinstall with the correct token." ;;
      000)     echo "  -> Network/DNS/firewall blocking $ENDPOINT." ;;
      *)       echo "  -> Backend returned an unexpected status." ;;
    esac
    exit 1
fi
