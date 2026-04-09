#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NODE_VERSION_FILE="$PROJECT_ROOT/.nvmrc"

use_project_node() {
  if [[ ! -f "$NODE_VERSION_FILE" ]]; then
    return
  fi

  if [[ -z "${NVM_DIR:-}" ]]; then
    export NVM_DIR="$HOME/.nvm"
  fi

  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    source "$NVM_DIR/nvm.sh"
    nvm use >/dev/null
  fi
}

load_env() {
  set -a
  if [[ -f "$PROJECT_ROOT/.env" ]]; then
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/.env"
  fi
  if [[ -f "$PROJECT_ROOT/.env.local" ]]; then
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/.env.local"
  fi
  set +a
}

cd "$PROJECT_ROOT"
use_project_node
load_env

export PORT="${PORT:-5000}"
export HOSTNAME="${MC_HOSTNAME:-${HOSTNAME:-0.0.0.0}}"

if [[ ! -f "$PROJECT_ROOT/.next/standalone/server.js" ]]; then
  echo "==> standalone bundle ausente; gerando build"
  pnpm build
fi

exec bash "$PROJECT_ROOT/scripts/start-standalone.sh"
