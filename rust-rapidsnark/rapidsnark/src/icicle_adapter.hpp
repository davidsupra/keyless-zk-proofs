#pragma once

#include <cstdint>

#include "alt_bn128.hpp"

namespace aptos::icicle {

#ifdef USE_ICICLE_GPU

bool initialize();

bool msm_g1(const AltBn128::G1PointAffine* bases,
            const uint8_t* scalars,
            uint64_t scalar_size,
            uint64_t n,
            AltBn128::G1Point& out);

bool msm_g2(const AltBn128::G2PointAffine* bases,
            const uint8_t* scalars,
            uint64_t scalar_size,
            uint64_t n,
            AltBn128::G2Point& out);

bool ntt_forward(AltBn128::FrElement* data, uint64_t size);
bool ntt_inverse(AltBn128::FrElement* data, uint64_t size);

#else

inline bool initialize() { return false; }

inline bool
msm_g1(const AltBn128::G1PointAffine*, const uint8_t*, uint64_t, uint64_t, AltBn128::G1Point&) { return false; }

inline bool
msm_g2(const AltBn128::G2PointAffine*, const uint8_t*, uint64_t, uint64_t, AltBn128::G2Point&) { return false; }

inline bool ntt_forward(AltBn128::FrElement*, uint64_t) { return false; }
inline bool ntt_inverse(AltBn128::FrElement*, uint64_t) { return false; }

#endif

} // namespace aptos::icicle
