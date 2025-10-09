#include "icicle_adapter.hpp"

#ifdef USE_ICICLE_GPU

#include <icicle/backend/ntt_config.h>
#include <icicle/config_extension.h>
#include <icicle/curves/params/bn254.h>
#include <icicle/msm.h>
#include <icicle/ntt.h>
#include <icicle/runtime.h>

#include <array>
#include <cstring>
#include <mutex>
#include <unordered_set>
#include <vector>

namespace aptos::icicle {

namespace {

using Scalar = bn254::scalar_t;
using G1Affine = bn254::affine_t;
using G1Projective = bn254::projective_t;
using G2Affine = bn254::g2_affine_t;
using G2Projective = bn254::g2_projective_t;

constexpr std::size_t LIMB_COUNT = 4; // number of u64 limbs in raw representation

std::once_flag init_flag;
bool init_success = false;

std::mutex domain_mutex;
std::unordered_set<uint32_t> initialized_domains;

void copy_scalar_to_icicle(const AltBn128::FrElement& src, Scalar& dst)
{
    for (std::size_t i = 0; i < LIMB_COUNT; ++i) {
        dst.limbs_storage.limbs64[i] = src.v[i];
    }
}

void copy_scalar_from_icicle(const Scalar& src, AltBn128::FrElement& dst)
{
    for (std::size_t i = 0; i < LIMB_COUNT; ++i) {
        dst.v[i] = src.limbs_storage.limbs64[i];
    }
}

void copy_fq_to_icicle(const RawFq::Element& src, bn254::point_field_t& dst)
{
    for (std::size_t i = 0; i < LIMB_COUNT; ++i) {
        dst.limbs_storage.limbs64[i] = src.v[i];
    }
}

void copy_fq_from_icicle(const bn254::point_field_t& src, RawFq::Element& dst)
{
    for (std::size_t i = 0; i < LIMB_COUNT; ++i) {
        dst.v[i] = src.limbs_storage.limbs64[i];
    }
}

void copy_f2_to_icicle(const F2Field<RawFq>::Element& src, bn254::g2_point_field_t& dst)
{
    for (std::size_t i = 0; i < LIMB_COUNT; ++i) {
        dst.c0.limbs_storage.limbs64[i] = src.a.v[i];
        dst.c1.limbs_storage.limbs64[i] = src.b.v[i];
    }
}

void copy_f2_from_icicle(const bn254::g2_point_field_t& src, F2Field<RawFq>::Element& dst)
{
    for (std::size_t i = 0; i < LIMB_COUNT; ++i) {
        dst.a.v[i] = src.c0.limbs_storage.limbs64[i];
        dst.b.v[i] = src.c1.limbs_storage.limbs64[i];
    }
}

bool ensure_domain(uint32_t logn)
{
    std::lock_guard<std::mutex> lock(domain_mutex);
    if (initialized_domains.count(logn) != 0) {
        return true;
    }

    Scalar primitive_root = Scalar::omega(logn);
    auto init_cfg = default_ntt_init_domain_config();
    auto status   = ntt_init_domain(primitive_root, init_cfg);
    if (status != eIcicleError::SUCCESS) {
        return false;
    }

    initialized_domains.insert(logn);
    return true;
}

bool is_power_of_two(uint64_t value)
{
    return value != 0 && (value & (value - 1)) == 0;
}

} // namespace

bool initialize()
{
    std::call_once(init_flag, []() {
        if (icicle_load_backend_from_env_or_default() != eIcicleError::SUCCESS) {
            init_success = false;
            return;
        }

        int device_count = 0;
        if (icicle_get_device_count(device_count) != eIcicleError::SUCCESS || device_count <= 0) {
            init_success = false;
            return;
        }

        Device cuda_device("CUDA", 0);
        if (icicle_set_default_device(cuda_device) == eIcicleError::SUCCESS) {
            init_success = true;
            return;
        }

        init_success = false;
    });

    return init_success;
}

bool msm_g1(const AltBn128::G1PointAffine* bases,
            const uint8_t* scalars,
            uint64_t scalar_size,
            uint64_t n,
            AltBn128::G1Point& out)
{
    if (n == 0) {
        AltBn128::Engine::engine.g1.copy(out, AltBn128::Engine::engine.g1.zero());
        return true;
    }

    if (!initialize() || scalar_size != sizeof(AltBn128::FrElement)) {
        return false;
    }

    const auto* scalar_elements = reinterpret_cast<const AltBn128::FrElement*>(scalars);

    std::vector<Scalar> scalar_buffer(n);
    std::vector<G1Affine> base_buffer(n);

    for (uint64_t i = 0; i < n; ++i) {
        copy_scalar_to_icicle(scalar_elements[i], scalar_buffer[i]);
        copy_fq_to_icicle(bases[i].x, base_buffer[i].x);
        copy_fq_to_icicle(bases[i].y, base_buffer[i].y);
    }

    auto config = default_msm_config();
    config.batch_size                 = 1;
    config.are_points_shared_in_batch = true;
    config.are_scalars_on_device      = false;
    config.are_points_on_device       = false;
    config.are_results_on_device      = false;
    config.is_async                   = false;
    config.are_scalars_montgomery_form = true;
    config.are_points_montgomery_form  = true;
    config.bitsize = 254;

    G1Projective result;
    auto status = msm<Scalar, G1Affine, G1Projective>(
        scalar_buffer.data(), base_buffer.data(), static_cast<int>(n), config, &result);

    if (status != eIcicleError::SUCCESS) {
        return false;
    }

    auto& g1 = AltBn128::Engine::engine.g1;
    if (result.z.is_zero()) {
        g1.copy(out, g1.zero());
        return true;
    }

    auto affine = result.to_affine();

    AltBn128::G1PointAffine rs_affine;
    copy_fq_from_icicle(affine.x, rs_affine.x);
    copy_fq_from_icicle(affine.y, rs_affine.y);

    g1.copy(out, rs_affine);
    return true;
}

bool msm_g2(const AltBn128::G2PointAffine* bases,
            const uint8_t* scalars,
            uint64_t scalar_size,
            uint64_t n,
            AltBn128::G2Point& out)
{
    if (n == 0) {
        AltBn128::Engine::engine.g2.copy(out, AltBn128::Engine::engine.g2.zero());
        return true;
    }

    if (!initialize() || scalar_size != sizeof(AltBn128::FrElement)) {
        return false;
    }

    const auto* scalar_elements = reinterpret_cast<const AltBn128::FrElement*>(scalars);

    std::vector<Scalar> scalar_buffer(n);
    std::vector<G2Affine> base_buffer(n);

    for (uint64_t i = 0; i < n; ++i) {
        copy_scalar_to_icicle(scalar_elements[i], scalar_buffer[i]);
        copy_f2_to_icicle(bases[i].x, base_buffer[i].x);
        copy_f2_to_icicle(bases[i].y, base_buffer[i].y);
    }

    auto config = default_msm_config();
    config.batch_size                 = 1;
    config.are_points_shared_in_batch = true;
    config.are_scalars_on_device      = false;
    config.are_points_on_device       = false;
    config.are_results_on_device      = false;
    config.is_async                   = false;
    config.are_scalars_montgomery_form = true;
    config.are_points_montgomery_form  = true;
    config.bitsize = 254;

    G2Projective result;
    auto status = msm<Scalar, G2Affine, G2Projective>(
        scalar_buffer.data(), base_buffer.data(), static_cast<int>(n), config, &result);

    if (status != eIcicleError::SUCCESS) {
        return false;
    }

    auto& g2 = AltBn128::Engine::engine.g2;
    if (result.z.c0.is_zero() && result.z.c1.is_zero()) {
        g2.copy(out, g2.zero());
        return true;
    }

    auto affine = result.to_affine();

    AltBn128::G2PointAffine rs_affine;
    copy_f2_from_icicle(affine.x, rs_affine.x);
    copy_f2_from_icicle(affine.y, rs_affine.y);

    g2.copy(out, rs_affine);
    return true;
}

bool ntt_forward(AltBn128::FrElement* data, uint64_t size)
{
    if (!initialize() || !is_power_of_two(size) || size == 0) {
        return false;
    }

    uint32_t logn = 0;
    while ((1ull << logn) < size) {
        ++logn;
    }

    if (!ensure_domain(logn)) {
        return false;
    }

    std::vector<Scalar> buffer(size);
    for (uint64_t i = 0; i < size; ++i) {
        copy_scalar_to_icicle(data[i], buffer[i]);
    }

    auto config = default_ntt_config<Scalar>();
    config.batch_size            = 1;
    config.are_inputs_on_device  = false;
    config.are_outputs_on_device = false;
    config.is_async              = false;
    config.ordering              = Ordering::kNN;

    auto status = ntt(buffer.data(), static_cast<int>(size), NTTDir::kForward, config, buffer.data());
    if (status != eIcicleError::SUCCESS) {
        return false;
    }

    for (uint64_t i = 0; i < size; ++i) {
        copy_scalar_from_icicle(buffer[i], data[i]);
    }

    return true;
}

bool ntt_inverse(AltBn128::FrElement* data, uint64_t size)
{
    if (!initialize() || !is_power_of_two(size) || size == 0) {
        return false;
    }

    uint32_t logn = 0;
    while ((1ull << logn) < size) {
        ++logn;
    }

    if (!ensure_domain(logn)) {
        return false;
    }

    std::vector<Scalar> buffer(size);
    for (uint64_t i = 0; i < size; ++i) {
        copy_scalar_to_icicle(data[i], buffer[i]);
    }

    auto config = default_ntt_config<Scalar>();
    config.batch_size            = 1;
    config.are_inputs_on_device  = false;
    config.are_outputs_on_device = false;
    config.is_async              = false;
    config.ordering              = Ordering::kNN;

    auto status = ntt(buffer.data(), static_cast<int>(size), NTTDir::kInverse, config, buffer.data());
    if (status != eIcicleError::SUCCESS) {
        return false;
    }

    for (uint64_t i = 0; i < size; ++i) {
        copy_scalar_from_icicle(buffer[i], data[i]);
    }

    return true;
}

} // namespace aptos::icicle

#endif // USE_ICICLE_GPU
