#!/bin/sh
set -e

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
VAULT_PATH="${VAULT_PATH:-/vault}"

# Writable home dir for obsidian-headless config state (~/.config/obsidian-headless/)
# Uses /run (tmpfs) so it's always clean and doesn't pollute the vault mount.
export HOME="/run/obsidian-home"

_setup_home() {
  mkdir -p "${HOME}/.config/obsidian-headless"
  chown -R "${PUID}:${PGID}" "${HOME}"
}

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

echo "[obsidian-headless] Running as UID=${PUID} GID=${PGID}"

cd "$VAULT_PATH"

# ---------------------------------------------------------------------------
# First-time vault setup
# ---------------------------------------------------------------------------
if [ -n "$VAULT_NAME" ]; then
  echo "[obsidian-headless] Configuring sync for vault: '$VAULT_NAME' → $VAULT_PATH"
  SETUP_CMD="ob sync-setup --vault \"$VAULT_NAME\""
  if [ -n "$VAULT_PASSWORD" ]; then
    SETUP_CMD="$SETUP_CMD --password \"$VAULT_PASSWORD\""
  fi
  if ! su-exec "${PUID}:${PGID}" sh -c "$SETUP_CMD"; then
    echo "[obsidian-headless] ERROR: ob sync-setup failed." >&2
    echo "[obsidian-headless] Check OBSIDIAN_AUTH_TOKEN and VAULT_NAME are correct." >&2
    if [ -z "$VAULT_PASSWORD" ]; then
      echo "[obsidian-headless] If your vault uses end-to-end encryption, set VAULT_PASSWORD." >&2
    fi
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Apply optional sync config
# ---------------------------------------------------------------------------
if [ -n "$DEVICE_NAME" ]; then
  su-exec "${PUID}:${PGID}" ob sync-config --device-name "$DEVICE_NAME" 2>/dev/null || true
fi

if [ -n "$CONFLICT_STRATEGY" ]; then
  su-exec "${PUID}:${PGID}" ob sync-config --conflict-strategy "$CONFLICT_STRATEGY" 2>/dev/null || true
fi

if [ -n "$EXCLUDED_FOLDERS" ]; then
  su-exec "${PUID}:${PGID}" ob sync-config --excluded-folders "$EXCLUDED_FOLDERS" 2>/dev/null || true
fi

if [ -n "$FILE_TYPES" ]; then
  su-exec "${PUID}:${PGID}" ob sync-config --file-types "$FILE_TYPES" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Run — drop privileges then exec (no wrapper shell, clean signal handling)
# ---------------------------------------------------------------------------
echo "[obsidian-headless] Starting continuous sync..."
exec su-exec "${PUID}:${PGID}" ob sync --continuous
