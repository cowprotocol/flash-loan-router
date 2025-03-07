## Flash-Loan Router

A smart contract that allows CoW Protocol solvers to call `settle` in the context of a flash-loan contract.

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

### Format

```shell
$ forge fmt
```

### Deploy

The deployment [scripts](script) permit the deployment of a single contract or all contracts at once.

#### Deploy a Single Contract

The deploy a single contract, e.g., `FlashLoanRouter.sol` we can use the following command:

```shell
$ forge script script/DeployFlashLoanRouter.s.sol:DeployFlashLoanRouter --rpc-url <your_rpc_url> --private-key <your_private_key>
```

#### Deploy All Contracts

To deploy all contracts, we can use the command below. This will run the deployments for FlashLoanRouter and Borrower contracts specified in the [DeployAllContracts](script/DeployAllContracts.s.sol) script.

```shell
$ forge script script/DeployAllContracts.s.sol:DeployAllContracts --rpc-url <your_rpc_url> --private-key <your_private_key>
```
