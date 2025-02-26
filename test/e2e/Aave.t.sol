// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {AaveFlashLoanSolverWrapper, IAavePool, IERC20} from "src/AaveFlashLoanSolverWrapper.sol";
import {FlashLoanRouter, LoanRequest} from "src/FlashLoanRouter.sol";
import {ICowSettlement, IFlashLoanSolverWrapper} from "src/interface/IFlashLoanSolverWrapper.sol";

import {Constants} from "./lib/Constants.sol";
import {CowProtocol} from "./lib/CowProtocol.sol";
import {CowProtocolInteraction} from "./lib/CowProtocolInteraction.sol";
import {ForkedRpc} from "./lib/ForkedRpc.sol";
import {TokenBalanceAccumulator} from "./lib/TokenBalanceAccumulator.sol";

/// @dev Documentation for the ERC-3156-compatible flash loans by Maker can be
/// found at:
/// <https://docs.makerdao.com/smart-contract-modules/flash-mint-module>
contract E2eAave is Test {
    using ForkedRpc for Vm;

    // This is the block immediately before a mainnet fee withdrawal:
    // <https://etherscan.io/tx/0x2ac75cbf67d74ae3ad736314acb9dba170922849d411cc7ccbe81e4e0cff157e>
    // It guarantees that there are some WETH available in the buffers to pay
    // for the flash loan.
    uint256 private constant MAINNET_FORK_BLOCK = 21883877;
    // The pool address is retrieved from the Aave aToken address corresponding
    // to the desired collateral through the POOL() function. The token address
    // can retrieved from the web interface:
    // https://app.aave.com/reserve-overview/?underlyingAsset=0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2&marketName=proto_mainnet_v3
    IAavePool private constant AAVE_WETH_POOL = IAavePool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    address private solver = makeAddr("E2eAaveV2: solver");

    AaveFlashLoanSolverWrapper private solverWrapper;
    TokenBalanceAccumulator private tokenBalanceAccumulator;
    FlashLoanRouter private router;

    function setUp() external {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);
        CowProtocol.addSolver(vm, solver);
        tokenBalanceAccumulator = new TokenBalanceAccumulator();
        prepareSolverWrapper();
    }

    function prepareSolverWrapper() private {
        router = new FlashLoanRouter(Constants.SETTLEMENT_CONTRACT);
        solverWrapper = new AaveFlashLoanSolverWrapper(router);

        // The solver wrapper must be a solver because it directly calls
        // `settle`.
        CowProtocol.addSolver(vm, address(router));

        // Call `approve` from the settlement contract so that WETH can be spent
        // on a settlement interaction on behalf of the solver wrapper. With an
        // unlimited approval, this step only needs to be performed once per
        // loaned token.
        ICowSettlement.Interaction[] memory onlyApprove = new ICowSettlement.Interaction[](1);
        onlyApprove[0] = CowProtocolInteraction.wrapperApprove(
            solverWrapper, Constants.WETH, address(Constants.SETTLEMENT_CONTRACT), type(uint256).max
        );
        vm.prank(solver);
        CowProtocol.emptySettleWithInteractions(onlyApprove);
    }

    function test_settleWithFlashLoan() external {
        uint256 loanedAmount = 500 ether; // 500 WETH

        // Note: one unit of flash fee represents 0.1% of the borrowed amount.
        // See:
        // <https://github.com/aave-dao/aave-v3-origin/blob/v3.1.0/src/core/contracts/protocol/libraries/math/PercentageMath.sol>
        uint256 relativeFlashFee = AAVE_WETH_POOL.FLASHLOAN_PREMIUM_TOTAL();
        assertGt(relativeFlashFee, 0);
        uint256 absoluteFlashFee = loanedAmount * relativeFlashFee / 1000;

        uint256 settlementInitialWethBalance = Constants.WETH.balanceOf(address(Constants.SETTLEMENT_CONTRACT));
        // We cover the balance of the flash fee with the tokens that are
        // currently present in the settlement contract.
        assertGt(settlementInitialWethBalance, absoluteFlashFee);

        TokenBalanceAccumulator.Balance[] memory expectedBalances = new TokenBalanceAccumulator.Balance[](3);

        // Start preparing the settlement interactions.
        ICowSettlement.Interaction[] memory interactionsWithFlashLoan = new ICowSettlement.Interaction[](6);
        // First, we confirm that, at the point in time of the settlement, the
        // flash loan proceeds are indeed stored in the wrapper solver.
        interactionsWithFlashLoan[0] = CowProtocolInteraction.pushBalanceToAccumulator(
            tokenBalanceAccumulator, Constants.WETH, address(solverWrapper)
        );
        expectedBalances[0] = TokenBalanceAccumulator.Balance(Constants.WETH, address(solverWrapper), loanedAmount);
        // Second, we double check that the settlement balance hasn't changed.
        interactionsWithFlashLoan[1] = CowProtocolInteraction.pushBalanceToAccumulator(
            tokenBalanceAccumulator, Constants.WETH, address(Constants.SETTLEMENT_CONTRACT)
        );
        expectedBalances[1] = TokenBalanceAccumulator.Balance(
            Constants.WETH, address(Constants.SETTLEMENT_CONTRACT), settlementInitialWethBalance
        );
        // Third, we make sure we can transfer these tokens. We do that by
        // trying a transfer into the settlement contract. The expectation is
        // that the wrapper has already approved the settlement contract to
        // transfer its tokens out of it. In practice, the target of the
        // transfer is expected to be the user rather than the settlement
        // contract for gas efficiency.
        interactionsWithFlashLoan[2] = CowProtocolInteraction.transferFrom(
            Constants.WETH, address(solverWrapper), address(Constants.SETTLEMENT_CONTRACT), loanedAmount
        );
        // Fourth, we check that the balance has indeed changed.
        interactionsWithFlashLoan[3] = CowProtocolInteraction.pushBalanceToAccumulator(
            tokenBalanceAccumulator, Constants.WETH, address(Constants.SETTLEMENT_CONTRACT)
        );
        expectedBalances[2] = TokenBalanceAccumulator.Balance(
            Constants.WETH, address(Constants.SETTLEMENT_CONTRACT), settlementInitialWethBalance + loanedAmount
        );
        // Fifth, prepare the flash-loan repayment. Aave makes you repay the
        // loan by calling `transferFrom` under the assumption that the flash
        // loan borrower holds the funds plus the expected fee and has approved
        // its contract for withdrawing this amount.
        interactionsWithFlashLoan[4] = CowProtocolInteraction.wrapperApprove(
            solverWrapper, Constants.WETH, address(AAVE_WETH_POOL), loanedAmount + absoluteFlashFee
        );
        // Sixth and finally, send the funds to the solver wrapper for repayment
        // of the loan.
        interactionsWithFlashLoan[5] =
            CowProtocolInteraction.transfer(Constants.WETH, address(solverWrapper), loanedAmount + absoluteFlashFee);

        bytes memory settleCallData = CowProtocol.encodeEmptySettleWithInteractions(interactionsWithFlashLoan);

        LoanRequest.Data[] memory loans = new LoanRequest.Data[](1);
        loans[0] = LoanRequest.Data({
            amount: loanedAmount,
            borrower: solverWrapper,
            lender: address(AAVE_WETH_POOL),
            token: Constants.WETH
        });

        vm.prank(solver);
        router.flashLoanAndSettle(loans, settleCallData);

        tokenBalanceAccumulator.assertAccumulatorEq(vm, expectedBalances);
        assertEq(
            Constants.WETH.balanceOf(address(Constants.SETTLEMENT_CONTRACT)),
            settlementInitialWethBalance - absoluteFlashFee
        );
    }
}
