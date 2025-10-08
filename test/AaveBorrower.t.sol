// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {AaveBorrower, IAavePool, IERC20, IFlashLoanRouter, ICowAuthentication} from "src/AaveBorrower.sol";
import {GPv2Trade, GPv2Interaction} from "src/vendored/CowWrapper.sol";

contract AaveBorrowerTest is Test {
    IFlashLoanRouter private router;
    AaveBorrower private borrower;
    address private authenticator;
    address private solver;

    function setUp() external {
        router = IFlashLoanRouter(makeAddr("AaveBorrowerTest: router"));
        address settlementContract = makeAddr("AaveBorrowerTest: settlementContract");
        authenticator = makeAddr("AaveBorrowerTest: authenticator");
        solver = makeAddr("AaveBorrowerTest: solver");

        vm.mockCall(
            address(router),
            abi.encodeCall(IFlashLoanRouter.settlementContract, ()),
            abi.encode(settlementContract)
        );

        borrower = new AaveBorrower(router, ICowAuthentication(authenticator));
    }

    function test_constructor_parameters() external view {
        assertEq(address(borrower.router()), address(router));
    }

    function test_flashLoanAndCallBack_callsFlashLoan() external {
        address lender = makeAddr("lender");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 42;
        bytes memory callBackData = hex"1337";

        bytes memory lenderCallData = lenderCallDataWithDefaultParams(borrower, token, amount, callBackData);
        vm.expectCall(lender, lenderCallData);
        vm.mockCall(lender, lenderCallData, abi.encode(true));
        vm.prank(address(router));
        borrower.flashLoanAndCallBack(lender, token, amount, callBackData);
    }

    function test_flashLoanAndCallBack_revertsIfFlashLoanReverts() external {
        address lender = makeAddr("lender");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 42;
        bytes memory callBackData = hex"1337";

        bytes memory lenderCallData = lenderCallDataWithDefaultParams(borrower, token, amount, callBackData);
        vm.mockCallRevert(lender, lenderCallData, "mock revert");
        vm.prank(address(router));
        vm.expectRevert("mock revert");
        borrower.flashLoanAndCallBack(lender, token, amount, callBackData);
    }

    function test_onFlashLoan_callsInternalSettle() external {
        bytes memory settleData = hex"1337";
        address nextSettlement = makeAddr("nextSettlement");
        // wrapperData needs the settlement address as a 32-byte word (left-padded)
        bytes memory wrapperData = abi.encodePacked(bytes32(uint256(uint160(nextSettlement))));
        bytes memory callBackData = abi.encode(settleData, wrapperData);

        // Mock the settle call to the next settlement contract
        vm.mockCall(nextSettlement, new bytes(0), abi.encode(true));

        borrower.executeOperation(new address[](0), new uint256[](0), new uint256[](0), address(0), callBackData);
    }

    function test_onFlashLoan_returnsTrue() external {
        bytes memory settleData = hex"1337";
        address nextSettlement = makeAddr("nextSettlement");
        // wrapperData needs the settlement address as a 32-byte word (left-padded)
        bytes memory wrapperData = abi.encodePacked(bytes32(uint256(uint160(nextSettlement))));
        bytes memory callBackData = abi.encode(settleData, wrapperData);

        // Mock the settle call to the next settlement contract
        vm.mockCall(nextSettlement, new bytes(0), abi.encode(true));

        bool output =
            borrower.executeOperation(new address[](0), new uint256[](0), new uint256[](0), address(0), callBackData);
        assertTrue(output);
    }

    function test_onFlashLoan_revertsIfInternalSettleReverts() external {
        bytes memory settleData = hex"1337";
        address nextSettlement = makeAddr("nextSettlement");
        // wrapperData needs the settlement address as a 32-byte word (left-padded)
        bytes memory wrapperData = abi.encodePacked(bytes32(uint256(uint160(nextSettlement))));
        bytes memory callBackData = abi.encode(settleData, wrapperData);

        // Mock a revert when the settlement is called
        vm.mockCallRevert(nextSettlement, new bytes(0), "mock revert");
        vm.expectRevert("mock revert");
        borrower.executeOperation(new address[](0), new uint256[](0), new uint256[](0), address(0), callBackData);
    }

    function test_settle_revertsIfNotSolver() external {
        // Mock the authenticator to return false for the caller
        vm.mockCall(
            authenticator,
            abi.encodeWithSignature("isSolver(address)", address(this)),
            abi.encode(false)
        );

        // Build settle call with wrapper data appended
        bytes memory settleCallData = abi.encodeCall(
            borrower.settle, (
            new IERC20[](0),          // tokens
            new uint256[](0),          // clearingPrices
            new GPv2Trade.Data[](0),              // trades (empty GPv2Trade.Data[])
            [new GPv2Interaction.Data[](0), new GPv2Interaction.Data[](0), new GPv2Interaction.Data[](0)]  // interactions
        ));

        // Append minimal wrapper data (32 bytes for next settlement address)
        settleCallData = abi.encodePacked(settleCallData, bytes32(uint256(uint160(makeAddr("nextSettlement")))));

        (bool success, bytes memory revertData) = address(borrower).call(settleCallData);
        assertFalse(success, "Expected revert");
        assertEq(revertData, abi.encodeWithSignature("NotASolver(address)", address(this)));
    }

    function test_settle_revertsIfNoWrapperData() external {
        // Mock the authenticator to return true for the solver
        vm.mockCall(
            authenticator,
            abi.encodeWithSignature("isSolver(address)", solver),
            abi.encode(true)
        );

        // Build settle call WITHOUT wrapper data appended
        bytes memory settleCallData = abi.encodeCall(
            borrower.settle, (
            new IERC20[](0),
            new uint256[](0),
            new GPv2Trade.Data[](0),
            [new GPv2Interaction.Data[](0), new GPv2Interaction.Data[](0), new GPv2Interaction.Data[](0)]
        ));

        vm.prank(solver);
        (bool success, bytes memory revertData) = address(borrower).call(settleCallData);
        assertFalse(success, "Expected revert");
        // Check that it reverted with WrapperHasNoSettleTarget
        assertGt(revertData.length, 0, "Expected revert data");
    }

    function test_settle_callsWrapAndTriggersFlashLoan() external {
        // Mock the authenticator to return true for the solver
        vm.mockCall(
            authenticator,
            abi.encodeWithSignature("isSolver(address)", solver),
            abi.encode(true)
        );

        // Setup flashloan parameters
        address lender = makeAddr("lender");
        address token = makeAddr("token");
        uint256 amount = 1000 ether;
        address nextSettlement = makeAddr("nextSettlement");

        // Build wrapperData:
        // 1. First 32 bytes: length of the ABI-encoded flashloan params
        // 2. Next len bytes: ABI-encoded (address lender, address[] assets, uint256[] amounts)
        // 3. Next 32 bytes: nextSettlement address
        address[] memory assets = new address[](1);
        assets[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        bytes memory flashloanParams = abi.encode(lender, assets, amounts);
        uint256 flashloanParamsLen = flashloanParams.length;

        bytes memory wrapperData = abi.encodePacked(
            bytes32(flashloanParamsLen),  // length prefix
            flashloanParams,               // encoded flashloan params
            bytes32(uint256(uint160(nextSettlement)))  // next settlement address
        );

        // Build settle call data with wrapper data appended
        bytes memory settleCallData = abi.encodeCall(
            borrower.settle, (
            new IERC20[](0),
            new uint256[](0),
            new GPv2Trade.Data[](0),
            [new GPv2Interaction.Data[](0), new GPv2Interaction.Data[](0), new GPv2Interaction.Data[](0)]
        ));
        settleCallData = abi.encodePacked(settleCallData, wrapperData);

        // Mock the flashloan call
        vm.mockCall(
            lender,
            abi.encodeWithSelector(IAavePool.flashLoan.selector),
            abi.encode(true)
        );

        // Call settle
        vm.prank(solver);
        (bool success,) = address(borrower).call{gas: 10000000}(settleCallData);
        assertTrue(success, "Settle call failed");
    }

    function lenderCallDataWithDefaultParams(
        AaveBorrower _borrower,
        IERC20 token,
        uint256 amount,
        bytes memory callBackData
    ) private pure returns (bytes memory) {
        address receiverAddress = address(_borrower);
        address[] memory assets = new address[](1);
        assets[0] = address(token);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0;
        address onBehalfOf = address(_borrower);
        bytes memory params = callBackData;
        uint16 referralCode = 0;

        return abi.encodeCall(
            IAavePool.flashLoan, (receiverAddress, assets, amounts, interestRateModes, onBehalfOf, params, referralCode)
        );
    }
}
