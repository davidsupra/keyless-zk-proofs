# shellcheck shell=bash

log() {
  printf '[setup] %s\n' "$*"
}

warn() {
  printf '[setup][warn] %s\n' "$*" >&2
}

err() {
  printf '[setup][error] %s\n' "$*" >&2
}

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
