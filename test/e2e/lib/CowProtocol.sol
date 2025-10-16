// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {CowSettlement} from "src/vendored/CowWrapper.sol";

import {Constants} from "./Constants.sol";

library CowProtocol {
    function addSolver(Vm vm, address solver) internal {
        vm.prank(Constants.AUTHENTICATOR_MANAGER);
        Constants.SOLVER_AUTHENTICATOR.addSolver(solver);
    }

    function emptySettleWithInteractions(CowSettlement.CowInteractionData[] memory intraInteractions) internal {
        (
            address[] memory noTokens,
            uint256[] memory noPrices,
            CowSettlement.CowTradeData[] memory noTrades,
            CowSettlement.CowInteractionData[][3] memory interactions
        ) = emptySettleInputWithInteractions(intraInteractions);

        Constants.SETTLEMENT_CONTRACT.settle(noTokens, noPrices, noTrades, interactions);
    }

    function encodeEmptySettleWithInteractions(CowSettlement.CowInteractionData[] memory intraInteractions)
        internal
        pure
        returns (bytes memory)
    {
        (
            address[] memory noTokens,
            uint256[] memory noPrices,
            CowSettlement.CowTradeData[] memory noTrades,
            CowSettlement.CowInteractionData[][3] memory interactions
        ) = emptySettleInputWithInteractions(intraInteractions);

        return abi.encodeCall(CowSettlement.settle, (noTokens, noPrices, noTrades, interactions));
    }

    function emptySettleInputWithInteractions(CowSettlement.CowInteractionData[] memory intraInteractions)
        internal
        pure
        returns (
            address[] memory noTokens,
            uint256[] memory noPrices,
            CowSettlement.CowTradeData[] memory noTrades,
            CowSettlement.CowInteractionData[][3] memory interactions
        )
    {
        noTokens = new address[](0);
        noPrices = new uint256[](0);
        noTrades = new CowSettlement.CowTradeData[](0);
        CowSettlement.CowInteractionData[] memory noInteractions = new CowSettlement.CowInteractionData[](0);
        interactions = [noInteractions, intraInteractions, noInteractions];
    }
}
