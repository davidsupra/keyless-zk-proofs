# shellcheck shell=bash

load_nvm() {
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  local nvm_sh="$nvm_dir/nvm.sh"
  if [[ -s "$nvm_sh" ]]; then
    export NVM_DIR="$nvm_dir"
    # shellcheck disable=SC1090
    . "$nvm_sh"
    if command -v nvm >/dev/null 2>&1; then
      local target_version=""
      target_version=$(nvm version default 2>/dev/null || true)
      if [[ -z "$target_version" || "$target_version" == "N/A" ]]; then
        target_version=$(nvm version node 2>/dev/null || true)
      fi
      if [[ -n "$target_version" && "$target_version" != "N/A" ]]; then
        nvm use "$target_version" >/dev/null 2>&1 || true
      else
        nvm use node >/dev/null 2>&1 || true
      fi
      local active_version=""
      active_version=$(nvm current 2>/dev/null || true)
      log "nvm active version after load: ${active_version:-<none>}"
      if [[ -n "$active_version" && "$active_version" != "none" && "$active_version" != "system" ]]; then
        local node_path=""
        node_path=$(nvm which "$active_version" 2>/dev/null || true)
        if [[ -n "$node_path" && "$node_path" != "N/A" ]]; then
          local node_dir
          node_dir=$(dirname "$node_path")
          if [[ -d "$node_dir" ]]; then
            export PATH="$node_dir:$PATH"
          fi
        fi
      fi
    fi
  else
    warn "nvm not found at $nvm_sh. npm-based commands may fail."
  fi
}
