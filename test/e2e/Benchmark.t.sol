// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {AaveFlashLoanSolverWrapper, IAavePool} from "src/AaveFlashLoanSolverWrapper.sol";
import {ERC3156FlashLoanSolverWrapper, IERC3156FlashLender} from "src/ERC3156FlashLoanSolverWrapper.sol";
import {ICowSettlement, IERC20, IFlashLoanSolverWrapper} from "src/interface/IFlashLoanSolverWrapper.sol";

import {Constants} from "./lib/Constants.sol";
import {CowProtocol} from "./lib/CowProtocol.sol";
import {CowProtocolInteraction} from "./lib/CowProtocolInteraction.sol";
import {ForkedRpc} from "./lib/ForkedRpc.sol";
import {TokenBalanceAccumulator} from "./lib/TokenBalanceAccumulator.sol";

uint256 constant MAINNET_FORK_BLOCK = 21765553;

// These values were computed based on the actual mainnet on-chain settlement
// transaction size on 2025-02-21.
uint256 constant SETTLEMENT_24H_MIN_SIZE = 1802;
uint256 constant SETTLEMENT_24H_MAX_SIZE = 45146;
uint256 constant SETTLEMENT_24H_AVERAGE_SIZE = 7598;
uint256 constant SETTLEMENT_24H_MEDIAN_SIZE = 4442;

abstract contract BenchmarkFixture is Test {
    using ForkedRpc for Vm;

    address private solver = makeAddr("BenchmarkFixture: solver");

    IFlashLoanSolverWrapper private immutable solverWrapper;
    IERC20 private immutable token;
    address private immutable lender;
    string private benchGroup;

    constructor(IERC20 _token, address _lender, string memory _benchGroup) {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);
        solverWrapper = deploySolverWrapper();
        token = _token;
        lender = _lender;
        benchGroup = _benchGroup;
    }

    function deploySolverWrapper() internal virtual returns (IFlashLoanSolverWrapper);

    function setUp() external {
        CowProtocol.addSolver(vm, solver);
        CowProtocol.addSolver(vm, address(solverWrapper));
        // The following is a transaction that is expected to happen only once
        // per token and per lender, which is why we exclude it from the
        // benchmark.
        ICowSettlement.Interaction[] memory onlyApprove = new ICowSettlement.Interaction[](1);
        onlyApprove[0] = CowProtocolInteraction.wrapperApprove(
            solverWrapper, token, address(Constants.SETTLEMENT_CONTRACT), type(uint256).max
        );
        vm.prank(solver);
        CowProtocol.emptySettleWithInteractions(onlyApprove);
    }

    /// @param extraDataSize The size of the padding data that will be included
    /// in an interaction to pad the settlement. This can be approximately be
    /// the calldata size of a `settle` interaction without flash loans.
    /// @param name An identifier that will be used to give a name to the
    /// snapshot for this run.
    function flashLoanSettleWithExtraData(uint256 extraDataSize, string memory name) private {
        uint256 loanedAmount = 1; // Just one wei of the token
        // We assume that the fees aren't larger than the traded amount.
        uint256 fees = loanedAmount;

        // We'll pay the fees from the buffers.
        uint256 settlementBalance = token.balanceOf(address(Constants.SETTLEMENT_CONTRACT));
        assertGt(settlementBalance, fees);

        // Start preparing the settlement interactions.
        ICowSettlement.Interaction[] memory interactionsWithFlashLoan = new ICowSettlement.Interaction[](4);
        // Transfer tokens out from the settlement wrapper to the settlement
        // contract. In practice, the funds will be sent to a different address,
        // but for the purpose of the test this should have an equivalent cost
        // of modifying a fresh storage slot.
        interactionsWithFlashLoan[0] = CowProtocolInteraction.transferFrom(
            token, address(solverWrapper), address(Constants.SETTLEMENT_CONTRACT), loanedAmount
        );
        // Approve repayment. Under some assumptions, this could be done once
        // per call.
        interactionsWithFlashLoan[1] =
            CowProtocolInteraction.wrapperApprove(solverWrapper, token, lender, loanedAmount + fees);
        // Prepare flash-loan repayment.
        interactionsWithFlashLoan[2] =
            CowProtocolInteraction.transfer(token, address(solverWrapper), loanedAmount + fees);
        // Padding transaction. It does nothing but increase the cost of
        // executing flash-loan in a way that is compatible with the execution
        // of other interactions with on-chain liquidity to settle an order.
        // In practice, the gas cost of these interactions will be different,
        // but that's not something that should change between the case with the
        // flash loan or without it.
        // As a first approximation, using the actual calldata size of a normal
        // call to `settle` seems reasonable, though it slightly overestimates
        // the actual cost (some of the calldata used in a settlement is due to
        // the ABI encoding of the transaction in a format compatible with a
        // `settle()` call, which has to be done regardless). However, we
        // consider the impact of this extra data overall small.
        interactionsWithFlashLoan[3] =
            ICowSettlement.Interaction({target: address(0), value: 0, callData: new bytes(extraDataSize)});

        bytes memory settleCallData = CowProtocol.encodeEmptySettleWithInteractions(interactionsWithFlashLoan);
        IFlashLoanSolverWrapper.LoanRequest memory loanRequest =
            IFlashLoanSolverWrapper.LoanRequest(token, loanedAmount);

        vm.prank(solver);
        vm.startSnapshotGas(string.concat("E2eBenchmark", benchGroup), name);
        solverWrapper.flashLoanAndSettle(lender, loanRequest, settleCallData);
        vm.stopSnapshotGas();
    }

    function test_settleMin() external {
        flashLoanSettleWithExtraData(SETTLEMENT_24H_MIN_SIZE, "Min");
    }

    function test_settleMax() external {
        flashLoanSettleWithExtraData(SETTLEMENT_24H_MAX_SIZE, "Max");
    }

    function test_settleAverage() external {
        flashLoanSettleWithExtraData(SETTLEMENT_24H_AVERAGE_SIZE, "Average");
    }

    function test_settleMedian() external {
        flashLoanSettleWithExtraData(SETTLEMENT_24H_MEDIAN_SIZE, "Median");
    }
}

contract E2eBenchmarkNoFlashLoan is Test {
    using ForkedRpc for Vm;

    address private solver = makeAddr("E2eBenchNoFlashLoan: solver");

    function setUp() external {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);
        CowProtocol.addSolver(vm, solver);
    }

    function settleWithExtraData(uint256 extraDataSize, string memory name) private {
        ICowSettlement.Interaction[] memory intraInteractions = new ICowSettlement.Interaction[](1);
        intraInteractions[0] =
            ICowSettlement.Interaction({target: address(0), value: 0, callData: new bytes(extraDataSize)});

        (
            address[] memory noTokens,
            uint256[] memory noPrices,
            ICowSettlement.Trade[] memory noTrades,
            ICowSettlement.Interaction[][3] memory interactions
        ) = CowProtocol.emptySettleInputWithInteractions(intraInteractions);

        vm.prank(solver);
        vm.startSnapshotGas("E2eBenchmarkNoFlashLoans", name);
        Constants.SETTLEMENT_CONTRACT.settle(noTokens, noPrices, noTrades, interactions);
        vm.stopSnapshotGas();
    }

    function test_settleMin() external {
        settleWithExtraData(SETTLEMENT_24H_MIN_SIZE, "Min");
    }

    function test_settleMax() external {
        settleWithExtraData(SETTLEMENT_24H_MAX_SIZE, "Max");
    }

    function test_settleAverage() external {
        settleWithExtraData(SETTLEMENT_24H_AVERAGE_SIZE, "Average");
    }

    function test_settleMedian() external {
        settleWithExtraData(SETTLEMENT_24H_MEDIAN_SIZE, "Median");
    }
}

contract E2eBenchmarkMaker is BenchmarkFixture {
    IERC3156FlashLender private constant MAKER_FLASH_LOAN_CONTRACT =
        IERC3156FlashLender(0x60744434d6339a6B27d73d9Eda62b6F66a0a04FA);

    constructor() BenchmarkFixture(Constants.DAI, address(MAKER_FLASH_LOAN_CONTRACT), "Maker") {}

    function deploySolverWrapper() internal override returns (IFlashLoanSolverWrapper solverWrapper) {
        solverWrapper = new ERC3156FlashLoanSolverWrapper(Constants.SETTLEMENT_CONTRACT);
    }
}

contract E2eBenchmarkAave is BenchmarkFixture {
    IAavePool private constant AAVE_WETH_POOL = IAavePool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    constructor() BenchmarkFixture(Constants.WETH, address(AAVE_WETH_POOL), "Aave") {}

    function deploySolverWrapper() internal override returns (IFlashLoanSolverWrapper solverWrapper) {
        solverWrapper = new AaveFlashLoanSolverWrapper(Constants.SETTLEMENT_CONTRACT);
    }
}
