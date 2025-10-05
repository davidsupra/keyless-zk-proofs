#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run_gpu_sanity.sh [--skip-log-check]

Runs a minimal proof with the Icicle-enabled prover to verify that the GPU backend works.
Environment overrides:
  GPU_SANITY_ZKEY    Path to the Groth16 proving key (defaults to prover-service/resources/toy_circuit/toy_1.zkey)
  GPU_SANITY_WITNESS Path to the witness file (defaults to prover-service/resources/toy_circuit/toy.wtns)
  GPU_SANITY_VK      Path to the verifying key (defaults to prover-service/resources/toy_circuit/toy_vk.json)

Exit codes:
  0 - Proof generated and GPU backend confirmed
  1 - Proof generated but GPU status could not be determined
  2 - Proof generated but GPU backend was not used (CPU fallback)
  3 - Proof generation failed
USAGE
}

SKIP_LOG_CHECK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-log-check)
      SKIP_LOG_CHECK=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[gpu-sanity][error] Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
LOG_FILE="${REPO_ROOT}/MyLogFile.log"

if [[ -f "$LOG_FILE" ]]; then
  rm -f "$LOG_FILE"
fi

if [[ -z "${ICICLE_BACKEND_INSTALL_DIR:-}" ]]; then
  printf '[gpu-sanity][warn] ICICLE_BACKEND_INSTALL_DIR not set; relying on default search paths.\n'
fi

set +e
(
  cd "$REPO_ROOT" && cargo run --quiet -p prover-service --bin gpu_sanity
)
RUN_STATUS=$?
set -e

if [[ $RUN_STATUS -ne 0 ]]; then
  printf '[gpu-sanity][error] Proof generation failed (exit code %d).\n' "$RUN_STATUS" >&2
  exit 3
fi

if [[ $SKIP_LOG_CHECK -eq 1 ]]; then
  printf '[gpu-sanity][info] Proof completed; log inspection skipped.\n'
  exit 0
fi

if [[ ! -f "$LOG_FILE" ]]; then
  printf '[gpu-sanity][warn] Proof succeeded but %s was not created; cannot confirm GPU usage.\n' "$LOG_FILE" >&2
  exit 1
fi

if grep -q 'Initialized icicle GPU backend' "$LOG_FILE"; then
  printf '[gpu-sanity][info] GPU backend initialized successfully.\n'
  exit 0
fi

if grep -q 'icicle GPU backend unavailable; using CPU implementation' "$LOG_FILE"; then
  printf '[gpu-sanity][warn] Proof succeeded but prover fell back to the CPU implementation.\n'
  exit 2
fi

printf '[gpu-sanity][warn] GPU status string not found in %s; inspect manually.\n' "$LOG_FILE" >&2
exit 1
