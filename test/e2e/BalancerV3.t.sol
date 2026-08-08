// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {BalancerV3Borrower} from "src/BalancerV3Borrower.sol";
import {FlashLoanRouter, Loan} from "src/FlashLoanRouter.sol";
import {ICowSettlement} from "src/interface/IBorrower.sol";
import {IBalancerVault} from "src/vendored/IBalancerV3Vault.sol";

import {Constants} from "./lib/Constants.sol";
import {CowProtocol} from "./lib/CowProtocol.sol";
import {CowProtocolInteraction} from "./lib/CowProtocolInteraction.sol";
import {ForkedRpc} from "./lib/ForkedRpc.sol";
import {TokenBalanceAccumulator} from "./lib/TokenBalanceAccumulator.sol";

library BalancerV3Setup {
    IBalancerVault internal constant VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    function prepareBorrower(Vm vm, FlashLoanRouter router, address solver)
        internal
        returns (BalancerV3Borrower borrower)
    {
        borrower = new BalancerV3Borrower(router);

        ICowSettlement.Interaction[] memory onlyApprove = new ICowSettlement.Interaction[](1);
        onlyApprove[0] = CowProtocolInteraction.borrowerApprove(
            borrower, Constants.WETH, address(Constants.SETTLEMENT_CONTRACT), type(uint256).max
        );
        vm.prank(solver);
        CowProtocol.emptySettleWithInteractions(onlyApprove);
    }
}

contract E2eBalancerV3 is Test {
    using ForkedRpc for Vm;

    uint256 private constant MAINNET_FORK_BLOCK = 21883877;
    address private solver = makeAddr("E2eBalancerV3: solver");

    BalancerV3Borrower private borrower;
    TokenBalanceAccumulator private tokenBalanceAccumulator;
    FlashLoanRouter private router;

    function setUp() external {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);
        tokenBalanceAccumulator = new TokenBalanceAccumulator();
        router = new FlashLoanRouter(Constants.SETTLEMENT_CONTRACT);
        CowProtocol.addSolver(vm, solver);
        CowProtocol.addSolver(vm, address(router));
        borrower = BalancerV3Setup.prepareBorrower(vm, router, solver);
    }

    function test_settleWithFlashLoan() external {
        uint256 desiredLoanAmount = 500 ether;

        uint256 flashLoanFeePercentage;
        try BalancerV3Setup.VAULT.getFlashLoanFeePercentage() returns (uint256 percentage) {
            flashLoanFeePercentage = percentage;
        } catch {
            flashLoanFeePercentage = 0;
        }

        uint256 settlementInitialBalance = Constants.WETH.balanceOf(address(Constants.SETTLEMENT_CONTRACT));
        uint256 loanedAmount = desiredLoanAmount;
        uint256 absoluteFlashFee;

        if (flashLoanFeePercentage > 0) {
            uint256 maxLoanFromBuffers = settlementInitialBalance * 1e18 / flashLoanFeePercentage;
            if (loanedAmount > maxLoanFromBuffers) {
                loanedAmount = maxLoanFromBuffers;
            }
            require(loanedAmount > 0, "E2eBalancerV3: insufficient WETH buffers");
            absoluteFlashFee = loanedAmount * flashLoanFeePercentage / 1e18;
        }

        TokenBalanceAccumulator.Balance[] memory expectedBalances = new TokenBalanceAccumulator.Balance[](4);
        ICowSettlement.Interaction[] memory interactionsWithFlashLoan = new ICowSettlement.Interaction[](6);

        interactionsWithFlashLoan[0] =
            CowProtocolInteraction.pushBalanceToAccumulator(tokenBalanceAccumulator, Constants.WETH, address(borrower));
        expectedBalances[0] = TokenBalanceAccumulator.Balance(Constants.WETH, address(borrower), loanedAmount);

        interactionsWithFlashLoan[1] = CowProtocolInteraction.pushBalanceToAccumulator(
            tokenBalanceAccumulator, Constants.WETH, address(Constants.SETTLEMENT_CONTRACT)
        );
        expectedBalances[1] = TokenBalanceAccumulator.Balance(
            Constants.WETH, address(Constants.SETTLEMENT_CONTRACT), settlementInitialBalance
        );

        interactionsWithFlashLoan[2] = CowProtocolInteraction.transferFrom(
            Constants.WETH, address(borrower), address(Constants.SETTLEMENT_CONTRACT), loanedAmount
        );

        interactionsWithFlashLoan[3] = CowProtocolInteraction.pushBalanceToAccumulator(
            tokenBalanceAccumulator, Constants.WETH, address(Constants.SETTLEMENT_CONTRACT)
        );
        expectedBalances[2] = TokenBalanceAccumulator.Balance(
            Constants.WETH, address(Constants.SETTLEMENT_CONTRACT), settlementInitialBalance + loanedAmount
        );

        interactionsWithFlashLoan[4] = CowProtocolInteraction.transfer(
            Constants.WETH, address(borrower), loanedAmount + absoluteFlashFee
        );

        interactionsWithFlashLoan[5] = CowProtocolInteraction.pushBalanceToAccumulator(
            tokenBalanceAccumulator, Constants.WETH, address(Constants.SETTLEMENT_CONTRACT)
        );
        expectedBalances[3] = TokenBalanceAccumulator.Balance(
            Constants.WETH, address(Constants.SETTLEMENT_CONTRACT), settlementInitialBalance - absoluteFlashFee
        );

        bytes memory settleCallData = CowProtocol.encodeEmptySettleWithInteractions(interactionsWithFlashLoan);

        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({amount: loanedAmount, borrower: borrower, lender: address(BalancerV3Setup.VAULT), token: Constants.WETH});

        vm.prank(solver);
        router.flashLoanAndSettle(loans, settleCallData);

        tokenBalanceAccumulator.assertAccumulatorEq(vm, expectedBalances);
        assertEq(
            Constants.WETH.balanceOf(address(Constants.SETTLEMENT_CONTRACT)),
            settlementInitialBalance - absoluteFlashFee
        );
        assertEq(Constants.WETH.balanceOf(address(borrower)), 0);
    }
}
