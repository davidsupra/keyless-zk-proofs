# shellcheck shell=bash

perform_circuit_setup() {
  local repo_root="$1"
  local custom_resources_dir="$2"

  load_nvm
  log "Installing npm dependencies for circuit"
  (cd "$repo_root/circuit" && npm install)

  local circom_cmd=(circom --O2 -l templates -l "$(npm root -g)" templates/main.circom --r1cs --wasm --c --sym)
  log "Compiling main circuit with: ${circom_cmd[*]}"
  (cd "$repo_root/circuit" && "${circom_cmd[@]}")

  if [[ -d "$repo_root/circuit/main_c_cpp" ]]; then
    log "Building C witness generator"
    (cd "$repo_root/circuit/main_c_cpp" && make)
  fi

  if [[ -n "$custom_resources_dir" ]]; then
    export RESOURCES_DIR="$custom_resources_dir"
  fi
  log "Procuring testing setup (this may take several minutes)"
  "$repo_root/scripts/task.sh" setup procure-testing-setup || warn "Testing setup procurement failed; rerun if proofs are required."
}
