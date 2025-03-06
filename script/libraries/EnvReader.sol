// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8;

import {Script} from "forge-std/Script.sol";

abstract contract EnvReader is Script {
    address internal constant DEFAULT_SETTLEMENT_CONTRACT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant DEFAULT_TOKEN0 = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address internal constant DEFAULT_TOKEN1 = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address internal constant DEFAULT_UNISWAP_V2_FACTORY = 0xF62c03E08ada871A0bEb309762E260a7a6a880E6;

    address internal settlement;
    address internal token0;
    address internal token1;
    address internal uniswapV2Factory;

    function addressEnvOrDefault(string memory envName, address defaultAddr) internal view returns (address) {
        try vm.envAddress(envName) returns (address env) {
            return env;
        } catch {
            return defaultAddr;
        }
    }
}