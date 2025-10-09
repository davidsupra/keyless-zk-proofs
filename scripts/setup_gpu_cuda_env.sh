#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# shellcheck source=lib/setup_common.sh
. "${SCRIPT_DIR}/lib/setup_common.sh"
# shellcheck source=lib/setup_node.sh
. "${SCRIPT_DIR}/lib/setup_node.sh"
# shellcheck source=lib/setup_python_env.sh
. "${SCRIPT_DIR}/lib/setup_python_env.sh"
# shellcheck source=lib/setup_backend.sh
. "${SCRIPT_DIR}/lib/setup_backend.sh"
# shellcheck source=lib/setup_circuit.sh
. "${SCRIPT_DIR}/lib/setup_circuit.sh"

usage() {
  cat <<'USAGE'
Usage: setup_gpu_cuda_env.sh [options]

Automate post-clone setup for the Aptos Keyless prover with Icicle GPU acceleration.

Options:
  --backend-prefix DIR      Installation target for the Icicle backend (default: /opt/icicle)
  --backend-version TAG     Icicle release tag (default: latest)
  --backend-distro NAME     Icicle backend distro suffix (default: ubuntu22)
  --backend-flavor NAME     Icicle backend flavor suffix (default: cuda122)
  --python-provider NAME    Python install strategy: auto (default), apt, or conda
  --backend-force           Overwrite any existing backend install at the target prefix
  --skip-backend            Skip backend download/installation
  --skip-submodules         Skip git submodule update
  --skip-circuit-setup      Skip circom/snarkjs compilation and trusted setup procurement
  --skip-cargo-build        Skip final cargo build of the prover service
  --resources-dir DIR       Override RESOURCES_DIR for circuit setup artifacts
  -h, --help                Show this help message

Examples:
  ./scripts/setup_gpu_cuda_env.sh
  ./scripts/setup_gpu_cuda_env.sh --backend-prefix /opt/icicle --backend-version v4.0.0
USAGE
}

ICICLE_PREFIX="/opt/icicle"
ICICLE_VERSION="latest"
ICICLE_DISTRO="ubuntu22"
ICICLE_FLAVOR="cuda122"
ICICLE_FORCE=0
SKIP_BACKEND=0
SKIP_SUBMODULES=0
SKIP_CIRCUIT_SETUP=0
SKIP_CARGO_BUILD=0
CUSTOM_RESOURCES_DIR=""
PYTHON_PROVIDER="auto"
RESOLVED_PYTHON_CMD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend-prefix)
      [[ $# -ge 2 ]] || { err "--backend-prefix requires a value"; exit 1; }
      ICICLE_PREFIX="$2"
      shift 2
      ;;
    --backend-version)
      [[ $# -ge 2 ]] || { err "--backend-version requires a value"; exit 1; }
      ICICLE_VERSION="$2"
      shift 2
      ;;
    --backend-distro)
      [[ $# -ge 2 ]] || { err "--backend-distro requires a value"; exit 1; }
      ICICLE_DISTRO="$2"
      shift 2
      ;;
    --backend-flavor)
      [[ $# -ge 2 ]] || { err "--backend-flavor requires a value"; exit 1; }
      ICICLE_FLAVOR="$2"
      shift 2
      ;;
    --python-provider)
      [[ $# -ge 2 ]] || { err "--python-provider requires a value"; exit 1; }
      case "$2" in
        auto|apt|conda)
          PYTHON_PROVIDER="$2"
          ;;
        *)
          err "Unsupported python provider '$2'. Expected one of: auto, apt, conda."
          exit 1
          ;;
      esac
      shift 2
      ;;
    --backend-force)
      ICICLE_FORCE=1
      shift
      ;;
    --skip-backend)
      SKIP_BACKEND=1
      shift
      ;;
    --skip-submodules)
      SKIP_SUBMODULES=1
      shift
      ;;
    --skip-circuit-setup)
      SKIP_CIRCUIT_SETUP=1
      shift
      ;;
    --skip-cargo-build)
      SKIP_CARGO_BUILD=1
      shift
      ;;
    --resources-dir)
      [[ $# -ge 2 ]] || { err "--resources-dir requires a value"; exit 1; }
      CUSTOM_RESOURCES_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

export PATH="$HOME/.local/bin:$PATH"

require_cmd git
require_cmd python3
require_cmd curl

cd "$REPO_ROOT"

if [[ $SKIP_SUBMODULES -eq 0 ]]; then
  if [[ -f "$REPO_ROOT/.gitmodules" ]] && git config --file "$REPO_ROOT/.gitmodules" --get-regexp '^submodule\.' >/dev/null 2>&1; then
    log "Updating git submodules (icicle et al.)"
    git submodule update --init --recursive
  else
    warn "No git submodules configured; skipping submodule update"
  fi
else
  log "Skipping submodule update"
fi

needs_node=0
if ! command -v node >/dev/null 2>&1; then
  needs_node=1
else
  nvm_candidate="${NVM_DIR:-$HOME/.nvm}/nvm.sh"
  if [[ ! -s "$nvm_candidate" ]]; then
    warn "Found node in PATH but no nvm installation; installing nvm-managed node for compatibility."
    needs_node=1
  fi
fi

prover_deps=(pkg-config lld meson rust clang cmake make libyaml nasm gmp openssl)
run_manage_deps "prover-service" "${prover_deps[@]}"

if [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck disable=SC1091
  . "$HOME/.cargo/env"
fi
if [[ -d "$HOME/.cargo/bin" ]]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

circuit_deps=(circom snarkjs circomlib nlohmann-json nasm)
if [[ $needs_node -eq 1 ]]; then
  circuit_deps=(node "${circuit_deps[@]}")
fi
run_manage_deps "circuit" "${circuit_deps[@]}"

load_nvm

# ensure_poetry fetches Poetry under ~/.local/bin when absent. In
# containerized shells that PATH entry may be missing on reruns, which would
# trigger a redundant reinstall. Export it before invoking ensure_poetry so
# the existing binary is detected.
if [[ -d "$HOME/.local/bin" ]]; then
  case ":$PATH:" in
    *:$(printf '%s' "$HOME/.local/bin"):* ) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
fi

ensure_poetry

if ! resolve_poetry_python; then
  true
fi
POETRY_PYTHON_CMD="$RESOLVED_PYTHON_CMD"
if [[ -z "$POETRY_PYTHON_CMD" ]]; then
  err "Python 3.11+ is required for poetry (project targets ^3.11). Install python3.11 manually or set POETRY_PYTHON before running."
  exit 1
fi

log "Using $POETRY_PYTHON_CMD for poetry virtual environment"
poetry env use "$POETRY_PYTHON_CMD" >/dev/null 2>&1 || poetry env use "$POETRY_PYTHON_CMD"

log "Installing Python dependencies via poetry"
poetry install

log "Adding prover-service env vars to shell profile"
./scripts/task.sh prover-service add-envvars-to-profile

if [[ $SKIP_BACKEND -eq 0 ]]; then
  install_icicle_backend "$ICICLE_PREFIX" "$ICICLE_VERSION" "$ICICLE_DISTRO" "$ICICLE_FLAVOR" "$ICICLE_FORCE" "$REPO_ROOT"
else
  log "Skipping Icicle backend installation"
  if [[ -z "${ICICLE_BACKEND_INSTALL_DIR:-}" ]]; then
    warn "ICICLE_BACKEND_INSTALL_DIR not set; ensure backend libraries are accessible before running the prover."
  fi
fi

if [[ $SKIP_CIRCUIT_SETUP -eq 0 ]]; then
  perform_circuit_setup "$REPO_ROOT" "$CUSTOM_RESOURCES_DIR"
else
  log "Skipping circuit compilation and setup procurement"
fi

if [[ $SKIP_CARGO_BUILD -eq 0 ]]; then
  log "Building prover service (debug profile)"
  cargo build -p prover-service
else
  log "Skipping prover service cargo build"
fi

log "Setup completed. Review warnings above if any."
