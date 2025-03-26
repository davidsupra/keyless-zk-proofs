
use std::fs::{self, File};
use std::io::Write;
use std::path::Path;
use std::process::Command;

use prover_service::groth16_vk::SnarkJsGroth16VerificationKey;
use prover_service::tests::common;
use prover_service::tests::common::types;
use aptos_crypto::ValidCryptoMaterialStringExt;

fn ceremony_dir_exists(release_tag: &str) -> bool {

    Path::new(
        shellexpand::tilde(
            &format!("~/.local/share/aptos-keyless/ceremonies/{}", release_tag)
        ).as_ref()
    ).is_dir()
}

fn ceremony_vk_path(release_tag: &str) -> String {
    shellexpand::tilde(
        &format!("~/.local/share/aptos-keyless/ceremonies/{}/verification_key.json", release_tag)
    ).to_string()
}

fn main() {
    // DEFAULT FLOW
    // ============
    //
    // take as input:
    // - release, "default" or "new" tag
    
    
    // download release using script if not present
    // generate tw keypair
    // generate jwk keypair

    // write out envvar file: (these envvars must be passed to prover service):w
    // - ONCHAIN_GROTH16_VK_URL=http://mock-on-chain:4444/groth16_vk.json
    // - ONCHAIN_TW_VK_URL=http://mock-on-chain:4444/keyless_config.json
    // - PRIVATE_KEY_0=0x8c75cacb54de1af0bd7b6c0549548b8d39a8177320f46ca5f767e5ed603dc08b
    // - PRIVATE_KEY_1=0x6bf4bd737ac8cc87841b5e83d396ff4e9197b014b7b395434d09c5828cca0e1d
    // - OIDC_PROVIDERS="[ { iss='test.oidc.provider', endpoint_url='http://mock-on-chain:4444/jwk.json' } ]"

    // output files:
    // /groth16_vk.json: vk for the release, can use cargo test code to generate DONE
    // /keyless_config.json: contains training wheels VK? (can also gen using cargo test code) DONE
    // /jwk.json: generate using jwk keypair
    // /jwk_sk.txt: jwk sk, used during testing to sign jwt
    // /tw_vk.txt: tw vk, used during testing to verify prover service response
    //
    //
    // SIGN FLOW
    // =========
    // take as input:
    // - jwk_sk.txt
    // - tw_vk.txt 
    //
    // output prover service request
    
    let command = std::env::args().nth(1).expect("No command given. Expected \"prepare-test\" or \"generate-request\"");

    if command == "prepare-test" {
        let release_tag = std::env::args().nth(2).expect("no path given");
        let mut envvars = vec![];

        if ! ceremony_dir_exists(&release_tag) {
            Command::new("../scripts/task.sh")
                .args(["setup", "download-ceremonies-for-releases", &release_tag, &release_tag])
                .status()
                .expect("Setup download task.sh action failed");

            assert!(ceremony_dir_exists(&release_tag));
        } 


        // Generate tw keypair and write tw sk/vk files/envvars
        let tw_keypair = prover_service::tests::common::gen_test_training_wheels_keypair();
        prover_service::prover_key::write_tw_on_chain_repr_json(&tw_keypair, "keyless_config.json");
        fs::write("tw_vk.txt", &tw_keypair.verification_key.to_encoded_string().unwrap()).unwrap();
        envvars.push(format!("PRIVATE_KEY_0={}", &tw_keypair.signing_key.to_encoded_string().unwrap()));
        envvars.push(format!("PRIVATE_KEY_1={}", &tw_keypair.signing_key.to_encoded_string().unwrap()));

        // Convert verification_key.json output by snarkjs into the on-chain-config format
        let local_vk_json = std::fs::read_to_string(ceremony_vk_path(&release_tag)).unwrap();
        let local_vk: SnarkJsGroth16VerificationKey = serde_json::from_str(&local_vk_json).unwrap();
        prover_service::groth16_vk::write_vk_onchain_repr_file(local_vk, "groth16_vk.json");

        fs::write("envvars.env", envvars.join("\n")).unwrap();
    }

}
