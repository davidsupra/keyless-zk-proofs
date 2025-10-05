#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
ICICLE_DIR="${REPO_ROOT}/third_party/icicle"
ICICLE_BUILD_DIR="${ICICLE_DIR}/build"

echo "[build_lib] Building icicle libraries"
cmake -S "${ICICLE_DIR}/icicle" -B "${ICICLE_BUILD_DIR}" \
  -DCURVE=bn254 \
  -DICICLE_STATIC_LINK=ON \
  -DBUILD_TESTS=OFF \
  -DCPU_BACKEND=ON
cmake --build "${ICICLE_BUILD_DIR}" --target icicle_curve icicle_field icicle_device -j

echo "[build_lib] Building rapidsnark library"
rm -rf "${SCRIPT_DIR}/build"
meson setup --native-file=native-env.ini build
cd build
meson compile
