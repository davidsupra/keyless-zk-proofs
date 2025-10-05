#!/usr/bin/env bash
set -euo pipefail

DEFAULT_INSTALL_PREFIX="/opt/icicle"
DEFAULT_RELEASE="latest"
DEFAULT_DISTRO="ubuntu22"
DEFAULT_FLAVOR="cuda122"
FORCE=0
INSTALL_PREFIX="${DEFAULT_INSTALL_PREFIX}"
RELEASE="${DEFAULT_RELEASE}"
DISTRO="${DEFAULT_DISTRO}"
FLAVOR="${DEFAULT_FLAVOR}"

usage() {
  cat <<'USAGE'
Usage: install_icicle_backend.sh [options]

Options:
  --prefix <dir>     Install location (default: /opt/icicle)
  --version <tag>    ICICLE release tag or version (default: latest)
  --distro <name>    Release distro suffix (default: ubuntu22)
  --flavor <name>    Backend flavor suffix, e.g. cuda122 or cpu (default: cuda122)
  --cpu              Shortcut for --flavor cpu
  --force            Overwrite existing installation directory contents
  -h, --help         Show this help

Examples:
  sudo ./install_icicle_backend.sh
  sudo ./install_icicle_backend.sh --version v4.0.0 --distro ubuntu20 --flavor cuda122
  sudo ./install_icicle_backend.sh --prefix /custom/icicle --cpu
USAGE
}

log() {
  printf '[install-icicle] %s\n' "$*"
}

error() {
  printf 'Error: %s\n' "$*" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || { error "--prefix requires a value"; exit 1; }
      INSTALL_PREFIX="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || { error "--version requires a value"; exit 1; }
      RELEASE="$2"
      shift 2
      ;;
    --distro)
      [[ $# -ge 2 ]] || { error "--distro requires a value"; exit 1; }
      DISTRO="$2"
      shift 2
      ;;
    --flavor)
      [[ $# -ge 2 ]] || { error "--flavor requires a value"; exit 1; }
      FLAVOR="$2"
      shift 2
      ;;
    --cpu)
      FLAVOR="cpu"
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

for tool in curl tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    error "Required tool '$tool' not found"
    exit 1
  fi
done

if [[ "$RELEASE" == "latest" ]]; then
  API_URL="https://api.github.com/repos/ingonyama-zk/icicle/releases/latest"
  log "Fetching latest release metadata"
  TAG=$(curl -sSf "$API_URL" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
  if [[ -z "${TAG:-}" ]]; then
    error "Failed to determine latest release tag"
    exit 1
  fi
else
  TAG="$RELEASE"
fi

TAG=${TAG#v}
TAG_WITH_V="v${TAG}"
VERSION_UNDERSCORED=${TAG//./_}

if [[ "$FLAVOR" == "cpu" ]]; then
  ARCHIVE_NAME="icicle_${VERSION_UNDERSCORED}-${DISTRO}.tar.gz"
else
  ARCHIVE_NAME="icicle_${VERSION_UNDERSCORED}-${DISTRO}-${FLAVOR}.tar.gz"
fi

DOWNLOAD_URL="https://github.com/ingonyama-zk/icicle/releases/download/${TAG_WITH_V}/${ARCHIVE_NAME}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
ARCHIVE_PATH="${TMPDIR}/${ARCHIVE_NAME}"

log "Downloading ${DOWNLOAD_URL}"
if ! curl -fL "$DOWNLOAD_URL" -o "$ARCHIVE_PATH"; then
  error "Download failed. Check version, distro, and flavor arguments."
  exit 1
fi

if [[ -d "$INSTALL_PREFIX" ]]; then
  if [[ "$FORCE" -ne 1 ]]; then
    if [[ -n $(find "$INSTALL_PREFIX" -mindepth 1 -print -quit 2>/dev/null) ]]; then
      error "Install prefix '$INSTALL_PREFIX' exists and is not empty. Use --force to overwrite."
      exit 1
    fi
  fi
else
  log "Creating install prefix $INSTALL_PREFIX"
  mkdir -p "$INSTALL_PREFIX"
fi

if [[ ! -w "$INSTALL_PREFIX" ]]; then
  error "Install prefix '$INSTALL_PREFIX' is not writable. Run with appropriate permissions."
  exit 1
fi

if [[ "$FORCE" -eq 1 ]]; then
  log "Clearing existing contents under $INSTALL_PREFIX"
  find "$INSTALL_PREFIX" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

log "Extracting archive"
tar -xzf "$ARCHIVE_PATH" -C "$INSTALL_PREFIX" --strip-components=1

BACKEND_DIR="${INSTALL_PREFIX}/lib/backend"
if [[ ! -d "$BACKEND_DIR" ]]; then
  error "Expected backend directory '$BACKEND_DIR' not found after extraction"
  exit 1
fi

log "Installed ICICLE backend to $INSTALL_PREFIX"
log "Set ICICLE_BACKEND_INSTALL_DIR to $BACKEND_DIR or copy runtime libs there if needed"
log "Example: export ICICLE_BACKEND_INSTALL_DIR=$BACKEND_DIR"
