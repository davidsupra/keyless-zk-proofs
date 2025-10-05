# Icicle GPU Integration for Rapidsnark

This document summarizes how the Icicle GPU backend was wired into the repository and what is required to build and run it.

## Overview

The goal was to keep the existing Rapidsnark code path intact while opportunistically dispatching heavy primitives to Icicle when a compatible CUDA backend is available. The integration touches three areas:

- **Build system** – we build the Icicle C++ project first and link the resulting static libraries into the Rapidsnark static library that `rust-rapidsnark` consumes.
- **C++ bridge** – a small adapter converts between Rapidsnark’s internal field/curve representations and Icicle’s layouts, calls GPU kernels, and falls back to CPU logic on failure.
- **Rust wrapper / prover service** – no API changes were required; the GPU path is transparent to the existing Rust code apart from log messages on prover initialization.

## Build Flow

1. `rust-rapidsnark/rapidsnark/build_lib.sh` now invokes CMake in `third_party/icicle/icicle` to compile the Icicle device, field, and curve libraries for `bn254`. They are built statically (`-DICICLE_STATIC_LINK=ON`) so Meson can link them directly.
2. Meson adds `USE_ICICLE_GPU` to the compiler flags, includes the Icicle headers, and links against `libicicle_device.a`, `libicicle_field_bn254.a`, and `libicicle_curve_bn254.a` found in `third_party/icicle/build`.
3. The `icicle_adapter.cpp` source is compiled into the Rapidsnark static library so the Rust crate can call GPU helpers without exposing Icicle at the Rust level.

## Runtime Behaviour

- On startup `FullProverImpl` attempts to load the GPU backend by calling `aptos::icicle::initialize()`. The helper loads the Icicle CUDA backend from `ICICLE_BACKEND_INSTALL_DIR` (or `/opt/icicle/lib/backend`) and tries to bind CUDA device `0`.
- When a backend is present the prover logs `Initialized icicle GPU backend`; otherwise it logs that the CPU implementation is being used and continues unchanged.
- The adapter exports four functions:
  - `msm_g1`/`msm_g2` – translate bases/scalars to Icicle structs, invoke `icicle::msm`, and convert the result back into the existing `AltBn128::` types.
  - `ntt_forward`/`ntt_inverse` – convert witness data into Icicle scalars, call `icicle::ntt`, and copy the results back. Domains are cached so repeated calls reuse GPU tables.
- `ParallelMultiexp::multiexp` and `FFT::fft/ifft` short-circuit to the adapter and only fall back to TBB-based CPU kernels if the GPU path reports failure.

## Repository Layout

- `third_party/icicle/` – vendored Icicle source and its CMake build scripts.
- `rust-rapidsnark/rapidsnark/src/icicle_adapter.{hpp,cpp}` – bridging layer between Rapidsnark types and Icicle APIs.
- `rust-rapidsnark/rapidsnark/src/{multiexp.cpp,fft.cpp,fullprover.cpp}` – conditional calls into the adapter and logging.
- `rust-rapidsnark/rapidsnark/build_lib.sh` & `meson.build` – updated build logic and link configuration.

## Prerequisites and Setup

1. Install the CUDA toolkit and drivers that match the GPU where the prover will run.
2. Install, or symlink, the Icicle CUDA backend shared libraries to a directory referenced by `ICICLE_BACKEND_INSTALL_DIR` (defaults to `/opt/icicle/lib/backend`). Only the runtime `.so` files are needed at execution time; we ship the static core libraries in-tree.
3. Build via `cargo build -p prover-service`. The script will rebuild Icicle the first time (or whenever the sources change) before Meson compiles Rapidsnark.
4. Run the prover as before (e.g. using `run_prover.sh` or `cargo run`). If the logs indicate the GPU backend could not be initialized the prover still works, but purely on CPU.

## Operational Notes

- Scalars and points are already in Montgomery form inside Rapidsnark, so the adapter marks the Icicle configuration with `are_scalars_montgomery_form = true` and `are_points_montgomery_form = true` to avoid expensive conversions.
- Icicle’s MSM/NTT routines copy host data to device memory internally; we have not added explicit precomputation or async stream handling yet. The first call therefore pays a one-off cost to initialise GPU tables and may take noticeably longer.
- For multi-proof batches the current bridge still copies data per call. Further optimisation (e.g. device-resident buffers or Icicle precomputation APIs) can be layered on without changing the Rust interface.
- The adapter caches NTT domain initialisation per `logn` to avoid redundant GPU setup; the cache is guarded by a mutex for thread safety inside the single-prover process.

## Future Work

- Support alternative devices (e.g. Metal/Vulkan backends) by extending `initialize()` to probe available backends rather than assuming CUDA.
- Offload additional primitives, such as pairing operations or witness preparation, once Icicle exports suitable kernels.
- Expand the build script to allow prebuilt Icicle binaries instead of compiling the third-party source every time when cross-compiling or using CI caches.
