#!/bin/sh
# Installs the command line interface of Laska.
#
#   curl -fsSL https://raw.githubusercontent.com/tenderowl/laska/main/tool/install.sh | sh
#
# The options:
#   --version <version>  The version to install. Defaults to the latest one.
#   --home <directory>   Where the command is installed. Defaults to ~/.laska.
#
# The script needs curl and unzip, and it checks the checksum of the bundle it
# downloads before it unpacks it.
set -eu

REPOSITORY="tenderowl/laska"
VERSION=""
HOME_DIR="${LASKA_HOME:-$HOME/.laska}"

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --home)
      HOME_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
  esac
done

case "$(uname -s)" in
  Linux) OS="linux" ;;
  Darwin) OS="macos" ;;
  *)
    echo "Laska is not built for this system: $(uname -s)." >&2
    echo "Use the package of pub.dev instead: dart pub global activate laska_cli" >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ARCH="x64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *)
    echo "Laska is not built for this architecture: $(uname -m)." >&2
    exit 1
    ;;
esac

if [ -z "$VERSION" ]; then
  echo "Looking for the latest version..."
  VERSION="$(curl -fsSL "https://api.github.com/repos/$REPOSITORY/releases/latest" \
    | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' \
    | head -n 1)"
fi

if [ -z "$VERSION" ]; then
  echo "The latest version could not be found." >&2
  exit 1
fi

ASSET="laska-$OS-$ARCH.zip"
BASE="https://github.com/$REPOSITORY/releases/download/v$VERSION"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is needed to download Laska." >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "unzip is needed to unpack Laska." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading Laska $VERSION for $OS-$ARCH..."
curl -fsSL "$BASE/$ASSET" -o "$WORK/$ASSET"
curl -fsSL "$BASE/$ASSET.sha256" -o "$WORK/$ASSET.sha256"

# The checksum of the bundle is checked before it is unpacked: the command that
# runs on the machine of the user is the one that was built by the project.
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL="$(sha256sum "$WORK/$ASSET" | cut -d' ' -f1)"
else
  ACTUAL="$(shasum -a 256 "$WORK/$ASSET" | cut -d' ' -f1)"
fi
EXPECTED="$(cut -d' ' -f1 < "$WORK/$ASSET.sha256")"

if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "The checksum of the bundle does not match: the download was changed on the way." >&2
  exit 1
fi

mkdir -p "$HOME_DIR"
unzip -q -o "$WORK/$ASSET" -d "$HOME_DIR"
chmod +x "$HOME_DIR/bin/laska"

echo ""
echo "Laska $VERSION is installed in $HOME_DIR."
echo ""
echo "Add it to the PATH:"
echo "  export PATH=\"$HOME_DIR/bin:\$PATH\""
echo ""
echo "Then run:"
echo "  laska new shop"
