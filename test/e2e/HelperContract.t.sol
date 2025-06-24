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

    uint256 private constant MAINNET_FORK_BLOCK = 21883877;
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
    }

    function test_settleWithFlashLoanAndHelperContract() external {
        address _clone = factory.deployOrderHelper(
            user, address(borrower), address(Constants.AWETH), address(Constants.ADAI), 1 ether, 0
        );

        OrderHelper helper = OrderHelper(_clone);
        assertEq(helper.owner(), user);
        assertEq(helper.borrower(), address(borrower));
        assertEq(address(helper.oldCollateral()), address(Constants.AWETH));
        assertEq(address(helper.newCollateral()), address(Constants.ADAI));
        assertEq(helper.oldCollateralAmount(), 1 ether);
        assertEq(helper.flashloanFee(), 0);
    }
}
