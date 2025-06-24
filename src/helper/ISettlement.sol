// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

/**
 * @title ISettlement
 * @notice External interface of CoW Protocol's SolutionSettler contract.
 */
interface ISettlement {
    /**
     * @return domainSeparator The domain separator for IERC1271 signature
     * @dev Immutable value, would not change on chain forks
     */
    function domainSeparator() external view returns (bytes32 domainSeparator);

    /**
     * @return vaultRelayer The address that'll use the pool liquidity in CoWprotocol swaps
     * @dev Address that will transfer and transferFrom the pool. Has an infinite allowance.
     */
    function vaultRelayer() external view returns (address vaultRelayer);
}
