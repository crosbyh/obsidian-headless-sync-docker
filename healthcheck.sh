#!/bin/sh
# Container healthcheck: verifies the sync process is alive and ob sync-status
# succeeds for every configured vault path. No-op in one-shot mode.

[ "$SYNC_ONESHOT" = "true" ] && exit 0

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
VAULT_PATH="${VAULT_PATH:-/vault}"
export HOME="/run/obsidian-home"

# Resolve token from a secrets file if the _FILE convention is used
if [ -z "${OBSIDIAN_AUTH_TOKEN:-}" ] && [ -n "${OBSIDIAN_AUTH_TOKEN_FILE:-}" ] && [ -r "$OBSIDIAN_AUTH_TOKEN_FILE" ]; then
  OBSIDIAN_AUTH_TOKEN=$(cat "$OBSIDIAN_AUTH_TOKEN_FILE")
  export OBSIDIAN_AUTH_TOKEN
fi

# The continuous sync process must be running
if ! pgrep -f "ob sync" >/dev/null 2>&1; then
  echo "unhealthy: no ob sync process running"
  exit 1
fi

_check() {
  su-exec "${PUID}:${PGID}" ob sync-status --path "$1" >/dev/null 2>&1
}

if [ -n "${VAULT_NAME_1:-}" ]; then
  _n=1
  while :; do
    eval "_vname=\${VAULT_NAME_${_n}:-}"
    [ -z "$_vname" ] && break
    if ! _check "${VAULT_PATH}/${_vname}"; then
      echo "unhealthy: sync-status failed for ${VAULT_PATH}/${_vname}"
      exit 1
    fi
    _n=$((_n + 1))
  done
else
  if ! _check "$VAULT_PATH"; then
    echo "unhealthy: sync-status failed for ${VAULT_PATH}"
    exit 1
  fi
fi

exit 0
