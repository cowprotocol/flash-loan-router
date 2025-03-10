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

### Gas benchmarking

This repository includes benchmarking to estimate the gas cost of using the different flash-loan providers.
Benchmark results are generated automatically when running `forge test`.
The generated data can be found in the `snapshots/` folder.

### Format

```shell
$ forge fmt
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```
