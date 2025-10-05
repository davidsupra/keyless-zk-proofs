use anyhow::{bail, Context, Result};
use rust_rapidsnark::FullProver;
use std::env;
use std::path::PathBuf;

use prover_service::handlers::RapidsnarkProofResponse;

fn resolve_path(env_key: &str, default: &PathBuf) -> PathBuf {
    env::var(env_key)
        .map(PathBuf::from)
        .unwrap_or_else(|_| default.clone())
}

fn ensure_file(label: &str, path: &PathBuf) -> Result<()> {
    if !path.is_file() {
        bail!("{} file not found at {}", label, path.display());
    }
    Ok(())
}

fn main() -> Result<()> {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let default_resources = manifest_dir.join("resources").join("toy_circuit");

    let default_zkey = default_resources.join("toy_1.zkey");
    let default_witness = default_resources.join("toy.wtns");
    let default_vk = default_resources.join("toy_vk.json");

    let zkey_path = resolve_path("GPU_SANITY_ZKEY", &default_zkey);
    let witness_path = resolve_path("GPU_SANITY_WITNESS", &default_witness);
    let vk_path = resolve_path("GPU_SANITY_VK", &default_vk);

    ensure_file("Proving key", &zkey_path)?;
    ensure_file("Witness", &witness_path)?;
    ensure_file("Verifying key", &vk_path)?;

    println!("== GPU sanity check ==");
    println!("Proving key   : {}", zkey_path.display());
    println!("Witness       : {}", witness_path.display());
    println!("Verifying key : {}", vk_path.display());

    match env::var("ICICLE_BACKEND_INSTALL_DIR") {
        Ok(dir) => println!("ICICLE_BACKEND_INSTALL_DIR={}", dir),
        Err(_) => {
            println!("ICICLE_BACKEND_INSTALL_DIR not set; relying on default backend search paths.")
        }
    }

    let zkey = zkey_path
        .to_str()
        .ok_or_else(|| anyhow::anyhow!("Non-UTF8 path: {}", zkey_path.display()))?;
    let witness = witness_path
        .to_str()
        .ok_or_else(|| anyhow::anyhow!("Non-UTF8 path: {}", witness_path.display()))?;

    let prover = FullProver::new(zkey)
        .with_context(|| format!("Failed to load proving key at {}", zkey_path.display()))?;

    let (proof_json, metrics) = prover.prove(witness).with_context(|| {
        format!(
            "Proof generation failed using witness {}",
            witness_path.display()
        )
    })?;

    let _parsed: RapidsnarkProofResponse =
        serde_json::from_str(proof_json).context("Prover returned malformed proof JSON")?;

    println!("Proof generated successfully.");
    println!("Groth16 prover time: {} ms", metrics.prover_time);
    println!("Inspect MyLogFile.log for 'Initialized icicle GPU backend' to confirm GPU usage.");

    Ok(())
}
