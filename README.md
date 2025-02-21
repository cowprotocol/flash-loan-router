## Flash-Loan Wrapper Solver

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

This repository includes benchmarking to estimate the gas cost of using the different flash-loan wrappers solvers.
Benchmark results are generated automatically when running tests.
The generated data can be found in the `snapshots/` folder.
This data is not checked into this repository.

### Format

```shell
$ forge fmt
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```
