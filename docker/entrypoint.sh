#!/bin/bash
# OpenClaw Docker Entrypoint
# Handles runtime plugin installation before starting the main process
set -e

# ============================================
# BUNDLED PLUGIN INSTALLATION (first boot only)
# ============================================
# Plugins listed in plugins-install-bundled.txt are installed on first boot.
# A marker file on persistent disk ensures this runs only once, not on every
# container restart. Subsequent deploys with a new image will re-run because
# the marker lives on the data disk (survives restarts, not full wipes).
#
BUNDLED_PLUGINS="/app/docker/plugins-install-bundled.txt"
BUNDLED_MARKER="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}/.bundled-plugins-installed"

if [ -f "$BUNDLED_PLUGINS" ] && [ ! -f "$BUNDLED_MARKER" ]; then
  echo "[entrypoint] Installing bundled plugins (first boot)..."
  while IFS= read -r plugin || [ -n "$plugin" ]; do
    # Trim whitespace
    plugin=$(echo "$plugin" | xargs)

    # Skip empty lines and comments
    [[ -z "$plugin" || "$plugin" == \#* ]] && continue

    # Extract plugin name for existence check
    plugin_name="${plugin##*/}"

    # Check if already installed
    if [ -d "/home/node/.openclaw/extensions/${plugin_name}" ]; then
      echo "[entrypoint] Already installed: $plugin_name"
      continue
    fi

    echo "[entrypoint] Installing: $plugin_name"
    node /app/dist/index.js plugins install "$plugin" || echo "[entrypoint] Warning: $plugin_name failed"
  done < "$BUNDLED_PLUGINS"
  touch "$BUNDLED_MARKER"
  echo "[entrypoint] Bundled plugin installation complete."
fi

# ============================================
# RUNTIME PLUGIN INSTALLATION
# ============================================
# Install plugins listed in plugins-install.txt at container startup.
# This allows users to add custom plugins without rebuilding the image.
#
# Format of plugins-install.txt (one plugin per line):
#   ./extensions/my-plugin        # Local extension
#   npm:my-plugin@1.0.0           # npm package
#   gh:owner/repo                 # GitHub repo
#   # This is a comment          # Comments start with #
#
PLUGINS_FILE="/home/node/.openclaw/plugins-install.txt"

if [ -f "$PLUGINS_FILE" ]; then
  echo "[entrypoint] Installing plugins from plugins-install.txt..."
  while IFS= read -r plugin || [ -n "$plugin" ]; do
    # Trim whitespace
    plugin=$(echo "$plugin" | xargs)

    # Skip empty lines and comments
    [[ -z "$plugin" || "$plugin" == \#* ]] && continue

    # Extract plugin name for existence check
    plugin_name="${plugin##*/}"
    plugin_name="${plugin_name%%@*}"

    # Check if already installed
    if [ -d "/home/node/.openclaw/extensions/${plugin_name}" ]; then
      echo "[entrypoint] Plugin already installed: $plugin_name"
      continue
    fi

    echo "[entrypoint] Installing plugin: $plugin"
    node /app/dist/index.js plugins install "$plugin" || echo "[entrypoint] Warning: Failed to install $plugin"
  done < "$PLUGINS_FILE"
  echo "[entrypoint] Plugin installation complete."
fi

# ============================================
# SECURE TELEGRAM CONFIGURATION
# ============================================
# If TELEGRAM_BOT_TOKEN is set and no config exists, create a secure initial config.
# This sets up Telegram with maximum security settings:
#   - dmPolicy: "allowlist" (only pre-approved users can message)
#   - groupPolicy: "disabled" (no group access)
#   - configWrites: false (no remote config changes)
#
CONFIG_DIR="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"

if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ ! -f "$CONFIG_FILE" ]; then
  echo "[entrypoint] Creating secure Telegram configuration..."
  mkdir -p "$CONFIG_DIR"

  # Build allowFrom array if TELEGRAM_ALLOWFROM is set
  if [ -n "$TELEGRAM_ALLOWFROM" ]; then
    ALLOWFROM_JSON="[\"$TELEGRAM_ALLOWFROM\"]"
  else
    ALLOWFROM_JSON="[]"
  fi

  cat > "$CONFIG_FILE" << EOF
{
  "gateway": {
    "mode": "local",
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    },
    "auth": {
      "allowTailscale": true
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "\${TELEGRAM_BOT_TOKEN}",
      "dmPolicy": "allowlist",
      "allowFrom": $ALLOWFROM_JSON,
      "groupPolicy": "disabled",
      "configWrites": false
    }
  }
}
EOF
  chmod 600 "$CONFIG_FILE"
  echo "[entrypoint] Secure Telegram config created at $CONFIG_FILE"
  echo "[entrypoint] Security settings: dmPolicy=allowlist, groupPolicy=disabled, configWrites=false"
fi

# ============================================
# SKILL CONFIGURATION
# ============================================
# Disable Homebrew preference for Docker (Linux has apt/pip)
export SKILLS_INSTALL_PREFER_BREW="${SKILLS_INSTALL_PREFER_BREW:-false}"

# ============================================
# DESCOPE OAUTH TOKEN FOR MCP SERVERS
# ============================================
# Fetch Descope OAuth token for MCP servers that require it.
# This handles headless Docker environments where browser-based OAuth fails.
#
if [ -n "$DESCOPE_CLIENT_ID" ] && [ -n "$DESCOPE_CLIENT_SECRET" ] && [ -n "$DESCOPE_TOKEN_URL" ]; then
    echo "[entrypoint] Fetching Descope OAuth token for MCP servers..."

    TOKEN_RESPONSE=$(curl -s -X POST "$DESCOPE_TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials" \
        -d "client_id=$DESCOPE_CLIENT_ID" \
        -d "client_secret=$DESCOPE_CLIENT_SECRET")

    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

    if [ -n "$ACCESS_TOKEN" ]; then
        echo "[entrypoint] Successfully obtained Descope access token"

        # Store token in mcporter cache for prod-reddit-research-mcp
        mkdir -p /home/node/.mcporter/prod-reddit-research-mcp
        echo "{\"access_token\": \"$ACCESS_TOKEN\", \"token_type\": \"Bearer\"}" > /home/node/.mcporter/prod-reddit-research-mcp/token.json
        chown -R node:node /home/node/.mcporter

        # Export as env var for use in mcporter config
        export REDDIT_MCP_ACCESS_TOKEN="$ACCESS_TOKEN"
        echo "[entrypoint] Token exported as REDDIT_MCP_ACCESS_TOKEN"
    else
        echo "[entrypoint] Warning: Failed to obtain Descope token"
        echo "[entrypoint] Response: $TOKEN_RESPONSE"
    fi
fi

# ============================================
# TAILSCALE (private tailnet access)
# ============================================
# Start tailscaled in userspace mode (no root needed) if TS_AUTHKEY is set.
# State is persisted on the data disk to survive redeploys.
# Uses default socket path (/var/run/tailscale/tailscaled.sock) so OpenClaw's
# tailscale CLI calls work without --socket.
#
if [ -n "$TS_AUTHKEY" ]; then
  echo "[entrypoint] Starting Tailscale daemon (userspace networking)..."
  TAILSCALE_STATE_DIR="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}/tailscale"
  mkdir -p "$TAILSCALE_STATE_DIR"

  tailscaled \
    --tun=userspace-networking \
    --state="$TAILSCALE_STATE_DIR/tailscaled.state" \
    --no-logs-no-support \
    &

  # Wait for daemon socket to appear
  for i in $(seq 1 10); do
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 1
  done

  echo "[entrypoint] Authenticating with Tailscale..."
  tailscale up \
    --authkey="$TS_AUTHKEY" \
    --hostname="${TS_HOSTNAME:-openclaw-render}"

  echo "[entrypoint] Tailscale connected:"
  tailscale status

  # Configure Tailscale Serve to proxy HTTPS to the local gateway.
  # Done manually here (not via gateway.tailscale.mode=serve) because
  # the gateway uses --bind lan for Render health checks, but OpenClaw's
  # built-in Tailscale Serve management requires --bind loopback.
  GATEWAY_PORT="${PORT:-8080}"
  tailscale serve --bg --https=443 "http://localhost:${GATEWAY_PORT}"
  echo "[entrypoint] Tailscale Serve: https://${TS_HOSTNAME:-openclaw-render}.<tailnet>.ts.net → localhost:${GATEWAY_PORT}"
fi

# ============================================
# EXECUTE MAIN COMMAND
# ============================================
exec "$@"
