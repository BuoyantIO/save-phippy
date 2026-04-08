#!/usr/bin/env bash
# installer.sh – download the admin binary for the current platform and install
# it to $HOME/save-phippy/bin/admin.
#
# The current release tag is read from .current on the main branch of this
# repository; the binary archives are attached to the matching GitHub release.

set -euo pipefail

REPO="BuoyantIO/save-phippy"
INSTALL_DIR="$HOME/.save-phippy/bin"
INSTALL_PATH="$INSTALL_DIR/spadmin"

# ---------------------------------------------------------------------------
# Detect OS
# ---------------------------------------------------------------------------
OS="$(uname -s)"
case "$OS" in
  Linux)  GOOS="linux" ;;
  Darwin) GOOS="darwin" ;;
  *)
    echo "Unsupported operating system: $OS" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Detect architecture
# ---------------------------------------------------------------------------
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) GOARCH="amd64" ;;
  aarch64|arm64) GOARCH="arm64" ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

# macOS universal binary is published as darwin_all
if [ "$GOOS" = "darwin" ]; then
  GOARCH="all"
fi

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
echo "Installing save-phippy admin ${TAG} (${GOOS}/${GOARCH}) ..."

# ---------------------------------------------------------------------------
# Download and extract the binary
# ---------------------------------------------------------------------------
ARCHIVE="admin_${TAG}_${GOOS}_${GOARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading ${DOWNLOAD_URL} ..."
if command -v curl &>/dev/null; then
  curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/$ARCHIVE"
else
  wget -qO "$TMP_DIR/$ARCHIVE" "$DOWNLOAD_URL"
fi

tar -xzf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR" admin

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
mkdir -p "$INSTALL_DIR"
mv "$TMP_DIR/admin" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

echo "Installed: $INSTALL_PATH"
echo ""
echo "To use the admin CLI, add the following to your shell profile:"
echo "  export PATH=\"\$HOME/.save-phippy/bin:\$PATH\""
echo ""
echo "Then you can run:"
echo "  spadmin --help"
