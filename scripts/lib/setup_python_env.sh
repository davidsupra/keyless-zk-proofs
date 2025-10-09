# shellcheck shell=bash

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

select_poetry_python() {
  local candidates=()
  if [[ -n "${POETRY_PYTHON:-}" ]]; then
    candidates+=("$POETRY_PYTHON")
  fi
  candidates+=(python3.12 python3.11 python3)
  for candidate in "${candidates[@]}"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
        command -v "$candidate"
        return 0
      fi
    fi
  done
  return 1
}

install_python_via_apt() {
  if [[ $EUID -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    warn "Need root privileges or sudo access to install Python via apt-get."
    return 1
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    return 1
  fi
  log "Attempting to install Python 3.11 via apt-get"
  local apt_cmd=(apt-get)
  if [[ $EUID -ne 0 ]]; then
    apt_cmd=(sudo apt-get)
  fi
  "${apt_cmd[@]}" update
  if "${apt_cmd[@]}" install -y python3.11 python3.11-venv python3.11-distutils; then
    return 0
  fi
  warn "Direct apt install of python3.11 failed; trying deadsnakes PPA"
  if ! command -v add-apt-repository >/dev/null 2>&1; then
    "${apt_cmd[@]}" install -y software-properties-common
  fi
  local add_repo_cmd=(add-apt-repository)
  if [[ $EUID -ne 0 ]]; then
    add_repo_cmd=(sudo add-apt-repository)
  fi
  if ! command -v add-apt-repository >/dev/null 2>&1; then
    warn "add-apt-repository not available; cannot add deadsnakes PPA automatically."
    return 1
  fi
  "${add_repo_cmd[@]}" -y ppa:deadsnakes/ppa
  "${apt_cmd[@]}" update
  "${apt_cmd[@]}" install -y python3.11 python3.11-venv python3.11-distutils
}

install_python_via_conda() {
  local conda_dir="${HOME}/miniconda3"
  local conda_bin="$conda_dir/bin/conda"
  local python_env_path="$conda_dir/envs/keyless-poetry"

  if [[ ! -x "$conda_bin" ]]; then
    local system
    local arch
    system=$(uname -s)
    arch=$(uname -m)
    local installer=""
    case "${system}_${arch}" in
      Linux_x86_64)
        installer="Miniconda3-latest-Linux-x86_64.sh"
        ;;
      Linux_aarch64|Linux_arm64)
        installer="Miniconda3-latest-Linux-aarch64.sh"
        ;;
      Darwin_x86_64)
        installer="Miniconda3-latest-MacOSX-x86_64.sh"
        ;;
      Darwin_arm64)
        installer="Miniconda3-latest-MacOSX-arm64.sh"
        ;;
      *)
        warn "Unsupported platform ${system}/${arch} for Miniconda bootstrap."
        return 1
        ;;
    esac
    local installer_url="https://repo.anaconda.com/miniconda/${installer}"
    log "Downloading Miniconda installer (${installer})"
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN
    if ! curl -fsSL "$installer_url" -o "${tmpdir}/${installer}"; then
      warn "Failed to download Miniconda installer from $installer_url"
      return 1
    fi
    log "Installing Miniconda into ${conda_dir}"
    bash "${tmpdir}/${installer}" -b -p "$conda_dir"
    rm -rf "$tmpdir"
    trap - RETURN
    if [[ ! -x "$conda_bin" ]]; then
      warn "Miniconda install did not produce ${conda_bin}"
      return 1
    fi
  fi

  log "Accepting Miniconda terms of service for automated use"
  "$conda_bin" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main >/dev/null 2>&1 || true
  "$conda_bin" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r >/dev/null 2>&1 || true

  if [[ ! -x "$python_env_path/bin/python" ]]; then
    log "Creating Python 3.11 environment via conda at ${python_env_path}"
    if ! "$conda_bin" create -y -p "$python_env_path" python=3.11 >/dev/null 2>&1; then
      warn "Conda environment creation failed. Check conda configuration."
      return 1
    fi
  fi

  if [[ -x "$python_env_path/bin/python" ]]; then
    export POETRY_PYTHON="$python_env_path/bin/python"
    log "Prepared conda-managed python at ${POETRY_PYTHON}"
    return 0
  fi

  warn "Conda environment did not produce a usable python interpreter."
  return 1
}

resolve_poetry_python() {
  local selected
  RESOLVED_PYTHON_CMD=""
  selected=$(select_poetry_python || true)
  if [[ -n "$selected" ]]; then
    RESOLVED_PYTHON_CMD="$selected"
    return 0
  fi

  local providers=()
  case "$PYTHON_PROVIDER" in
    apt)
      providers=(apt)
      ;;
    conda)
      providers=(conda)
      ;;
    auto)
      providers=(apt conda)
      ;;
  esac

  local provider
  for provider in "${providers[@]}"; do
    case "$provider" in
      apt)
        if install_python_via_apt; then
          selected=$(select_poetry_python || true)
          if [[ -n "$selected" ]]; then
            RESOLVED_PYTHON_CMD="$selected"
            return 0
          fi
        else
          if command -v apt-get >/dev/null 2>&1; then
            warn "Automatic installation of Python 3.11 via apt-get failed."
          fi
        fi
        ;;
      conda)
        if install_python_via_conda; then
          selected=$(select_poetry_python || true)
          if [[ -n "$selected" ]]; then
            RESOLVED_PYTHON_CMD="$selected"
            return 0
          fi
        else
          warn "Automatic installation of Python 3.11 via conda failed."
        fi
        ;;
    esac
  done
  RESOLVED_PYTHON_CMD=""
  return 1
}
