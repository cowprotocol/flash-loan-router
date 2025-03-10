// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

library Constants {
    address internal constant DEFAULT_SETTLEMENT_CONTRACT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant DETERMINISTIC_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes32 internal constant SALT = bytes32(uint256(31415));
}
