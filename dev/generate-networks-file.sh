#!/bin/bash

set -o errexit -o pipefail -o nounset

repo_root_dir="$(git rev-parse --show-toplevel)"

# Iterate over each deployment JSON file in the broadcast directory
for deployment in "$repo_root_dir/broadcast/"*"/"*"/"*".json"; do
  # The subfolder name is the chain ID
  chain_id=${deployment%/*}
  chain_id=${chain_id##*/}

  # Process the deployments and format the output
  jq --arg chainId "$chain_id" '
    .transactions[]
    | select(.transactionType == "CREATE2")
    | select(.hash != null)
    | {(.contractName): [
        {
          chainId: $chainId,
          contractAddress: .contractAddress,
          transactionHash: .hash
        }
      ]}
  ' <"$deployment"
done \
  | # Then, all these single-contract single-chain-id networks.jsons are merged. Note: in case the same contract is
    # deployed twice in the same script run, the last deployed contract takes priority.
    # If the same contract is deployed twice in different runs, the address in the file path that comes latest in
    # alphabetical order takes priority. For example, a contract in `broadcast/Deployment10/*` is overwritten by
    # one with the same name from `broadcast/Deployment2/*`.
    jq --sort-keys --null-input 'reduce inputs as $item ({}; . *= $item)'
