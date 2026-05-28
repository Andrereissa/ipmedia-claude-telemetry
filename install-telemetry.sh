#!/usr/bin/env bash
# Claude Code Monitoring — One-Click Telemetry Installer
#
# Enables Claude Code to send metrics, events, and traces to the team
# monitoring stack at https://claude-roi.ipmedia.com.br
#
# Usage (most secure — interactive prompt):
#   ./install-telemetry.sh
#
# Usage (env var, recommended for CI):
#   OTLP_TOKEN=<token> ./install-telemetry.sh
#
# Usage (positional arg, leaks into shell history — avoid if possible):
#   ./install-telemetry.sh <OTLP_TOKEN>
#
# Usage (curl pipe):
#   OTLP_TOKEN=<token> bash -c "$(curl -fsSL https://raw.githubusercontent.com/Andrereissa/ipmedia-claude-telemetry/main/install-telemetry.sh)"

set -euo pipefail

ENDPOINT="https://claude-roi.ipmedia.com.br"

# Resolve token: env var → positional arg → interactive prompt
TOKEN="${OTLP_TOKEN:-${1:-}}"

if [ -z "$TOKEN" ] && [ -t 0 ]; then
  read -rsp "OTLP token: " TOKEN
  echo ""
fi

if [ -z "$TOKEN" ]; then
  echo "ERROR: OTLP token required."
  echo ""
  echo "Get the token from your team admin or run:"
  echo "  aws ssm get-parameter --name /monitoring/otlp-auth-token \\"
  echo "    --with-decryption --query Parameter.Value --output text \\"
  echo "    --region us-east-2 --profile ipmedia-ai"
  echo ""
  echo "Then run: OTLP_TOKEN=<token> $0"
  exit 1
fi

# Detect OS and pick managed settings path + the OS-typical owner group
case "$(uname -s)" in
  Linux*)   SETTINGS_DIR="/etc/claude-code";                        OWNER="root:root" ;;
  Darwin*)  SETTINGS_DIR="/Library/Application Support/ClaudeCode";  OWNER="root:wheel" ;;
  *)
    echo "ERROR: Unsupported OS. For Windows, see DEPLOY.md"
    exit 1
    ;;
esac

SETTINGS_FILE="$SETTINGS_DIR/managed-settings.json"

echo "Installing Claude Code telemetry config..."
echo "  Endpoint: $ENDPOINT"
echo "  Settings: $SETTINGS_FILE"
echo ""

# JSON-encode the token to handle quotes, backslashes, newlines safely.
# Strips the surrounding quotes from the JSON string so it can be embedded inline.
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required to safely encode the token."
  echo "Install python3 (e.g. 'sudo apt install python3' or 'brew install python3') and re-run."
  exit 1
fi
TOKEN_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1])[1:-1])' "$TOKEN")

# Create directory and file (requires sudo)
sudo mkdir -p "$SETTINGS_DIR"
sudo tee "$SETTINGS_FILE" > /dev/null <<EOF
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_TRACES_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "$ENDPOINT",
    "OTEL_EXPORTER_OTLP_HEADERS": "Authorization=Bearer $TOKEN_JSON",
    "OTEL_LOG_USER_PROMPTS": "1",
    "OTEL_LOG_TOOL_DETAILS": "1",
    "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA": "1",
    "OTEL_LOG_TOOL_CONTENT": "1"
  }
}
EOF

# Owner = root (so a normal user can't tamper with the policy file), but mode
# 0644 so the NON-root user that runs Claude Code can READ it. A 0600 root file
# is invisible to Claude Code (it runs as the user, not root) and the telemetry
# config silently never applies.
# Tradeoff: the bearer token in this file is readable by any local user.
sudo chown "$OWNER" "$SETTINGS_FILE"
sudo chmod 0644 "$SETTINGS_FILE"

# Verify the endpoint is reachable (real OTLP POST, not HEAD)
echo "Testing connection to $ENDPOINT..."
HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
  -X POST "$ENDPOINT/v1/traces" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/x-protobuf" \
  --data-binary '' \
  --connect-timeout 5 \
  --max-time 10 || echo "000")

if [[ "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
  echo "  Connection: OK ($HTTP_CODE)"
else
  echo "  Connection: FAILED (HTTP $HTTP_CODE)"
  echo "  Check the token or your network."
  exit 1
fi

echo ""
echo "Done! Restart Claude Code (close and reopen) to start sending telemetry."
echo ""
echo "View dashboards at: $ENDPOINT"
