# Flash-Loan Router

A smart contract that allows CoW-Protocol solvers to execute a settlement with the ability to use funds from one or more flash loans.

## Design

The flash-loan router lets a solver specify a list of flash-loan requests as well as a settlement to be executed with the proceeds of those loans.

Any registered CoW-Protocol solver can use this contract to execute settlements by proxy.

The entry point to the [router](src/FlashLoanRouter.sol) is the function `flashLoanAndSettle`.
It takes a list of loans with the following entries for each loan:

- The loaned amount and ERC-20 token.
- The flash-loan lender (e.g., Balancer, Aave, Maker, ...).
- The _borrower_, which is an adapter contract that makes the specific lender implementation compatible with the router.

It also takes the exact call data for a call to `settle`.
The flash-loan router is a solver for CoW Protocol and calls `settle` directly once the flash loans have been obtained.
Only CoW-Protocol solvers can call this function.
Solver authentication is done by interrogating the same contract that manages solver authentication for the settlement contract.

Tokens and lenders are external contracts, while the router and each specific borrowers are dedicated contract implemented in this repository.

The borrowers are the contracts that are called back by the lender once the flash loan is initiated; they are the contracts that receive the flash-loan proceeds and that are eventually responsible to repay the loan.

The only way to move funds out of a borrower is through an ERC-20 approval for some spender.
Approvals can be set by calling the `approve` function on the borrower from the context of a settlement.
For safe operations, like an approval for the settlement contract to spend the funds of the borrower, it's enough to set the approval once for an unlimited amount and reuse the same approval in future settlements.

At the start of the settlement, it's expected that the loaned funds are transferred from the borrowers to where they are needed. For example, this can be the settlement contract itself, or the address of a user who wants to use the loan to retrieve the collateral needed to avoid liquidations.
In general, solvers have full flexibility in deciding how loaned funds are allocated.

The settlement is also reponsible for repaying the flash loans.
The specific repayment mechanism depends on the lender, but a common process is having the settlement contract send back the borrowed funds to the borrower and set an approval to the lender for spending the funds of the borrower: then the lender is going to pull back the funds with an ERC-20 `transferFrom` after the settlement is terminated.
Inability to pay for a flash loan will most likely be met by a reverting transaction.

We support the following flash-loan lenders:

- Any lender that is compatible with [ERC-3156](https://eips.ethereum.org/EIPS/eip-3156) interface (for example [Maker](https://docs.makerdao.com/smart-contract-modules/flash-mint-module)).
- [Aave](https://aave.com/docs/developers/flash-loans#overview).

Support for further flash-loan lenders can be added in the future.

This repository provides an abstract `Borrower` implementation that encodes much of the logic expected from a borrower.
Concrete borrower implementations can be built by inheriting this contract and implementing two functions: `triggerFlashLoan`, which describes how to call the lender to request a flash loan, and the lender-specific call-back function that internallly forwards the call to `Borrower.flashLoanCallBack`.

### Example: a settlement with two loans, Aave and Maker

We describe an example of how to execute a settlement after borrowing two flash loans (from Aave and Maker) through the flash-loan router.

The following diagram is a simplified description of the expected calls in the execution process.
Each line is a call from the originating contract to the target contract.
Note that the call context is never given up in the diagram: each new call just increase the current call depth.
All calls are terminated at the end, after the settlement is executed.

```mermaid
sequenceDiagram
  CoW-Protocol solver ->> flash-loan router: flashLoanAndSettle()
  flash-loan router ->> Aave borrower: flashLoanAndCallBack()
  Aave borrower ->> Aave lender contract: Aave-specific flash loan request
  Aave lender contract ->> Aave borrower: Aave-specific flash loan callback
  Aave borrower ->> flash-loan router: borrowerCallBack()
  flash-loan router ->> Maker borrower: flashLoanAndCallBack()
  Maker borrower ->> Maker lender contract: Maker-specific flash loan request
  Maker lender contract ->> Maker borrower: Maker-specific flash loan callback
  Maker borrower ->> flash-loan router: borrowerCallBack()
  flash-loan router ->> CoW Settlement: settle()
```

The lenders are external contracts, not managed by this repository.

## Security model

### Router

The key security property of the router is that a solver is always in control of the data that is executed by the settlement contract.
The only way to execute a settlement through this contract is by having a registered solver call `flashLoanAndSettle` and including the exact settlement call data in the input to the call.

In particular, this means that:

- `flashLoanAndSettle` can only be called by a solver (that is not the router);
- a single call to `flashLoanAndSettle` leads to exactly one call to `settle`;
- the call to `settle` matches the data used in `flashLoanAndSettle`;

and this is also the case if any of the tokens, lenders, as well as borrowers involved are controlled by an adversary.

The flash-loan router also requests flash loans in the order they have been provided to `flashLoanAndSettle`.
Out-of-order execution eventually leads to a transaction revert.

A malicious party in the execution (token, lender, or borrower) is, however, able to disrupt the successful execution of a settlement by changing the chain state before the point of the `settle` call.
This could be either by triggering a revert or by exploiting the slippage tolerance in a solver's settlement.
This doesn't impact the security of user's funds but it increases the risks for solvers when relying on these contracts.
Assuming that the token, lender and borrower contracts are trusted, those risks should be comparable to the normal risks of executing a normal settlement.

### Borrowers

Borrowers don't have any special access to CoW Protocol nor to the router.
They are only used as an adapter for specific flash-loan lender implementations.

Unauthorized external access should not impair their ability to act as an adapter, nor it should modify the expected behavior of the contract.


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

#### Benchmarking table based on chosen optimizations

| Gas profile | `main` | No optimizer | Turn on optimizer | Empty details | Default details | All true details | All false details | Optimizer false as well |
| - | - | - | - | - | - | - | - | - |
| Aave Average | 378,499 | 386,911 (+8,412) | 378,499 (0) | 340,747 (-37,752) | 349,159 (-29,340) | 340,747 (-37,752) | 350,017 (-28,482) | 350,017 (-28,482) |
| Aave Max | 913,766 | 922,178 (+8,412) | 913,766 (0) | 725,870 (-187,896) | 734,282 (-179,484) | 725,870 (-187,896) | 735,140 (-178,626) | 735,140 (-178,626) |
| Aave Median | 339,474 | 347,886 (+8,412) | 339,474 (0) | 314,394 (-25,080) | 322,806 (-16,668) | 314,394 (-25,080) | 323,664 (-15,810) | 323,664 (-15,810) |
| Aave Min | 307,872 | 316,284 (+8,412) | 307,872 (0) | 293,288 (-14,584) | 301,700 (-6,172) | 293,288 (-14,584) | 302,558 (-5,314) | 302,558 (-5,314) |
| Aave&Maker Average | 586,621 | 601,093 (+14,472) | 586,621 (0) | 616,841 (+30,220) | 631,313 (+44,692) | 616,841 (+30,220) | 632,738 (+46,117) | 632,738 (+46,117) |
| Aave&Maker Max | 1,203,370 | 1,217,842 (+14,472) | 1,203,370 (0) | 1,083,446 (-119,924) | 1,097,918 (-105,452) | 1,083,446 (-119,924) | 1,099,343 (-104,027) | 1,099,343 (-104,027) |
| Aave&Maker Median | 542,438 | 556,910 (+14,472) | 542,438 (0) | 585,330 (+42,892) | 599,802 (+57,364) | 585,330 (+42,892) | 601,227 (+58,789) | 601,227 (+58,789) |
| Aave&Maker Min | 506,769 | 521,241 (+14,472) | 506,769 (0) | 560,157 (+53,388) | 574,629 (+67,860) | 560,157 (+53,388) | 576,054 (+69,285) | 576,054 (+69,285) |
| Maker Average | 308,538 | 315,129 (+6,591) | 308,538 (0) | 317,642 (+9,104) | 325,542 (+17,004) | 317,642 (+9,104) | 326,351 (+17,813) | 326,351 (+17,813) |
| Maker Max | 597,381 | 605,281 (+7,900) | 597,381 (0) | 463,285 (-134,096) | 471,185 (-126,196) | 463,285 (-134,096) | 471,994 (-125,387) | 471,994 (-125,387) |
| Maker Median | 291,700 | 298,291 (+6,591) | 291,700 (0) | 309,533 (+17,833) | 317,433 (+25,733) | 309,533 (+17,833) | 318,242 (+26,542) | 318,242 (+26,542) |
| Maker Min | 278,174 | 284,764 (+6,590) | 278,174 (0) | 303,305 (+25,131) | 311,205 (+33,031) | 303,305 (+25,131) | 312,014 (+33,840) | 312,014 (+33,840) |
| No Loan Average | 87,736 | 89,890 (+2,154) | 87,736 (0) | 36,560 (-51,176) | 38,714 (-49,022) | 36,560 (-51,176) | 38,766 (-48,970) | 38,766 (-48,970) |
| No Loan Max | 267,455 | 269,609 (+2,154) | 267,455 (0) | 66,123 (-201,332) | 68,277 (-199,178) | 66,123 (-201,332) | 68,329 (-199,126) | 68,329 (-199,126) |
| No Loan Median | 73,564 | 75,718 (+2,154) | 73,564 (0) | 35,048 (-38,516) | 37,202 (-36,362) | 35,048 (-38,516) | 37,254 (-36,310) | 37,254 (-36,310) |
| No Loan Min | 61,932 | 64,086 (+2,154) | 61,932 (0) | 33,912 (-28,020) | 36,066 (-25,866) | 33,912 (-28,020) | 36,118 (-25,814) | 36,118 (-25,814) |

### Format

```shell
$ forge fmt
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```
