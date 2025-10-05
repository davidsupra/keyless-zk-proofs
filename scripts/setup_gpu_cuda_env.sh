#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[setup] %s\n' "$*"
}

warn() {
  printf '[setup][warn] %s\n' "$*" >&2
}

err() {
  printf '[setup][error] %s\n' "$*" >&2
}

usage() {
  cat <<'USAGE'
Usage: setup_gpu_cuda_env.sh [options]

Automate post-clone setup for the Aptos Keyless prover with Icicle GPU acceleration.

Options:
  --backend-prefix DIR      Installation target for the Icicle backend (default: /opt/icicle)
  --backend-version TAG     Icicle release tag (default: latest)
  --backend-distro NAME     Icicle backend distro suffix (default: ubuntu22)
  --backend-flavor NAME     Icicle backend flavor suffix (default: cuda122)
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

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

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

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Required command '$1' not found in PATH. Please install it and re-run."
    exit 1
  fi
}

run_manage_deps() {
  local label="$1"
  shift
  local deps=("$@")
  if [[ ${#deps[@]} -eq 0 ]]; then
    return
  fi
  log "Installing ${label} dependencies: ${deps[*]}"
  DEP_LIST="${deps[*]}" REPO_ROOT="$REPO_ROOT" python3 - <<'PY'
import os
import sys
repo_root = os.environ["REPO_ROOT"]
sys.path.insert(0, os.path.join(repo_root, "scripts", "python"))
from utils import manage_deps
deps = os.environ["DEP_LIST"].split()
if deps:
    manage_deps.install_deps(deps)
PY
}

ensure_poetry() {
  if command -v poetry >/dev/null 2>&1; then
    return
  fi
  log "Poetry not detected. Installing..."
  if command -v pipx >/dev/null 2>&1; then
    pipx install poetry
  else
    if ! command -v curl >/dev/null 2>&1; then
      err "curl is required to bootstrap poetry."
      exit 1
    fi
    curl -sSL https://install.python-poetry.org | python3 -
  fi
  if ! command -v poetry >/dev/null 2>&1; then
    warn "Poetry installation completed but binary not on PATH. Exporting ~/.local/bin."
    export PATH="$HOME/.local/bin:$PATH"
    if ! command -v poetry >/dev/null 2>&1; then
      err "Poetry is still not available on PATH after installation."
      exit 1
    fi
  fi
}

load_nvm() {
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  local nvm_sh="$nvm_dir/nvm.sh"
  if [[ -s "$nvm_sh" ]]; then
    export NVM_DIR="$nvm_dir"
    # shellcheck disable=SC1090
    . "$nvm_sh"
  else
    warn "nvm not found at $nvm_sh. npm-based commands may fail."
  fi
}

require_cmd git
require_cmd python3
require_cmd curl

cd "$REPO_ROOT"

if [[ $SKIP_SUBMODULES -eq 0 ]]; then
  log "Updating git submodules (icicle et al.)"
  git submodule update --init --recursive
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

circuit_deps=(circom snarkjs circomlib nlohmann-json nasm)
if [[ $needs_node -eq 1 ]]; then
  circuit_deps=(node "${circuit_deps[@]}")
fi
run_manage_deps "circuit" "${circuit_deps[@]}"

load_nvm

if [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck disable=SC1091
  . "$HOME/.cargo/env"
fi
if [[ -d "$HOME/.cargo/bin" ]]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi

ensure_poetry

log "Installing Python dependencies via poetry"
poetry install

log "Adding prover-service env vars to shell profile"
./scripts/task.sh prover-service add-envvars-to-profile

if [[ $SKIP_BACKEND -eq 0 ]]; then
  INSTALL_ARGS=("--prefix" "$ICICLE_PREFIX" "--version" "$ICICLE_VERSION" "--distro" "$ICICLE_DISTRO" "--flavor" "$ICICLE_FLAVOR")
  if [[ $ICICLE_FORCE -eq 1 ]]; then
    INSTALL_ARGS+=("--force")
  fi
  backend_script="$REPO_ROOT/scripts/install_icicle_backend.sh"
  if [[ ! -x "$backend_script" ]]; then
    err "Backend installer script not found at $backend_script"
    exit 1
  fi
  log "Installing Icicle backend (${ICICLE_VERSION}/${ICICLE_DISTRO}/${ICICLE_FLAVOR}) into $ICICLE_PREFIX"
  if [[ -w "$ICICLE_PREFIX" ]]; then
    bash "$backend_script" "${INSTALL_ARGS[@]}"
  elif [[ ! -e "$ICICLE_PREFIX" ]] && [[ -w "$(dirname "$ICICLE_PREFIX")" ]]; then
    bash "$backend_script" "${INSTALL_ARGS[@]}"
  elif command -v sudo >/dev/null 2>&1; then
    sudo bash "$backend_script" "${INSTALL_ARGS[@]}"
  else
    err "Cannot write to $ICICLE_PREFIX and sudo is unavailable."
    exit 1
  fi
  export ICICLE_BACKEND_INSTALL_DIR="$ICICLE_PREFIX/lib/backend"
  log "Exporting ICICLE_BACKEND_INSTALL_DIR=$ICICLE_BACKEND_INSTALL_DIR for current session"
  python3 - <<'PY'
import os
import sys
repo_root = os.environ["REPO_ROOT"]
sys.path.insert(0, os.path.join(repo_root, "scripts", "python"))
from utils import add_envvar_to_profile
install_dir = os.environ["ICICLE_BACKEND_INSTALL_DIR"]
add_envvar_to_profile("ICICLE_BACKEND_INSTALL_DIR", install_dir)
PY
else
  log "Skipping Icicle backend installation"
  if [[ -z "${ICICLE_BACKEND_INSTALL_DIR:-}" ]]; then
    warn "ICICLE_BACKEND_INSTALL_DIR not set; ensure backend libraries are accessible before running the prover."
  fi
fi

if [[ $SKIP_CIRCUIT_SETUP -eq 0 ]]; then
  load_nvm
  log "Installing npm dependencies for circuit"
  (cd "$REPO_ROOT/circuit" && npm install)

  circom_cmd=(circom --O2 -l templates -l "$(npm root -g)" templates/main.circom --r1cs --wasm --c --sym)
  log "Compiling main circuit with: ${circom_cmd[*]}"
  (cd "$REPO_ROOT/circuit" && "${circom_cmd[@]}")

  if [[ -d "$REPO_ROOT/circuit/main_c_cpp" ]]; then
    log "Building C witness generator"
    (cd "$REPO_ROOT/circuit/main_c_cpp" && make)
  fi

  if [[ -n "$CUSTOM_RESOURCES_DIR" ]]; then
    export RESOURCES_DIR="$CUSTOM_RESOURCES_DIR"
  fi
  log "Procuring testing setup (this may take several minutes)"
  ./scripts/task.sh setup procure-testing-setup || warn "Testing setup procurement failed; rerun if proofs are required."
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
