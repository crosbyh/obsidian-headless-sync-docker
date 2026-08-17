#!/bin/sh
set -e

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
VAULT_PATH="${VAULT_PATH:-/vault}"

# CLI state (auth/device/sync db) goes to $XDG_CONFIG_HOME/obsidian-headless.
# HOME cannot be used for this: su-exec resets HOME to the target UID's passwd
# entry (/home/node for UID 1000), which is empty on the read-only rootfs.
# XDG_CONFIG_HOME survives the privilege drop, and /data is a volume so the
# registered sync device identity persists across container recreates.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/data/config}"

# Writable home for anything else that insists on $HOME (tmpfs, always clean).
export HOME="/run/obsidian-home"

_setup_home() {
  mkdir -p "${HOME}" "${XDG_CONFIG_HOME}/obsidian-headless"
  chown -R "${PUID}:${PGID}" "${HOME}" "${XDG_CONFIG_HOME}"
}

# ---------------------------------------------------------------------------
# _FILE secrets support: file_env VAR resolves VAR from VAR_FILE (Docker/Podman
# secrets convention). Setting both VAR and VAR_FILE is an error.
# ---------------------------------------------------------------------------
file_env() {
  _var="$1"
  _fvar="${_var}_FILE"
  eval "_val=\${${_var}:-}"
  eval "_fval=\${${_fvar}:-}"
  if [ -n "$_val" ] && [ -n "$_fval" ]; then
    echo "[obsidian-headless] ERROR: both ${_var} and ${_fvar} are set — use one." >&2
    exit 1
  fi
  if [ -n "$_fval" ]; then
    if [ ! -r "$_fval" ]; then
      echo "[obsidian-headless] ERROR: ${_fvar} points to an unreadable file: ${_fval}" >&2
      exit 1
    fi
    eval "${_var}=\$(cat \"\$_fval\")"
    export "${_var?}"
  fi
}

file_env OBSIDIAN_AUTH_TOKEN
file_env VAULT_PASSWORD

# ---------------------------------------------------------------------------
# Subcommand dispatch — lets helpers and raw ob commands be called directly:
#   docker run --rm -it <image> get-token
#   docker run --rm -it <image> ob sync-list-remote
# ---------------------------------------------------------------------------
case "$1" in
  get-token)
    _setup_home
    exec su-exec "${PUID}:${PGID}" /usr/local/bin/get-token
    ;;
  ob)
    shift
    _setup_home
    exec su-exec "${PUID}:${PGID}" ob "$@"
    ;;
  "")
    ;;   # fall through to sync logic below
  *)
    exec su-exec "${PUID}:${PGID}" "$@"
    ;;
esac

# ---------------------------------------------------------------------------
# Validate required env vars
# ---------------------------------------------------------------------------
if [ -z "$OBSIDIAN_AUTH_TOKEN" ]; then
  echo "[obsidian-headless] ERROR: OBSIDIAN_AUTH_TOKEN is not set." >&2
  echo "[obsidian-headless] Run: docker run --rm -it <image> get-token" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Prepare directories (runs as root so chown always works, even on rootless)
# ---------------------------------------------------------------------------
mkdir -p "$VAULT_PATH"
chown "${PUID}:${PGID}" "$VAULT_PATH"
_setup_home

if [ -r /etc/obsidian-headless-version ]; then
  echo "[obsidian-headless] obsidian-headless v$(cat /etc/obsidian-headless-version)"
fi
echo "[obsidian-headless] Running as UID=${PUID} GID=${PGID}"

# ---------------------------------------------------------------------------
# Vault setup + optional sync config, applied per vault path
# ---------------------------------------------------------------------------
_setup_vault() {
  # _setup_vault <remote-vault-name> <password> <local-path>
  _name="$1"; _pass="$2"; _path="$3"

  mkdir -p "$_path"
  chown "${PUID}:${PGID}" "$_path"

  echo "[obsidian-headless] Configuring sync for vault: '$_name' → $_path"
  set -- ob sync-setup --vault "$_name" --path "$_path"
  if [ -n "$_pass" ]; then
    set -- "$@" --password "$_pass"
  fi
  if [ -n "$CONFIG_DIR" ]; then
    set -- "$@" --config-dir "$CONFIG_DIR"
  fi
  if ! su-exec "${PUID}:${PGID}" "$@"; then
    echo "[obsidian-headless] ERROR: ob sync-setup failed for vault '$_name'." >&2
    echo "[obsidian-headless] Check OBSIDIAN_AUTH_TOKEN and the vault name are correct." >&2
    if [ -z "$_pass" ]; then
      echo "[obsidian-headless] If this vault uses end-to-end encryption, set its password." >&2
    fi
    exit 1
  fi
}

_apply_config() {
  # _apply_config <local-path>
  _path="$1"

  if [ -n "$DEVICE_NAME" ]; then
    su-exec "${PUID}:${PGID}" ob sync-config --path "$_path" --device-name "$DEVICE_NAME" 2>/dev/null || true
  fi
  if [ -n "$CONFLICT_STRATEGY" ]; then
    su-exec "${PUID}:${PGID}" ob sync-config --path "$_path" --conflict-strategy "$CONFLICT_STRATEGY" 2>/dev/null || true
  fi
  if [ -n "$EXCLUDED_FOLDERS" ]; then
    su-exec "${PUID}:${PGID}" ob sync-config --path "$_path" --excluded-folders "$EXCLUDED_FOLDERS" 2>/dev/null || true
  fi
  if [ -n "$FILE_TYPES" ]; then
    su-exec "${PUID}:${PGID}" ob sync-config --path "$_path" --file-types "$FILE_TYPES" 2>/dev/null || true
  fi
  if [ -n "$SYNC_MODE" ]; then
    su-exec "${PUID}:${PGID}" ob sync-config --path "$_path" --mode "$SYNC_MODE" 2>/dev/null || true
  fi
  if [ -n "$SYNC_CONFIGS" ]; then
    su-exec "${PUID}:${PGID}" ob sync-config --path "$_path" --configs "$SYNC_CONFIGS" 2>/dev/null || true
  fi
  if [ -n "$CONFIG_DIR" ]; then
    su-exec "${PUID}:${PGID}" ob sync-config --path "$_path" --config-dir "$CONFIG_DIR" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Enumerate configured vaults.
#
# Multi-vault: VAULT_NAME_1, VAULT_NAME_2, ... (with optional VAULT_PASSWORD_n
# or VAULT_PASSWORD_n_FILE), each syncing to $VAULT_PATH/<vault name>.
# Single-vault: VAULT_NAME (+ VAULT_PASSWORD), syncing to $VAULT_PATH itself.
# ---------------------------------------------------------------------------
VAULT_PATHS=""

if [ -n "${VAULT_NAME_1:-}" ]; then
  if [ -n "${VAULT_NAME:-}" ]; then
    echo "[obsidian-headless] WARNING: VAULT_NAME is ignored because numbered VAULT_NAME_1... vars are set." >&2
  fi
  _n=1
  while :; do
    eval "_vname=\${VAULT_NAME_${_n}:-}"
    if [ -z "$_vname" ]; then
      break
    fi
    file_env "VAULT_PASSWORD_${_n}"
    eval "_vpass=\${VAULT_PASSWORD_${_n}:-}"
    _vpath="${VAULT_PATH}/${_vname}"
    _setup_vault "$_vname" "$_vpass" "$_vpath"
    _apply_config "$_vpath"
    VAULT_PATHS="${VAULT_PATHS}${_vpath}
"
    _n=$((_n + 1))
  done
else
  if [ -n "$VAULT_NAME" ]; then
    _setup_vault "$VAULT_NAME" "$VAULT_PASSWORD" "$VAULT_PATH"
  fi
  _apply_config "$VAULT_PATH"
  VAULT_PATHS="${VAULT_PATH}
"
fi

# ---------------------------------------------------------------------------
# One-shot mode: run a single sync per vault, then exit.
# ---------------------------------------------------------------------------
if [ "$SYNC_ONESHOT" = "true" ]; then
  _rc=0
  while IFS= read -r _vpath; do
    [ -z "$_vpath" ] && continue
    echo "[obsidian-headless] One-shot sync: $_vpath"
    su-exec "${PUID}:${PGID}" ob sync --path "$_vpath" || _rc=1
  done <<EOF
$VAULT_PATHS
EOF
  if [ "$_rc" -eq 0 ]; then
    echo "[obsidian-headless] One-shot sync complete."
  else
    echo "[obsidian-headless] One-shot sync finished with errors." >&2
  fi
  exit "$_rc"
fi

# ---------------------------------------------------------------------------
# Continuous sync.
# Single vault: exec directly (no wrapper shell, clean signal handling).
# Multiple vaults: one child per vault; if any dies, stop the rest and exit
# non-zero so the restart policy restarts the container.
# ---------------------------------------------------------------------------
_count=$(printf '%s' "$VAULT_PATHS" | grep -c .)

if [ "$_count" -le 1 ]; then
  _vpath=$(printf '%s' "$VAULT_PATHS" | head -n1)
  echo "[obsidian-headless] Starting continuous sync..."
  exec su-exec "${PUID}:${PGID}" ob sync --continuous --path "${_vpath:-$VAULT_PATH}"
fi

echo "[obsidian-headless] Starting continuous sync for ${_count} vaults..."
PIDS=""
while IFS= read -r _vpath; do
  [ -z "$_vpath" ] && continue
  su-exec "${PUID}:${PGID}" ob sync --continuous --path "$_vpath" &
  PIDS="$PIDS $!"
done <<EOF
$VAULT_PATHS
EOF

_shutdown() {
  echo "[obsidian-headless] Stopping sync processes..."
  kill $PIDS 2>/dev/null || true
  wait
  exit 0
}
trap _shutdown TERM INT

while :; do
  for _pid in $PIDS; do
    if ! kill -0 "$_pid" 2>/dev/null; then
      echo "[obsidian-headless] ERROR: a sync process exited — stopping container for restart." >&2
      kill $PIDS 2>/dev/null || true
      wait
      exit 1
    fi
  done
  sleep 5
done
