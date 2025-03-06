// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {Utils} from "script/libraries/Utils.sol";
import {EnvReader} from "script/libraries/EnvReader.sol";

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}


contract DeployUniswapV2Pool is Script, EnvReader, Utils {
    constructor() {
        // Initialise contracts
        token0 = addressEnvOrDefault("TOKEN0", DEFAULT_TOKEN0);
        console.log("Token0 contract at %s.", token0);
        require(token0 != address(0), "Invalid TOKEN0 address");
        assertHasCode(token0, "No code at expected TOKEN0 contract");

        token1 = addressEnvOrDefault("TOKEN1", DEFAULT_TOKEN1);
        console.log("Token1 contract at %s.", token1);
        require(token1 != address(0), "Invalid TOKEN1 address");
        assertHasCode(token1, "No code at expected TOKEN1 contract");

        uniswapV2Factory = addressEnvOrDefault("UNISWAP_V2_FACTORY", DEFAULT_UNISWAP_V2_FACTORY);
        console.log("Uniswap V2 Factory contract at %s.", uniswapV2Factory);
        require(uniswapV2Factory != address(0), "Invalid Uniswap V2 Factory address");
        assertHasCode(uniswapV2Factory, "no code at expected Uniswap V2 Factory contract");
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Create new Uniswap V2 pair
        address pair = deployUniswapV2USDCWETHPool();
        console.log("Uniswap V2 Pair (USDC/WETH) deployed at:", pair);
        
        vm.stopBroadcast();
    }

    function deployUniswapV2USDCWETHPool() internal returns (address pair) {
        IUniswapV2Factory factory = IUniswapV2Factory(uniswapV2Factory);
        pair = factory.createPair(token0, token1);
        
        IUniswapV2Pair uniswapV2Pair = IUniswapV2Pair(pair);
        require(uniswapV2Pair.token0() == token0 || uniswapV2Pair.token0() == token1, "Token0 incorrectly set");
        require(uniswapV2Pair.token1() == token0 || uniswapV2Pair.token1() == token1, "Token1 incorrectly set");
    }
}
