// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IERC20} from "../vendored/IERC20.sol";

/// @title Safe-approve Library
/// @author CoW DAO developers
/// @notice This library includes the `safeApprove` function, which supports
/// calling `approve` on some common tokens that aren't fully ERC-20 compliant.
library SafeApprove {
    /// @notice This calls the `approve` function on the target token with the
    /// specified parameters. It has less strict requirements on the format of
    /// the call return value, accepting either a standard-conforming bool or no
    /// return value. If the approval fails (e.g., by returning `false`) then
    /// this function reverts.
    /// @param token The token to approve.
    /// @param spender The address approved to spend the tokens.
    /// @param value The value of the approval.
    ///
    /// This code is based on OpenZeppelin contracts v5.2:
    /// <https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/token/ERC20/utils/SafeERC20.sol#L78-L94>
    /// In the same way as `safeApprove`, it supports ERC-20-compliant tokens
    /// as well as tokens that don't return any value when calling `approve`.
    /// There is however a major difference: `forceApprove` (as well as the
    /// now-removed `safeApprove`) also supports setting an allowance for the
    /// USDT token when the current allowance isn't zero (a normal call to
    /// `approve` in this scenario would revert).
    /// Removing this feature makes the implementation simpler and also
    /// guarantees that using `safeApprove` leads to exactly one call to
    /// `approve`. In the context of this repository, approvals are done as
    /// arbitrary calls and this feature is supported by performing two calls
    /// instead of one: setting the approval to zero first and then setting
    /// the desired approval.
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        _callOptionalReturn(token, approvalCall);
    }

    /// @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
    /// on the return value: the return value is optional (but if data is returned, it must not be false).
    /// @param token The token targeted by the call.
    /// @param data The call data (encoded using abi.encode or one of its variants).
    ///
    /// This code is based on OpenZeppelin contracts v5.2:
    /// <https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/token/ERC20/utils/SafeERC20.sol#L151-L177>
    /// The only change is using a string error instead of a custom error.
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            let success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            // bubble errors
            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        if (returnSize == 0 ? address(token).code.length == 0 : returnValue != 1) {
            revert("SafeApprove: operation failed");
        }
    }
}
