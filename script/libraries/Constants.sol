// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

/// @title Constants Library
/// @author CoW DAO developers
/// @notice A library defining constant variables used for smart contract deployments.
library Constants {
    address internal constant DEFAULT_SETTLEMENT_CONTRACT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant DEFAULT_AUTHENTICATOR = 0x2c4c28DDBdAc9C5E7055b4C863b72eA0149D8aFE;
    bytes32 internal constant SALT = bytes32(uint256(93));
}
