# shellcheck shell=bash

load_nvm() {
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  local nvm_sh="$nvm_dir/nvm.sh"
  if [[ -s "$nvm_sh" ]]; then
    export NVM_DIR="$nvm_dir"
    # shellcheck disable=SC1090
    . "$nvm_sh"
    if command -v nvm >/dev/null 2>&1; then
      local had_nounset=0
      if [[ $- == *u* ]]; then
        had_nounset=1
        set +u
      fi

      local have_node_version=0
      if [[ -d "$nvm_dir/versions/node" ]]; then
        local check_dir
        for check_dir in "$nvm_dir"/versions/node/*; do
          if [[ -d "$check_dir/bin" ]]; then
            have_node_version=1
            break
          fi
        done
      fi
      if [[ $have_node_version -eq 0 ]]; then
        if command -v bash >/dev/null 2>&1; then
          log "No nvm-managed Node.js version detected; installing latest Node."
          if ! bash -lc "export NVM_DIR=\"$nvm_dir\"; [ -s \"$nvm_sh\" ] && . \"$nvm_sh\"; nvm install node"; then
            err "Failed to install Node via nvm. Verify nvm installation."
            exit 1
          fi
        else
          err "bash is required to install Node via nvm but is not available."
          exit 1
        fi
        have_node_version=1
      fi
      local target_version=""
      target_version=$(nvm version default 2>/dev/null || true)
      if [[ -z "$target_version" || "$target_version" == "N/A" || "$target_version" == "default" ]]; then
        target_version=$(nvm version node 2>/dev/null || true)
      fi
      if [[ -n "$target_version" && "$target_version" != "N/A" ]]; then
        nvm use "$target_version" >/dev/null 2>&1 || nvm use node >/dev/null 2>&1 || true
      else
        nvm use node >/dev/null 2>&1 || true
      fi
      local active_version=""
      local fallback_version=""
      active_version=$(nvm current 2>/dev/null || true)

      if [[ -z "$active_version" || "$active_version" == "none" || "$active_version" == "system" ]]; then
        fallback_version=$(nvm version node 2>/dev/null || true)
        if [[ -z "$fallback_version" || "$fallback_version" == "N/A" ]]; then
          if [[ -d "$nvm_dir/alias" && -s "$nvm_dir/alias/default" ]]; then
            local alias_target=""
            alias_target=$(head -n 1 "$nvm_dir/alias/default" | tr -d '[:space:]')
            if [[ -n "$alias_target" ]]; then
              fallback_version=$(nvm version "$alias_target" 2>/dev/null || true)
            fi
          fi
        fi
        if [[ -z "$fallback_version" || "$fallback_version" == "N/A" ]]; then
          if [[ -d "$nvm_dir/versions/node" ]]; then
            local version_dir
            for version_dir in "$nvm_dir"/versions/node/*; do
              if [[ -d "$version_dir" ]]; then
                fallback_version=$(basename "$version_dir")
                break
              fi
            done
          fi
        fi
        if [[ -n "$fallback_version" && "$fallback_version" != "N/A" ]]; then
          nvm use "$fallback_version" >/dev/null 2>&1 || true
          active_version=$(nvm current 2>/dev/null || true)
        fi
      fi

      local node_dir=""
      if [[ -n "$active_version" && "$active_version" != "none" && "$active_version" != "system" ]]; then
        local node_path=""
        node_path=$(nvm which "$active_version" 2>/dev/null || true)
        if [[ -n "$node_path" && "$node_path" != "N/A" ]]; then
          node_dir=$(dirname "$node_path")
        fi
      fi

      if [[ -z "$node_dir" || ! -d "$node_dir" ]]; then
        if [[ -n "$fallback_version" && "$fallback_version" != "N/A" && -d "$nvm_dir/versions/node/$fallback_version/bin" ]]; then
          node_dir="$nvm_dir/versions/node/$fallback_version/bin"
          if [[ -z "$active_version" || "$active_version" == "none" || "$active_version" == "system" ]]; then
            active_version="$fallback_version"
          fi
        fi
      fi

      if [[ -z "$node_dir" || ! -d "$node_dir" ]]; then
        if [[ -d "$nvm_dir/versions/node" ]]; then
          local version_dir
          for version_dir in "$nvm_dir"/versions/node/*; do
            if [[ -d "$version_dir/bin" ]]; then
              node_dir="$version_dir/bin"
              if [[ -z "$active_version" || "$active_version" == "none" || "$active_version" == "system" ]]; then
                active_version=$(basename "$version_dir")
              fi
              break
            fi
          done
        fi
      fi

      if [[ -z "$node_dir" || ! -d "$node_dir" ]]; then
        err "nvm failed to activate a Node.js version. Install one with 'nvm install node' before rerunning."
        exit 1
      fi

      log "nvm active version after load: ${active_version:-<none>}"
      if [[ -d "$node_dir" ]]; then
        export PATH="$node_dir:$PATH"
      fi

      if ! command -v npm >/dev/null 2>&1; then
        err "npm not found in PATH even after loading nvm ($active_version)."
        exit 1
      fi

      if [[ $had_nounset -eq 1 ]]; then
        set -u
      fi
    fi
  else
    warn "nvm not found at $nvm_sh. npm-based commands may fail."
  fi
}
