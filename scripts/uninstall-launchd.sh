#!/usr/bin/env bash

set -euo pipefail

LABEL="${MC_LAUNCHD_LABEL:-com.builderzlabs.mission-control}"
PLIST_PATH="${HOME}/Library/LaunchAgents/${LABEL}.plist"
UID_VALUE="$(id -u)"

launchctl bootout "gui/${UID_VALUE}" "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"

echo "launchd service removed:"
echo "  label: ${LABEL}"
echo "  plist: ${PLIST_PATH}"
