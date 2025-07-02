// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {AaveBorrower, IAavePool} from "src/AaveBorrower.sol";
import {FlashLoanRouter, Loan} from "src/FlashLoanRouter.sol";

import {GPv2Order, IERC20} from "src/helper/GPv2Order.sol";
import {ISettlement} from "src/helper/ISettlement.sol";
import {OrderHelper} from "src/helper/OrderHelper.sol";
import {OrderHelperFactory} from "src/helper/OrderHelperFactory.sol";
import {ICowSettlement} from "src/interface/IBorrower.sol";

import {Constants} from "./lib/Constants.sol";
import {CowProtocol} from "./lib/CowProtocol.sol";
import {CowProtocolInteraction} from "./lib/CowProtocolInteraction.sol";
import {ForkedRpc} from "./lib/ForkedRpc.sol";

interface IPreSignTarget {
    function domainSeparator() external view returns (bytes32);
    function setPreSignature(bytes calldata orderUid, bool signed) external;
}

contract E2eHelperContract is Test {
    using ForkedRpc for Vm;
    using GPv2Order for GPv2Order.Data;

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
        Constants.WETH.approve(
            address(ISettlement(address(Constants.SETTLEMENT_CONTRACT)).vaultRelayer()), type(uint256).max
        );
        vm.stopPrank();

        // Ensure there are 2.5k DAI in the settlement contract so the trade works
        deal(address(Constants.DAI), address(Constants.SETTLEMENT_CONTRACT), 2_500 ether);

        // Flashloan definition
        Loan.Data[] memory _loans = new Loan.Data[](1);
        _loans[0] = Loan.Data({amount: 10 ether, borrower: borrower, lender: address(POOL), token: Constants.WETH});

        /*
            The order will be:
            Sell token: WETH - Buy token: DAI
            from: user - to: helper
        */
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: Constants.WETH,
            buyToken: Constants.DAI,
            receiver: address(helper),
            sellAmount: 10 ether,
            buyAmount: 2_500 ether,
            validTo: type(uint32).max,
            appData: bytes32(0),
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
        {
            bytes memory orderUid = computeOrderUid(order, user);
            vm.prank(user);
            IPreSignTarget(address(Constants.SETTLEMENT_CONTRACT)).setPreSignature(orderUid, true);
        }

        ICowSettlement.Interaction[] memory preInteractions = new ICowSettlement.Interaction[](1);
        ICowSettlement.Interaction[] memory postInteractions = new ICowSettlement.Interaction[](3);

        // 0) Move flashloan from the borrower to the user
        preInteractions[0] =
            CowProtocolInteraction.transferFrom(Constants.WETH, address(borrower), address(user), 10 ether);

        // 1) Mock the "fee payback" by giving flashloan fee to the borrower
        {
            uint256 _fee = 5000000000000000; // 10.005 is flashloan + fee. 0.005 is the fee in eth.
            deal(address(Constants.WETH), address(Constants.SETTLEMENT_CONTRACT), _fee);
            postInteractions[0] = CowProtocolInteraction.transfer(Constants.WETH, address(borrower), _fee);
        }

        // 2) Call helper.swapCollateral()
        postInteractions[1] = CowProtocolInteraction.orderHelperSwapCollateral(address(helper));

        // 3) Borrower needs to approve the pool so the flashloan tokens + fees can be pulled out
        postInteractions[2] =
            CowProtocolInteraction.borrowerApprove(borrower, Constants.WETH, address(POOL), type(uint256).max);

        bytes memory _settleCallData;
        {
            address[] memory tokens = new address[](2);
            uint256 wethIndex = 0;
            uint256 daiIndex = 1;
            tokens[wethIndex] = address(Constants.WETH);
            tokens[daiIndex] = address(Constants.DAI);

            uint256[] memory clearingPrices = new uint256[](2);
            clearingPrices[wethIndex] = order.buyAmount;
            clearingPrices[daiIndex] = order.sellAmount;

            ICowSettlement.Trade[] memory trades = new ICowSettlement.Trade[](1);
            trades[0] = derivePreSignTrade(order, wethIndex, daiIndex, user);

            ICowSettlement.Interaction[][3] memory interactions =
                [preInteractions, new ICowSettlement.Interaction[](0), postInteractions];

            _settleCallData = abi.encodeCall(ICowSettlement.settle, (tokens, clearingPrices, trades, interactions));
        }

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

    /// @dev Computes the order UID for an order and the given owner
    function computeOrderUid(GPv2Order.Data memory order, address owner) internal view returns (bytes memory) {
        bytes32 domainSeparator = IPreSignTarget(address(Constants.SETTLEMENT_CONTRACT)).domainSeparator();
        return abi.encodePacked(order.hash(domainSeparator), owner, order.validTo);
    }

    function derivePreSignTrade(
        GPv2Order.Data memory order,
        uint256 sellTokenIndex,
        uint256 buyTokenIndex,
        address owner
    ) internal pure returns (ICowSettlement.Trade memory) {
        assertEq(order.kind, GPv2Order.KIND_SELL, "Unsupported order kind");
        assertEq(order.partiallyFillable, false, "Unsupported partially fillable");
        assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20, "Unsupported order sell token balance");
        assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20, "Unsupported order buy token balance");
        bytes memory signature = abi.encodePacked(owner);
        return ICowSettlement.Trade(
            sellTokenIndex,
            buyTokenIndex,
            order.receiver,
            order.sellAmount,
            order.buyAmount,
            order.validTo,
            order.appData,
            order.feeAmount,
            packFlags(),
            order.sellAmount,
            signature
        );
    }

    function packFlags() internal pure returns (uint256) {
        // For information on flag encoding, see:
        // https://github.com/cowprotocol/contracts/blob/v1.0.0/src/contracts/libraries/GPv2Trade.sol#L70-L93
        uint256 sellOrderFlag = 0;
        uint256 fillOrKillFlag = 0 << 1;
        uint256 internalSellTokenBalanceFlag = 0 << 2;
        uint256 internalBuyTokenBalanceFlag = 0 << 4;
        uint256 preSignSignatureFlag = 3 << 5;
        return sellOrderFlag | fillOrKillFlag | internalSellTokenBalanceFlag | internalBuyTokenBalanceFlag
            | preSignSignatureFlag;
    }
}
