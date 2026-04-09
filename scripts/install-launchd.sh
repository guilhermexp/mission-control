#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LABEL="${MC_LAUNCHD_LABEL:-com.builderzlabs.mission-control}"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
SERVICE_ROOT="${HOME}/Library/Application Support/MissionControl"
CURRENT_DIR="${SERVICE_ROOT}/current"
LOG_DIR="${HOME}/Library/Logs/mission-control"
PLIST_PATH="${LAUNCH_AGENTS_DIR}/${LABEL}.plist"
RUNNER_PATH="${SERVICE_ROOT}/run.sh"
STDOUT_PATH="${LOG_DIR}/launchd.stdout.log"
STDERR_PATH="${LOG_DIR}/launchd.stderr.log"
UID_VALUE="$(id -u)"
NODE_BIN="${MC_NODE_BIN:-}"

if [[ -z "$NODE_BIN" ]]; then
  NODE_BIN="$(command -v node)"
fi

stop_existing_service_processes() {
  local -a pids=()

  while IFS= read -r pid; do
    [[ -n "$pid" ]] && pids+=("$pid")
  done < <(pgrep -f "${SERVICE_ROOT}/current/server.js" || true)

  while IFS= read -r pid; do
    [[ -n "$pid" ]] && pids+=("$pid")
  done < <(pgrep -f "${PROJECT_ROOT}/.next/standalone/server.js" || true)

  if command -v lsof >/dev/null 2>&1; then
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && pids+=("$pid")
    done < <(lsof -tiTCP:5000 -sTCP:LISTEN -a -c node 2>/dev/null || true)
  fi

  if [[ ${#pids[@]} -eq 0 ]]; then
    return
  fi

  declare -A seen=()
  for pid in "${pids[@]}"; do
    [[ -n "${seen[$pid]:-}" ]] && continue
    seen[$pid]=1
    kill "$pid" >/dev/null 2>&1 || true
  done

  sleep 1
}

mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_DIR" "$CURRENT_DIR" "$SERVICE_ROOT"

if [[ ! -f "${PROJECT_ROOT}/.next/standalone/server.js" ]]; then
  echo "error: standalone bundle ausente em ${PROJECT_ROOT}/.next/standalone/server.js" >&2
  echo "rode 'pnpm build' antes de instalar o launchd" >&2
  exit 1
fi

rm -rf "${CURRENT_DIR}"
mkdir -p "${CURRENT_DIR}/.next"
rsync -a "${PROJECT_ROOT}/.next/standalone/" "${CURRENT_DIR}/"
if [[ -d "${PROJECT_ROOT}/.next/static" ]]; then
  rsync -a "${PROJECT_ROOT}/.next/static/" "${CURRENT_DIR}/.next/static/"
fi
if [[ -d "${PROJECT_ROOT}/public" ]]; then
  rsync -a "${PROJECT_ROOT}/public/" "${CURRENT_DIR}/public/"
fi
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  cp "${PROJECT_ROOT}/.env" "${SERVICE_ROOT}/.env"
fi
if [[ -f "${PROJECT_ROOT}/.env.local" ]]; then
  cp "${PROJECT_ROOT}/.env.local" "${SERVICE_ROOT}/.env.local"
fi

cat >"$RUNNER_PATH" <<EOF
#!/usr/bin/env bash

set -euo pipefail

SERVICE_ROOT="${SERVICE_ROOT}"
CURRENT_DIR="\${SERVICE_ROOT}/current"

set -a
if [[ -f "\${SERVICE_ROOT}/.env" ]]; then
  # shellcheck disable=SC1090
  source "\${SERVICE_ROOT}/.env"
fi
if [[ -f "\${SERVICE_ROOT}/.env.local" ]]; then
  # shellcheck disable=SC1090
  source "\${SERVICE_ROOT}/.env.local"
fi
set +a

export PORT="\${PORT:-5000}"
export HOSTNAME="\${MC_HOSTNAME:-\${HOSTNAME:-0.0.0.0}}"

cd "\${CURRENT_DIR}"
exec "${NODE_BIN}" server.js
EOF

chmod +x "$RUNNER_PATH"

cat >"$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${RUNNER_PATH}</string>
  </array>

  <key>WorkingDirectory</key>
  <string>${CURRENT_DIR}</string>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>ThrottleInterval</key>
  <integer>10</integer>

  <key>StandardOutPath</key>
  <string>${STDOUT_PATH}</string>

  <key>StandardErrorPath</key>
  <string>${STDERR_PATH}</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key>
    <string>${HOME}</string>
    <key>PORT</key>
    <string>5000</string>
  </dict>
</dict>
</plist>
EOF

launchctl bootout "gui/${UID_VALUE}" "$PLIST_PATH" >/dev/null 2>&1 || true
stop_existing_service_processes
launchctl bootstrap "gui/${UID_VALUE}" "$PLIST_PATH"
launchctl enable "gui/${UID_VALUE}/${LABEL}"
launchctl kickstart -k "gui/${UID_VALUE}/${LABEL}"

echo "launchd service installed:"
echo "  label: ${LABEL}"
echo "  plist: ${PLIST_PATH}"
echo "  service root: ${SERVICE_ROOT}"
echo "  stdout: ${STDOUT_PATH}"
echo "  stderr: ${STDERR_PATH}"
