# shellcheck shell=bash

install_icicle_backend() {
  local prefix="$1"
  local version="$2"
  local distro="$3"
  local flavor="$4"
  local force="$5"
  local repo_root="$6"

  local backend_script="${repo_root}/scripts/install_icicle_backend.sh"
  if [[ ! -x "$backend_script" ]]; then
    err "Backend installer script not found at $backend_script"
    exit 1
  fi

  local install_args=("--prefix" "$prefix" "--version" "$version" "--distro" "$distro" "--flavor" "$flavor")
  if [[ "$force" -eq 1 ]]; then
    install_args+=("--force")
  fi

  local backend_dir="${prefix}/lib/backend"
  if [[ -d "$backend_dir" ]] && [[ "$force" -ne 1 ]]; then
    log "Icicle backend already present at $backend_dir; skipping download"
  else
    log "Installing Icicle backend (${version}/${distro}/${flavor}) into $prefix"
    if [[ -w "$prefix" ]]; then
      bash "$backend_script" "${install_args[@]}"
    elif [[ ! -e "$prefix" ]] && [[ -w "$(dirname "$prefix")" ]]; then
      bash "$backend_script" "${install_args[@]}"
    elif command -v sudo >/dev/null 2>&1; then
      sudo bash "$backend_script" "${install_args[@]}"
    else
      err "Cannot write to $prefix and sudo is unavailable."
      exit 1
    fi
  fi

  export ICICLE_BACKEND_INSTALL_DIR="$backend_dir"
  log "Exporting ICICLE_BACKEND_INSTALL_DIR=$ICICLE_BACKEND_INSTALL_DIR for current session"
  REPO_ROOT="$repo_root" ICICLE_BACKEND_INSTALL_DIR="$ICICLE_BACKEND_INSTALL_DIR" python3 - <<'PY'
import os
import sys
repo_root = os.environ["REPO_ROOT"]
sys.path.insert(0, os.path.join(repo_root, "scripts", "python"))
from utils import add_envvar_to_profile
install_dir = os.environ["ICICLE_BACKEND_INSTALL_DIR"]
add_envvar_to_profile("ICICLE_BACKEND_INSTALL_DIR", install_dir)
PY
}
