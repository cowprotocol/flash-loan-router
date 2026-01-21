# Flash-Loan Router

A smart contract that allows CoW-Protocol solvers to execute a settlement with the ability to use funds from one or more flash loans.

# Ethereum addresses

The flash-loan router is introduced as part of the protocol with [CIP 66](https://snapshot.box/#/s:cow.eth/proposal/0x6f3d88347bcc8de87ecded2442c090d8eb1d3ef99eca75a831ee220ff5705f00).
All contracts are deployed deterministically with `CREATE2` and have the same address on all supported networks.

- FlashLoanRouter: `0x9da8B48441583a2b93e2eF8213aAD0EC0b392C69`
- AaveBorrower: `0x7d9C4DeE56933151Bc5C909cfe09DEf0d315CB4A`
- ERC3156Borrower: `0x47d71b4B3336AB2729436186C216955F3C27cD04`

See [networks.json](./networks.json) for details.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

To exclude tests requiring an internet connection:

```shell
$ forge test --no-match-path 'test/e2e/**/*'
```

### Gas benchmarking

This repository includes benchmarking to estimate the gas cost of using the different flash-loan providers.
Benchmark results are generated automatically when running `forge test`.
The generated data can be found in the `snapshots/` folder.

### Format

```shell
$ forge fmt
```

### Deploy

For deploying on a new network, there are two steps:

1. [Deploy all contracts.](#deploy-all-contracts)
2. [Update the `networks.json` file.](#deployment-addresses)

For deploying new contracts on an existing network, the deployment [scripts](script) permit the deployment of a single contract or all contracts at once.
The networks.json file needs to be updated as linked above.

#### Environment setup

Copy the `.env.example` to `.env` and set the applicable configuration variables for the testing / deployment environment.


#### Deploy All Contracts

Deployment is handled by solidity scripts in `forge`. The network being deployed to is dependent on the `ETH_RPC_URL`.

To deploy all contracts in a single run, the [DeployAllContracts](script/DeployAllContracts.s.sol) script is used. This will run the deployments for FlashLoanRouter and Borrower contracts specified in the script.

```shell
source .env

# Dry-run the deployment
forge script script/DeployAllContracts.s.sol:DeployAllContracts --rpc-url $ETH_RPC_URL --private-key $PRIVATE_KEY 

# Broadcast the deployment
#   Don't forget to add the --verify flag
#   For Etherscan verification, ensure that the `ETHERSCAN_API_KEY` environment variable is set
forge script script/DeployAllContracts.s.sol:DeployAllContracts --rpc-url $ETH_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

For Etherscan verification, ensure that the `ETHERSCAN_API_KEY` environment variable is set and add the `--verify` flag to the `forge script` deployment commands.

#### Verification of deployed contracts
To verify an already deployed contract, you can use the `forge verify-contract` command.

```shell
# Verify FlashLoanRouter
forge verify-contract 0x9da8B48441583a2b93e2eF8213aAD0EC0b392C69 src/FlashLoanRouter.sol:FlashLoanRouter  --chain-id $CHAIN_ID --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $(cast abi-encode "constructor(address)" 0x9008D19f58AAbD9eD0D60971565AA8510560ab41)

# Verify AaveBorrower
forge verify-contract 0x7d9C4DeE56933151Bc5C909cfe09DEf0d315CB4A src/AaveBorrower.sol:AaveBorrower --chain-id $CHAIN_ID --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $(cast abi-encode "constructor(address)" 0x9da8B48441583a2b93e2eF8213aAD0EC0b392C69)

# Verify ERC3156Borrower
forge verify-contract 0x47d71b4B3336AB2729436186C216955F3C27cD04 src/ERC3156Borrower.sol:ERC3156Borrower --chain-id $CHAIN_ID --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $(cast abi-encode "constructor(address)" 0x9da8B48441583a2b93e2eF8213aAD0EC0b392C69)

```

#### Deploy a Single Contract

To deploy a single contract, the scripts within the [script/single-deployment](script/single-deployment) directory are used, e.g., to deploy the `FlashLoanRouter.sol` contract, the command below is used:

```shell
source .env

forge script script/single-deployment/DeployFlashLoanRouter.s.sol:DeployFlashLoanRouter --rpc-url $ETH_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

#### Deployment addresses

The file [`networks.json`](./networks.json) lists all official deployments of the contracts in this repository by chain id.

This file is generated automatically using the broadcast files in the `broadcast/` directory.

Most of the deployments are done using the `forge` script as described in this README, however, some networks might be deployed in some other way (like replaying the creation code and constructor arguments). For these, we will need to manually update the file `broadcast/networks-manual.json`.

To regenerate the file after a new deployment, run the following command:

```sh
bash script/generate-networks-file.sh > networks.json
```
