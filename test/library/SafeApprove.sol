// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {IERC20, SafeApprove} from "src/library/SafeApprove.sol";

contract Caller {
    using SafeApprove for IERC20;

    function safeApprove(IERC20 token, address spender, uint256 value) external {
        token.safeApprove(spender, value);
    }
}

contract SafeApproveTest is Test {
    Caller caller;
    IERC20 token;
    address spender;
    uint256 value;

    function setUp() external {
        caller = new Caller();
        token = IERC20(makeAddr("SafeApproveTest.setUp: token"));
        spender = makeAddr("SafeApproveTest.setUp: spender");
        value = 42;
    }

    function test_succeedsOnSuccessfulErc20Approval() external {
        bytes memory approveData = abi.encodeCall(IERC20.approve, (spender, value));
        vm.expectCall(address(token), approveData);
        vm.mockCall(address(token), approveData, abi.encode(true));
        caller.safeApprove(token, spender, value);
    }

    function test_succeedsOnSuccessfulApprovalWithNoReturnData() external {
        bytes memory approveData = abi.encodeCall(IERC20.approve, (spender, value));
        vm.expectCall(address(token), approveData);
        vm.mockCall(address(token), approveData, hex"");
        caller.safeApprove(token, spender, value);
    }

    function test_revertsOnApprovalRevert() external {
        bytes memory approveData = abi.encodeCall(IERC20.approve, (spender, value));
        vm.mockCallRevert(address(token), approveData, "mock revert");
        vm.expectRevert("mock revert");
        caller.safeApprove(token, spender, value);
    }

    function test_revertsOnApprovalReturningFalse() external {
        bytes memory approveData = abi.encodeCall(IERC20.approve, (spender, value));
        vm.mockCall(address(token), approveData, abi.encode(false));
        vm.expectRevert("SafeApprove: operation failed");
        caller.safeApprove(token, spender, value);
    }
}
