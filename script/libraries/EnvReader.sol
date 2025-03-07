// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import {Script} from "forge-std/Script.sol";

abstract contract EnvReader is Script {
    address internal constant DEFAULT_SETTLEMENT_CONTRACT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    bytes32 constant SALT = bytes32(uint256(31415));

    function addressEnvOrDefault(string memory envName, address defaultAddr) internal view returns (address) {
        try vm.envAddress(envName) returns (address env) {
            return env;
        } catch {
            return defaultAddr;
        }
    }
}
