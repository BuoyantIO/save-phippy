#!/usr/bin/env bash
# init-multi.sh – download the sp-panopticon.sh and sp-station.sh scripts and
# install them to $HOME/.save-phippy/bin.  These scripts are
# architecture-independent.
#
# The current release tag is read from .current on the main branch of this
# repository; the scripts are fetched from raw GitHub at the matching tag.

set -euo pipefail

REPO="BuoyantIO/save-phippy"
INSTALL_DIR="$HOME/.save-phippy/bin"

# ---------------------------------------------------------------------------
# Fetch the current release tag
# ---------------------------------------------------------------------------
CURRENT_URL="https://raw.githubusercontent.com/${REPO}/main/.current"
echo "Fetching current release tag from ${CURRENT_URL} ..."
if command -v curl &>/dev/null; then
  TAG="$(curl -fsSL "$CURRENT_URL")"
elif command -v wget &>/dev/null; then
  TAG="$(wget -qO- "$CURRENT_URL")"
else
  echo "curl or wget is required to download files" >&2
  exit 1
fi
TAG="$(echo "$TAG" | tr -d '\n')"  # strip trailing newline
if [ -z "$TAG" ]; then
  echo "Could not determine current release tag" >&2
  exit 1
fi
echo "Installing scripts at ${TAG} ..."

# ---------------------------------------------------------------------------
# Download and install each script
# ---------------------------------------------------------------------------
mkdir -p "$INSTALL_DIR"

for script in sp-panopticon.sh sp-station.sh; do
  SCRIPT_URL="https://raw.githubusercontent.com/${REPO}/${TAG}/${script}"
  INSTALL_PATH="$INSTALL_DIR/$script"
  echo "Downloading ${SCRIPT_URL} ..."
  if command -v curl &>/dev/null; then
    curl -fsSL "$SCRIPT_URL" -o "$INSTALL_PATH"
  else
    wget -qO "$INSTALL_PATH" "$SCRIPT_URL"
  fi
  chmod +x "$INSTALL_PATH"
  echo "Installed: $INSTALL_PATH"
done
