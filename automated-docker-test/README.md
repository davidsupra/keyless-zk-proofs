
This folder contains resources that allow for running an automated test of
a prover service docker image. Specifically, it contains:

- a rust crate that sets up the test and allows for making requests
- a Dockerfile that defines a mock-on-chain and mock-OIDC service that the
  prover service will query
- a Dockerfile that performs the test
- a docker compose file `test_deployment.yml` which orchestrates the
  running of the test
