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

    IAavePool internal constant AAVE_POOL = IAavePool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    uint256 private constant MAINNET_FORK_BLOCK = 22828430;
    address private solver = makeAddr("E2eHelperContract: solver");
    address private user;
    uint256 private userKey;

    AaveBorrower private borrower;
    FlashLoanRouter private router;
    OrderHelperFactory private factory;

    function setUp() external {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);
        (user, userKey) = makeAddrAndKey("E2eHelperContract: user");
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
        factory = new OrderHelperFactory(address(new OrderHelper()), address(AAVE_POOL));

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
            0.1 ether
        );

        OrderHelper helper = OrderHelper(_clone);
        assertEq(helper.owner(), user);
        assertEq(address(helper.borrower()), address(borrower));
        assertEq(address(helper.oldCollateral()), address(Constants.WETH));
        assertEq(address(helper.oldCollateralAToken()), address(Constants.AWETH));
        assertEq(helper.oldCollateralAmount(), 10 ether);
        assertEq(address(helper.newCollateral()), address(Constants.DAI));
        assertEq(address(helper.newCollateralAToken()), address(Constants.ADAI));
        assertEq(helper.minSupplyAmount(), 2500 ether);
        assertEq(helper.validTo(), 0xffffffff);
        assertEq(helper.flashloanFee(), 0.1 ether);
        assertEq(address(helper.factory()), address(factory));
    }

    function test_10WethCollatWith100UsdsSwappingCollateralForDaiWithFlashLoan() external {
        vm.startPrank(user);
        Constants.WETH.approve(address(AAVE_POOL), type(uint256).max);
        AAVE_POOL.supply(address(Constants.WETH), 10 ether, user, 0);
        AAVE_POOL.borrow(address(Constants.USDS), 100 ether, 2, 0, user);
        vm.stopPrank();
        assertEq(Constants.AWETH.balanceOf(user), 10 ether);
        assertEq(Constants.USDS.balanceOf(user), 100 ether);

        uint256 _flashloanFee = 5000000000000000; // 10.005 is flashloan + fee. 0.005 is the fee in eth.

        // Get the predeterministic order helper address. Contract will be deployed in a hook
        address _helperAddress = factory.getOrderHelperAddress(
            user,
            address(borrower),
            address(Constants.WETH),
            10 ether,
            address(Constants.DAI),
            2_500 ether,
            0xffffffff,
            _flashloanFee
        );

        // User approvals and pre-actions
        vm.startPrank(user);
        // Approve the helper factory to pull the atokens
        Constants.AWETH.approve(address(factory), 10 ether);
        // Presign the helper
        //factory.setPreApprovedContracts(_helperAddress);
        vm.stopPrank();

        // Ensure there are 2.5k ADAI in the settlement contract so the trade works
        deal(address(Constants.DAI), address(Constants.SETTLEMENT_CONTRACT), 2_500 ether);
        vm.startPrank(address(Constants.SETTLEMENT_CONTRACT));
        Constants.DAI.approve(address(AAVE_POOL), type(uint256).max);
        AAVE_POOL.supply(address(Constants.DAI), 2500 ether, address(Constants.SETTLEMENT_CONTRACT), 0);
        vm.stopPrank();

        // Flashloan definition
        Loan.Data[] memory _loans = new Loan.Data[](1);
        _loans[0] = Loan.Data({amount: 10 ether, borrower: borrower, lender: address(AAVE_POOL), token: Constants.WETH});

        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: Constants.AWETH,
            buyToken: Constants.ADAI,
            receiver: user,
            sellAmount: 10 ether - _flashloanFee,
            buyAmount: 2_500 ether,
            validTo: type(uint32).max,
            appData: bytes32(0),
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        ICowSettlement.Interaction[] memory preInteractions = new ICowSettlement.Interaction[](3);
        ICowSettlement.Interaction[] memory postInteractions = new ICowSettlement.Interaction[](2);

        // PRE-0) Driver calls borrower.takeOut()
        preInteractions[0] = CowProtocolInteraction.takeOut(address(borrower), _helperAddress, Constants.WETH, 10 ether);

        // PRE-1) Deploy the helper instance
        preInteractions[1] = CowProtocolInteraction.deployOrderHelper(
            address(factory),
            user,
            address(borrower),
            address(Constants.WETH),
            10 ether,
            address(Constants.DAI),
            2_500 ether,
            0xffffffff,
            _flashloanFee
        );

        // PRE-2) Order helper preHook()
        preInteractions[2] = CowProtocolInteraction.orderHelperPreHook(_helperAddress);

        // POST-1) Call helper.postHook()
        postInteractions[0] = CowProtocolInteraction.orderHelperPostHook(_helperAddress);

        // POST-2) Borrower needs to approve the pool so the flashloan tokens + fees can be pulled out
        postInteractions[1] = CowProtocolInteraction.borrowerApprove(
            borrower, Constants.WETH, address(AAVE_POOL), 10 ether + _flashloanFee
        );

        bytes memory _settleCallData;
        {
            address[] memory tokens = new address[](2);
            uint256 awethIndex = 0;
            uint256 adaiIndex = 1;
            tokens[awethIndex] = address(Constants.AWETH);
            tokens[adaiIndex] = address(Constants.ADAI);

            uint256[] memory clearingPrices = new uint256[](2);
            clearingPrices[awethIndex] = order.buyAmount;
            clearingPrices[adaiIndex] = order.sellAmount;

            ICowSettlement.Trade[] memory trades = new ICowSettlement.Trade[](1);

            bytes32 domainSeparator = IPreSignTarget(address(Constants.SETTLEMENT_CONTRACT)).domainSeparator();
            bytes32 orderDigest = order.hash(domainSeparator);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(userKey, orderDigest);
            bytes memory userSignature = abi.encodePacked(r, s, v);
            bytes memory signature = abi.encode(order, userSignature);
            trades[0] = deriveEip1271Trade(order, awethIndex, adaiIndex, _helperAddress, signature);

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
        assertEq(Constants.AWETH.balanceOf(_helperAddress), 0);
        assertEq(Constants.WETH.balanceOf(_helperAddress), 0);
        assertEq(Constants.ADAI.balanceOf(_helperAddress), 0);

        // borrower final state
        assertEq(Constants.WETH.balanceOf(address(borrower)), 0);
    }

    /// @dev Computes the order UID for an order and the given owner
    function computeOrderUid(GPv2Order.Data memory order, address owner) internal view returns (bytes memory) {
        bytes32 domainSeparator = IPreSignTarget(address(Constants.SETTLEMENT_CONTRACT)).domainSeparator();
        return abi.encodePacked(order.hash(domainSeparator), owner, order.validTo);
    }

    function deriveEip1271Trade(
        GPv2Order.Data memory order,
        uint256 sellTokenIndex,
        uint256 buyTokenIndex,
        address owner,
        bytes memory signature
    ) internal pure returns (ICowSettlement.Trade memory) {
        assertEq(order.kind, GPv2Order.KIND_SELL, "Unsupported order kind");
        assertEq(order.partiallyFillable, false, "Unsupported partially fillable");
        assertEq(order.sellTokenBalance, GPv2Order.BALANCE_ERC20, "Unsupported order sell token balance");
        assertEq(order.buyTokenBalance, GPv2Order.BALANCE_ERC20, "Unsupported order buy token balance");
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
            abi.encodePacked(owner, signature)
        );
    }

    function packFlags() internal pure returns (uint256) {
        // For information on flag encoding, see:
        // https://github.com/cowprotocol/contracts/blob/v1.0.0/src/contracts/libraries/GPv2Trade.sol#L70-L93
        uint256 sellOrderFlag = 0;
        uint256 fillOrKillFlag = 0 << 1;
        uint256 internalSellTokenBalanceFlag = 0 << 2;
        uint256 internalBuyTokenBalanceFlag = 0 << 4;
        uint256 eip1271Flag = 2 << 5;
        return sellOrderFlag | fillOrKillFlag | internalSellTokenBalanceFlag | internalBuyTokenBalanceFlag | eip1271Flag;
    }
}
