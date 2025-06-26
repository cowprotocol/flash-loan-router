// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {AaveBorrower, IAavePool} from "src/AaveBorrower.sol";

import {AaveHelper} from "src/AaveHelper.sol";
import {FlashLoanRouter, Loan} from "src/FlashLoanRouter.sol";

import {ICowSettlement} from "src/interface/IBorrower.sol";

import {Constants} from "./lib/Constants.sol";
import {CowProtocol} from "./lib/CowProtocol.sol";
import {CowProtocolInteraction} from "./lib/CowProtocolInteraction.sol";
import {ForkedRpc} from "./lib/ForkedRpc.sol";

contract E2eCollateralSwap is Test {
    using ForkedRpc for Vm;

    IAavePool internal constant POOL = IAavePool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    // This is the block immediately before a mainnet fee withdrawal:
    // <https://etherscan.io/tx/0x2ac75cbf67d74ae3ad736314acb9dba170922849d411cc7ccbe81e4e0cff157e>
    // It guarantees that there are some WETH available in the buffers to pay
    // for the flash loan.
    uint256 private constant MAINNET_FORK_BLOCK = 22785269;
    address private solver = makeAddr("E2eCollateralSwap: solver");
    address private user = makeAddr("E2eCollateralSwap: user");

    AaveBorrower private borrower;
    FlashLoanRouter private router;
    AaveHelper private helper;

    function setUp() external {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);

        // Setup flashloan router and borrower
        router = new FlashLoanRouter(Constants.SETTLEMENT_CONTRACT);
        borrower = new AaveBorrower(router);
        CowProtocol.addSolver(vm, solver);
        CowProtocol.addSolver(vm, address(router));

        // Allow settlement to do approvals on borrower
        ICowSettlement.Interaction[] memory onlyApprove = new ICowSettlement.Interaction[](1);
        onlyApprove[0] = CowProtocolInteraction.borrowerApprove(
            borrower, Constants.WETH, address(Constants.SETTLEMENT_CONTRACT), type(uint256).max
        );
        vm.prank(solver);
        CowProtocol.emptySettleWithInteractions(onlyApprove);

        // Give enough weth to our user
        deal(address(Constants.WETH), user, 100 ether);
        helper = new AaveHelper();
    }

    function test_10WethCollatWith100UsdsSwappingCollateralForDaiWithFlashLoan() external {
        // Supply 10 weth, borrow 100 usds
        vm.startPrank(user);
        Constants.WETH.approve(address(POOL), type(uint256).max);
        IAavePool(POOL).supply(address(Constants.WETH), 10 ether, user, 0);
        IAavePool(POOL).borrow(address(Constants.USDS), 100 ether, 2, 0, user);
        vm.stopPrank();
        assertEq(Constants.AWETH.balanceOf(user), 10 ether);
        assertEq(Constants.USDS.balanceOf(user), 100 ether);

        // User approvals
        vm.startPrank(user);
        // Approve the settlement to pull tokens for swap
        Constants.WETH.approve(address(Constants.SETTLEMENT_CONTRACT), type(uint256).max);
        // Approve the helper to pull the atokens
        Constants.AWETH.approve(address(helper), type(uint256).max);
        // Approve the borrower to pull the weth to repay loan
        Constants.WETH.approve(address(borrower), type(uint256).max);
        vm.stopPrank();

        // Flashloan definition
        Loan.Data[] memory _loans = new Loan.Data[](1);
        _loans[0] = Loan.Data({amount: 10 ether, borrower: borrower, lender: address(POOL), token: Constants.WETH});

        /*
            The order will be:
            Sell token: weth - Buy token: Dai
            from: user - to: helper
        */

        // Setup the interactions for order:
        // 0) Call AaveBorrower takeOut(user, weth, 10 ether)
        // 1) Mock a swap by pulling weth from the user
        // 2) Mock the swap by giving DAI to the helper contract
        // 3) Mock the "fee payback" by giving flashloan fee to the borrower
        // 4) Call helper.swap(weth, dai, user, 10 ether)
        // 5) Call AaveBorrower payBack(user, weth)
        // 6) Borrower needs to approve the pool so the flashloan tokens + fees can be pulled out
        ICowSettlement.Interaction[] memory _interactions = new ICowSettlement.Interaction[](7);

        // 0) Call AaveBorrower takeOut(user, weth, 10 ether)
        _interactions[0] = CowProtocolInteraction.takeOut(address(borrower), user, Constants.WETH, 10 ether);

        // 1) Mock a swap by pulling weth from the user
        _interactions[1] = CowProtocolInteraction.transferFrom(
            Constants.WETH, address(user), address(Constants.SETTLEMENT_CONTRACT), 10 ether
        );

        // 2) Mock the swap by giving DAI to the helper contract
        deal(address(Constants.DAI), address(Constants.SETTLEMENT_CONTRACT), 2_500 ether);
        _interactions[2] = CowProtocolInteraction.transfer(Constants.DAI, address(helper), 2_500 ether);

        // 3) Mock the "fee payback" by giving flashloan fee to the borrower
        uint256 _fee = 5000000000000000; // 10.005 is flashloan + fee. 0.005 is the fee in eth.
        deal(address(Constants.WETH), address(Constants.SETTLEMENT_CONTRACT), _fee);
        _interactions[3] = CowProtocolInteraction.transfer(Constants.WETH, address(borrower), _fee);

        // 4) Call helper.swap(weth, dai, user, 10 ether)
        _interactions[4] = CowProtocolInteraction.helperSwap(
            address(helper), address(Constants.WETH), address(Constants.DAI), user, 10 ether
        );

        // 5) Call AaveBorrower payBack(user, weth)
        _interactions[5] = CowProtocolInteraction.payBack(address(borrower), user, Constants.WETH);

        // 6) Borrower needs to approve the pool so the flashloan tokens + fees can be pulled out
        _interactions[6] =
            CowProtocolInteraction.borrowerApprove(borrower, Constants.WETH, address(POOL), type(uint256).max);

        bytes memory _settleCallData = CowProtocol.encodeEmptySettleWithInteractions(_interactions);
        vm.prank(solver);
        router.flashLoanAndSettle(_loans, _settleCallData);

        // User final state
        assertEq(Constants.AWETH.balanceOf(user), 0);
        assertEq(Constants.WETH.balanceOf(user), 100 ether - 10 ether);
        assertEq(Constants.USDS.balanceOf(user), 100 ether);
        assertEq(Constants.ADAI.balanceOf(user), 2_500 ether);

        // Helper final state
        assertEq(Constants.AWETH.balanceOf(address(helper)), 0);
        assertEq(Constants.WETH.balanceOf(address(helper)), 0);
        assertEq(Constants.ADAI.balanceOf(address(helper)), 0);

        // borrower final state
        assertEq(Constants.WETH.balanceOf(address(borrower)), 0);
    }
}
