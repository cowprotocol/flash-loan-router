#!/bin/bash

set -o errexit -o pipefail -o nounset

repo_root_dir="$(git rev-parse --show-toplevel)"

for deployment in "$repo_root_dir/broadcast/"*"/"*"/"*".json"; do
  # Extract the chain ID from the folder structure
  chain_id=${deployment%/*}
  chain_id=${chain_id##*/}

  # Process each deployment file and format it correctly
  jq --arg chainId "$chain_id" '
    .transactions[]
    | select(.transactionType == "CREATE")
    | select(.hash != null)
    | {(.contractName): {($chainId): {address: .contractAddress, transactionHash: .hash }}}
  ' <"$deployment"
done \
  | # Merge all contracts ensuring multiple chains are properly stored
    jq --sort-keys --null-input '
      reduce inputs as $item ({}; 
        . as $orig | 
        reduce ($item | to_entries[]) as $kv ($orig; 
          .[$kv.key] += $kv.value
        )
      )'
