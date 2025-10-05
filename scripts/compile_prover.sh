#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[compile] %s\n' "$*"
}

err() {
  printf '[compile][error] %s\n' "$*" >&2
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
NATIVE_FILE="${REPO_ROOT}/rust-rapidsnark/rapidsnark/native-env.ini"

if [[ ! -f "$NATIVE_FILE" ]]; then
  err "native-env.ini not found at $NATIVE_FILE"
  exit 1
fi

if ! command -v cargo >/dev/null 2>&1; then
  err "cargo not found in PATH"
  exit 1
fi

NASM_BIN="${NASM:-}"
if [[ -z "$NASM_BIN" ]]; then
  NASM_BIN=$(command -v nasm || true)
fi

if [[ -z "$NASM_BIN" ]]; then
  err "nasm not found; install it or export NASM=/path/to/nasm"
  exit 1
fi

export NASM_BIN
python3 - "$NATIVE_FILE" <<'PY'
import os
import sys
from pathlib import Path

nasm_path = os.environ["NASM_BIN"]
config = Path(sys.argv[1])
lines = config.read_text().splitlines()
updated = False
for idx, line in enumerate(lines):
    if line.strip().startswith("nasm"):
        if lines[idx].strip() != f"nasm = '{nasm_path}'":
            lines[idx] = f"nasm = '{nasm_path}'"
        updated = True
        break
if not updated:
    lines.append(f"nasm = '{nasm_path}'")
config.write_text("\n".join(lines) + "\n")
PY

log "Using nasm at $NASM_BIN"

if [[ $# -eq 0 ]]; then
  CARGO_ARGS=(-p prover-service)
else
  CARGO_ARGS=("$@")
fi

log "Invoking cargo build ${CARGO_ARGS[*]}"
(
  cd "$REPO_ROOT" && cargo build "${CARGO_ARGS[@]}"
)
