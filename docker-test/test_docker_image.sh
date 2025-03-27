#!/bin/bash

echo "" > ./test/testing_envvars.txt
echo "ONCHAIN_GROTH16_VK_URL=http://mock-on-chain:4444/groth16_vk.json" >> ./test/testing_envvars.txt
echo "ONCHAIN_TW_VK_URL=http://mock-on-chain:4444/keyless_config.json" >> ./test/testing_envvars.txt
echo "PRIVATE_KEY_0=$(cat ./prover-service/private_key_for_testing.txt)" >> ./test/testing_envvars.txt
echo "PRIVATE_KEY_1=$(cat ./prover-service/private_key_for_testing_another.txt)" >> ./test/testing_envvars.txt

pushd prover-service
LOCAL_VK_IN=~/.local/share/aptos-prover-service/default/verification_key.json ONCHAIN_VK_OUT=groth16_vk.json cargo test groth16_vk_rewriter
LOCAL_TW_VK_IN=private_key_for_testing.txt ONCHAIN_KEYLESS_CONFIG_OUT=keyless_config.json cargo test tw_vk_rewriter
popd

sudo docker compose -f ./docker-test/test_deployment.yml up




