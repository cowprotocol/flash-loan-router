// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {ICowSettlement, IERC20, IFlashLoanSolverWrapper} from "src/interface/IFlashLoanSolverWrapper.sol";

import {TokenBalanceAccumulator} from "./TokenBalanceAccumulator.sol";

library CowProtocolInteraction {
    function transferFrom(IERC20 token, address from, address to, uint256 amount)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(token),
            value: 0,
            callData: abi.encodeCall(IERC20.transferFrom, (from, to, amount))
        });
    }

    function transfer(IERC20 token, address to, uint256 amount)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(token),
            value: 0,
            callData: abi.encodeCall(IERC20.transfer, (to, amount))
        });
    }

    function wrapperApprove(IFlashLoanSolverWrapper solverWrapper, IERC20 token, address spender, uint256 amount)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(solverWrapper),
            value: 0,
            callData: abi.encodeCall(IFlashLoanSolverWrapper.approve, (token, spender, amount))
        });
    }

    function pushBalanceToAccumulator(TokenBalanceAccumulator tokenBalanceAccumulator, IERC20 token, address owner)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(tokenBalanceAccumulator),
            value: 0,
            callData: abi.encodeCall(TokenBalanceAccumulator.push, (token, owner))
        });
    }
}
