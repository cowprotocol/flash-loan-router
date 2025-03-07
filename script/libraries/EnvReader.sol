// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import {Script} from "forge-std/Script.sol";

abstract contract EnvReader is Script {
    address internal constant DEFAULT_SETTLEMENT_CONTRACT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    bytes32 constant SALT = bytes32(uint256(31415));

    address internal settlement;

    function addressEnvOrDefault(string memory envName, address defaultAddr, bool isVariable)
        internal
        view
        returns (address)
    {
        if (!isVariable) {
            return defaultAddr;
        }

        try vm.envAddress(envName) returns (address env) {
            return env;
        } catch {
            return defaultAddr;
        }
    }
}
