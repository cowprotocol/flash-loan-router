// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {AaveBorrower, IAavePool} from "src/AaveBorrower.sol";
import {FlashLoanRouter, Loan} from "src/FlashLoanRouter.sol";

import {OrderHelper} from "src/helper/OrderHelper.sol";
import {OrderHelperFactory} from "src/helper/OrderHelperFactory.sol";
import {ICowSettlement} from "src/interface/IBorrower.sol";

import {Constants} from "./lib/Constants.sol";
import {CowProtocol} from "./lib/CowProtocol.sol";
import {CowProtocolInteraction} from "./lib/CowProtocolInteraction.sol";
import {ForkedRpc} from "./lib/ForkedRpc.sol";

contract E2eHelperContract is Test {
    using ForkedRpc for Vm;

    IAavePool internal constant POOL = IAavePool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    uint256 private constant MAINNET_FORK_BLOCK = 22828430;
    address private solver = makeAddr("E2eHelperContract: solver");
    address private user = makeAddr("E2eHelperContract: user");

    AaveBorrower private borrower;
    FlashLoanRouter private router;
    OrderHelperFactory private factory;

    function setUp() external {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);
        router = new FlashLoanRouter(Constants.SETTLEMENT_CONTRACT);
        CowProtocol.addSolver(vm, solver);
        CowProtocol.addSolver(vm, address(router));
        borrower = new AaveBorrower(router);

        ICowSettlement.Interaction[] memory onlyApprove = new ICowSettlement.Interaction[](1);
        onlyApprove[0] = CowProtocolInteraction.borrowerApprove(
            borrower, Constants.WETH, address(Constants.SETTLEMENT_CONTRACT), type(uint256).max
        );
        vm.prank(solver);
        CowProtocol.emptySettleWithInteractions(onlyApprove);
        factory = new OrderHelperFactory(address(new OrderHelper()));

        deal(address(Constants.WETH), user, 100 ether);
    }

    function test_orderHelperFactory() external {
        address _clone = factory.deployOrderHelper(
            user,
            address(borrower),
            address(Constants.WETH),
            10 ether,
            address(Constants.DAI),
            2500 ether,
            0xffffffff,
            0
        );

        OrderHelper helper = OrderHelper(_clone);
        assertEq(helper.owner(), user);
        assertEq(helper.borrower(), address(borrower));
        assertEq(address(helper.oldCollateral()), address(Constants.WETH));
        assertEq(helper.oldCollateralAmount(), 10 ether);
        assertEq(address(helper.newCollateral()), address(Constants.DAI));
        assertEq(helper.minSupplyAmount(), 2500 ether);
        assertEq(helper.validTo(), 0xffffffff);
        assertNotEq(helper.appData(), bytes32(0));
        assertEq(helper.flashloanFee(), 0);
    }

    function test_10WethCollatWith100UsdsSwappingCollateralForDaiWithFlashLoan() external {
        vm.startPrank(user);
        Constants.WETH.approve(address(POOL), type(uint256).max);
        POOL.supply(address(Constants.WETH), 10 ether, user, 0);
        POOL.borrow(address(Constants.USDS), 100 ether, 2, 0, user);
        vm.stopPrank();
        assertEq(Constants.AWETH.balanceOf(user), 10 ether);
        assertEq(Constants.USDS.balanceOf(user), 100 ether);

        // Order helper contract deployment can happen before or inside a hook, it doesn't matter.
        address _clone = factory.deployOrderHelper(
            user,
            address(borrower),
            address(Constants.WETH),
            10 ether,
            address(Constants.DAI),
            2_500 ether,
            0xffffffff,
            0
        );
        OrderHelper helper = OrderHelper(_clone);

        // User approvals
        vm.startPrank(user);
        // Approve the helper to pull the atokens on the swapCollateral hook logic
        Constants.AWETH.approve(address(helper), type(uint256).max);
        vm.stopPrank();

        // Flashloan definition
        Loan.Data[] memory _loans = new Loan.Data[](1);
        _loans[0] = Loan.Data({amount: 10 ether, borrower: borrower, lender: address(POOL), token: Constants.WETH});

        /*
            The order will be:
            Sell token: WETH - Buy token: DAI
            from: helper - to: helper
        */

        ICowSettlement.Interaction[] memory _interactions = new ICowSettlement.Interaction[](6);

        // 0) Move flashloan from the borrower to the helper
        _interactions[0] =
            CowProtocolInteraction.transferFrom(Constants.WETH, address(borrower), address(helper), 10 ether);

        // 1) Mock a swap by pulling weth from the helper
        // hack until order is created propertly we approve helper's weth to the settlement contract
        vm.prank(address(helper));
        Constants.WETH.approve(address(Constants.SETTLEMENT_CONTRACT), type(uint256).max);
        _interactions[1] = CowProtocolInteraction.transferFrom(
            Constants.WETH, address(helper), address(Constants.SETTLEMENT_CONTRACT), 10 ether
        );

        // 2) Mock the swap by giving DAI to the helper contract
        deal(address(Constants.DAI), address(Constants.SETTLEMENT_CONTRACT), 2_500 ether);
        _interactions[2] = CowProtocolInteraction.transfer(Constants.DAI, address(helper), 2_500 ether);

        // 3) Mock the "fee payback" by giving flashloan fee to the borrower
        uint256 _fee = 5000000000000000; // 10.005 is flashloan + fee. 0.005 is the fee in eth.
        deal(address(Constants.WETH), address(Constants.SETTLEMENT_CONTRACT), _fee);
        _interactions[3] = CowProtocolInteraction.transfer(Constants.WETH, address(borrower), _fee);

        // 4) Call helper.swapCollateral()
        _interactions[4] = CowProtocolInteraction.orderHelperSwapCollateral(address(helper));

        // 5) Borrower needs to approve the pool so the flashloan tokens + fees can be pulled out
        _interactions[5] =
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
