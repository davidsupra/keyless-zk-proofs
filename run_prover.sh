export CONFIG_FILE=./prover-service/config_local_testing.yml
export PRIVATE_KEY_0=$(cat ./prover-service/private_key_for_testing.txt)
cargo run -p prover-service
