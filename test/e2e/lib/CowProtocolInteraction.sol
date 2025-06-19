// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {TokenBalanceAccumulator} from "./TokenBalanceAccumulator.sol";
import {IFlashLoanTracker} from "src/FlashLoanTracker.sol";
import {IBorrower, ICowSettlement, IERC20} from "src/interface/IBorrower.sol";

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

    function borrowerApprove(IBorrower borrower, IERC20 token, address spender, uint256 amount)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(borrower),
            value: 0,
            callData: abi.encodeCall(IBorrower.approve, (token, spender, amount))
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

    function repayLoan(IFlashLoanTracker tracker, address pool, address token, uint256 amount, address onBehalfOf)
        internal
        pure
        returns (ICowSettlement.Interaction memory)
    {
        return ICowSettlement.Interaction({
            target: address(tracker),
            value: 0,
            callData: abi.encodeCall(IFlashLoanTracker.repay, (pool, token, amount, 2, onBehalfOf))
        });
    }
}
