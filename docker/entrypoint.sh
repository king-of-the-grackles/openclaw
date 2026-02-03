#!/bin/bash
# OpenClaw Docker Entrypoint
# Handles runtime plugin installation before starting the main process
set -e

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
# SKILL CONFIGURATION
# ============================================
# Disable Homebrew preference for Docker (Linux has apt/pip)
export SKILLS_INSTALL_PREFER_BREW="${SKILLS_INSTALL_PREFER_BREW:-false}"

# ============================================
# EXECUTE MAIN COMMAND
# ============================================
exec "$@"
