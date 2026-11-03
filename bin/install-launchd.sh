#!/bin/bash
# Install the Notchcast updater for this user. Usage: install-launchd.sh update
#   notchcast.update runs bin/notchcast-update.sh every 30 min (needs gh logged in).
# Builds and releases run on GitHub Actions (.github/workflows/sync.yml), not on a Mac.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LOGS="$HOME/Library/Logs/notchcast"
mkdir -p "$LOGS" "$HOME/Library/LaunchAgents"

agent() { # label interval program...
    local label=$1 interval=$2 name=$3; shift 3
    local plist="$HOME/Library/LaunchAgents/$label.plist" args=""
    for a in "$@"; do args="$args<string>$a</string>"; done
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array>$args</array>
<key>StartInterval</key><integer>$interval</integer>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Background</string>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
<key>StandardOutPath</key><string>$LOGS/$name.log</string>
<key>StandardErrorPath</key><string>$LOGS/$name.log</string>
</dict></plist>
PLIST
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist"
    echo "loaded $label -> $LOGS/$name.log"
}

[ "${1:-}" = update ] || { echo "usage: $0 update" >&2; exit 2; }
agent notchcast.update 1800 update /bin/bash "$HERE/bin/notchcast-update.sh"
