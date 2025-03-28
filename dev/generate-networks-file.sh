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
  | # Merge all the deployments from different contract files
    jq --sort-keys --null-input 'reduce inputs as $item ({}; . *= $item)'
