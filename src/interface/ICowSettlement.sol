// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

/// @notice An interface for CoW Protocol's settlement contract that only
/// enumerates the functions and types needed for this project.
/// For more information, see the project's repository:
/// <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/GPv2Settlement.sol>
interface ICowSettlement {
    /// @dev See <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/libraries/GPv2Trade.sol#L14-L28>.
    struct Trade {
        uint256 sellTokenIndex;
        uint256 buyTokenIndex;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        uint256 flags;
        uint256 executedAmount;
        bytes signature;
    }

    /// @dev See <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/libraries/GPv2Interaction.sol#L7-L13>.
    struct Interaction {
        address target;
        uint256 value;
        bytes callData;
    }

    /// @dev See <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/GPv2Settlement.sol#L28-L32>.
    function authenticator() external returns (address);

    /// @dev See <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/GPv2Settlement.sol#L99-L126>.
    function settle(address[] calldata, uint256[] calldata, Trade[] calldata, Interaction[][3] calldata) external;
}
