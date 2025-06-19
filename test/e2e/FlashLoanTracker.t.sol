// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {Constants} from "./lib/Constants.sol";
import {CowProtocol} from "./lib/CowProtocol.sol";
import {CowProtocolInteraction} from "./lib/CowProtocolInteraction.sol";
import {ForkedRpc} from "./lib/ForkedRpc.sol";
import {AaveBorrower} from "src/AaveBorrower.sol";
import {FlashLoanRouter, Loan} from "src/FlashLoanRouter.sol";
import {FlashLoanTracker, IFlashLoanTracker} from "src/FlashLoanTracker.sol";
import {ICowSettlement} from "src/interface/IBorrower.sol";
import {IBorrower} from "src/interface/IBorrower.sol";
import {IAavePool} from "src/vendored/IAavePool.sol";

library AaveSetup {
    // The pool address is retrieved from the Aave aToken address corresponding
    // to the desired collateral through the POOL() function. The token address
    // can retrieved from the web interface:
    // https://app.aave.com/reserve-overview/?underlyingAsset=0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2&marketName=proto_mainnet_v3
    IAavePool internal constant WETH_POOL = IAavePool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    // TODO: why they are the same?
    IAavePool internal constant USDS_POOL = IAavePool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    function prepareBorrow(Vm vm, address user, address token, uint256 amount) internal {
        vm.startPrank(user);
        IAavePool(USDS_POOL).borrow(token, amount, 2, 0, user);
        vm.stopPrank();
    }

    function prepareCollateral(Vm vm, address user, address token, uint256 amount) internal {
        vm.startPrank(user);
        Constants.WETH.approve(address(WETH_POOL), type(uint256).max);
        IAavePool(WETH_POOL).supply(token, amount, user, 0);
        vm.stopPrank();
    }

    function prepareBorrower(Vm vm, FlashLoanRouter router, address solver) internal returns (AaveBorrower borrower) {
        borrower = new AaveBorrower(router);

        // Call `approve` from the settlement contract so that WETH can be spent
        // on a settlement interaction on behalf of the borrower. With an
        // unlimited approval, this step only needs to be performed once per
        // loaned token.
        ICowSettlement.Interaction[] memory onlyApprove = new ICowSettlement.Interaction[](1);
        onlyApprove[0] = CowProtocolInteraction.borrowerApprove(
            borrower, Constants.USDS, address(Constants.SETTLEMENT_CONTRACT), type(uint256).max
        );
        vm.prank(solver);
        CowProtocol.emptySettleWithInteractions(onlyApprove);
    }
}

contract E2eFlashLoanTracker is Test {
    using ForkedRpc for Vm;

    uint256 private constant MAINNET_FORK_BLOCK = 22735409;
    address private solver = makeAddr("E2eFlashLoanTracker: solver");
    address private user = makeAddr("E2eFlashLoanTracker: user");

    AaveBorrower private borrower;
    FlashLoanRouter private router;
    FlashLoanTracker private tracker;

    function setUp() external {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);
        tracker = new FlashLoanTracker(address(Constants.SETTLEMENT_CONTRACT));
        router = new FlashLoanRouter(Constants.SETTLEMENT_CONTRACT);

        CowProtocol.addSolver(vm, solver);
        CowProtocol.addSolver(vm, address(router));
        borrower = AaveSetup.prepareBorrower(vm, router, solver);

        deal(address(Constants.WETH), user, 100 ether);
    }

    function test_10WethCollat100UsdsBorrowDumpingWethForCowWithFlashLoan() external {
        require(Constants.WETH.balanceOf(user) == 100 ether);

        AaveSetup.prepareCollateral(vm, user, address(Constants.WETH), 10 ether);
        require(Constants.AWETH.balanceOf(user) == 10 ether);

        // We are going to loan 100 USDS
        uint256 _loanedAmount = 100 ether;
        AaveSetup.prepareBorrow(vm, user, address(Constants.USDS), _loanedAmount);
        require(Constants.USDS.balanceOf(user) == 100 ether);

        // Collateral should be locked
        vm.startPrank(user);
        vm.expectRevert();
        Constants.AWETH.transfer(address(Constants.SETTLEMENT_CONTRACT), 10 ether);
        vm.stopPrank();

        // Setup the interactions
        // 0) Send USDS from borrower to tracker
        // 1) Approve FlashLoanTracker's USDS to AAVE's pool
        // 2) Tracker should repay user loan
        // 3) Mock a swap by pulling user funds
        // 4) Mock the swap by giving the user CoW
        // 5) Mock the payment of usds to FlashLoanTracker
        // 6) Approve FlashLoanTracker's USDS to borrower
        // 7) Pull assets from FlashLoanTracker to the borrower
        // 8) Borrower needs to approve the pool so the flashloan tokens + fees can be pulled out
        ICowSettlement.Interaction[] memory _interactions = new ICowSettlement.Interaction[](9);

        // 0) Send USDS from borrower to tracker
        _interactions[0] =
            CowProtocolInteraction.transferFrom(Constants.USDS, address(borrower), address(tracker), _loanedAmount);

        // 1) Approve FlashLoanTracker's USDS to AAVE's pool
        // HACK, I am being lazy and using the borrower interface since they have the same signature
        _interactions[1] = CowProtocolInteraction.borrowerApprove(
            IBorrower(address(tracker)), Constants.USDS, address(AaveSetup.USDS_POOL), type(uint256).max
        );

        // 2) Tracker should repay user loan
        _interactions[2] = CowProtocolInteraction.repayLoan(
            IFlashLoanTracker(address(tracker)),
            address(AaveSetup.USDS_POOL),
            address(Constants.USDS),
            _loanedAmount,
            user
        );

        // 3) Mock a swap by pulling user funds
        // HACK: will make the user approve settlement to mock the vault logic
        vm.prank(user);
        Constants.AWETH.approve(address(Constants.SETTLEMENT_CONTRACT), type(uint256).max);
        _interactions[3] = CowProtocolInteraction.transferFrom(
            Constants.AWETH, address(user), address(Constants.SETTLEMENT_CONTRACT), 10 ether
        );

        // 4) Mock the swap by giving the user CoW
        // HACK: The settlement will have enough CoW!
        deal(address(Constants.COW), address(Constants.SETTLEMENT_CONTRACT), 1 ether);
        _interactions[4] = CowProtocolInteraction.transfer(Constants.COW, address(user), 1 ether);

        // 5) Mock the payment of usds to FlashLoanTracker
        // HACK: The settlement will have enough USDS!
        uint256 _relativeFlashFee = AaveSetup.USDS_POOL.FLASHLOAN_PREMIUM_TOTAL();
        uint256 _absoluteFlashFee = _loanedAmount * _relativeFlashFee / 1000;
        uint256 _borrowedPlusFee = _loanedAmount + _absoluteFlashFee;

        deal(address(Constants.USDS), address(Constants.SETTLEMENT_CONTRACT), _borrowedPlusFee);

        _interactions[5] = CowProtocolInteraction.transfer(Constants.USDS, address(tracker), _borrowedPlusFee);

        // 6) Approve FlashLoanTracker's USDS to borrower
        // HACK, I am being lazy and using the borrower interface since they have the same signature
        _interactions[6] = CowProtocolInteraction.borrowerApprove(
            IBorrower(address(tracker)), Constants.USDS, address(Constants.SETTLEMENT_CONTRACT), type(uint256).max
        );

        // 7) Pull assets from FlashLoanTracker to the borrower
        _interactions[7] =
            CowProtocolInteraction.transferFrom(Constants.USDS, address(tracker), address(borrower), _borrowedPlusFee);

        // 8) Borrower needs to approve the pool so the flashloan tokens + fees can be pulled out
        _interactions[8] = CowProtocolInteraction.borrowerApprove(
            borrower, Constants.USDS, address(AaveSetup.USDS_POOL), type(uint256).max
        );

        bytes memory _settleCallData = CowProtocol.encodeEmptySettleWithInteractions(_interactions);

        Loan.Data[] memory _loans = new Loan.Data[](1);
        _loans[0] = Loan.Data({
            amount: _loanedAmount,
            borrower: borrower,
            lender: address(AaveSetup.USDS_POOL),
            token: Constants.USDS
        });

        vm.prank(solver);
        router.flashLoanAndSettle(_loans, _settleCallData);

        require(Constants.COW.balanceOf(user) == 1 ether);
        require(Constants.COW.balanceOf(address(Constants.SETTLEMENT_CONTRACT)) == 0);

        require(Constants.AWETH.balanceOf(user) == 0);
        require(Constants.AWETH.balanceOf(address(Constants.SETTLEMENT_CONTRACT)) >= 10 ether);
    }
}
