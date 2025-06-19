// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {SafeTransfer} from "./SafeTransfer.sol";
import {IAavePool} from "./vendored/IAavePool.sol";
import {IERC20} from "./vendored/IERC20.sol";
import {SafeERC20} from "./vendored/SafeERC20.sol";

interface IFlashLoanTracker {
    function repay(address pool, address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf)
        external
        returns (uint256);
}

/// @title Flash Loan Tracker
/// @author CoW DAO developers
/// @notice A separate settlement contract for flashloan actions.
contract FlashLoanTracker {
    using SafeERC20 for IERC20;

    address private settlementContract;

    constructor(address _settlementContract) {
        settlementContract = _settlementContract;
    }

    function repay(address pool, address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf)
        external
        returns (uint256)
    {
        return IAavePool(pool).repay(asset, amount, interestRateMode, onBehalfOf);
    }

    function approve(IERC20 token, address target, uint256 amount) external {
        require(msg.sender == settlementContract);
        token.forceApprove(target, amount);
    }

    function supply(address atoken, address asset, uint256 amount, address destination) external {
        IAavePool(atoken).supply(asset, amount, destination, 0);
    }

    function withdraw(address atoken, uint256 amount, address asset, address destination) external {
        IAavePool(atoken).withdraw(asset, amount, destination);
    }

    function sweep(address[] calldata _tokens, uint256[] calldata _amounts) external {
        address _settlement = settlementContract;
        require(msg.sender == _settlement);

        if (_tokens.length != _amounts.length) {
            revert("todo: do an error lib");
        }

        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] == address(0)) {
                SafeTransfer._safeTransferETH(_settlement, _amounts[i]);
            } else {
                SafeTransfer._safeTransfer(_tokens[i], _settlement, _amounts[i]);
            }
        }
    }
}
