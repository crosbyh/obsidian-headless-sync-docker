#!/bin/sh
# Interactive helper: logs in to Obsidian and prints the resulting auth token.
# Usage: docker run --rm -it <image> get-token

set -e

echo ""
echo "=== obsidian-headless: Get Auth Token ==="
echo ""
echo "Log in to your Obsidian account."
echo "You will be prompted for your email, password, and MFA code (if enabled)."
echo ""

ob login

echo ""
echo "==========================================="

# Locate the stored token file (fall back to a find if path differs)
TOKEN=""
CANDIDATES="
  ${HOME}/.config/obsidian-headless/auth_token
  ${HOME}/.local/share/obsidian-headless/auth_token
  ${HOME}/.obsidian-headless/auth_token
"

for candidate in $CANDIDATES; do
  if [ -f "$candidate" ]; then
    TOKEN=$(cat "$candidate")
    break
  fi
done

if [ -z "$TOKEN" ]; then
  FOUND=$(find "$HOME" -path "*obsidian-headless*" -name "auth_token" 2>/dev/null | head -1)
  if [ -n "$FOUND" ]; then
    TOKEN=$(cat "$FOUND")
  fi
fi

if [ -z "$TOKEN" ]; then
  echo "Could not locate the auth token file automatically." >&2
  echo "Search manually with:" >&2
  echo "  find ~ -path '*obsidian-headless*' 2>/dev/null" >&2
  exit 1
fi

echo ""
echo "Your OBSIDIAN_AUTH_TOKEN:"
echo ""
echo "  $TOKEN"
echo ""
echo "Add this to your .env file:"
echo "  OBSIDIAN_AUTH_TOKEN=$TOKEN"
echo ""
echo "==========================================="
