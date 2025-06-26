// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IAavePool} from "./vendored/IAavePool.sol";
import {IERC20} from "./vendored/IERC20.sol";
import {SafeERC20} from "./vendored/SafeERC20.sol";

/// @title AaveHelper
/// @author CoW DAO developers
/// @notice A helpful helper.
contract AaveHelper {
    using SafeERC20 for IERC20;

    address public constant AAVE_LENDING_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    function swap(address _oldCollateral, address _newCollateral, address _user, uint256 _pullAmount) external {
        // TODO: check what happens if newCollateral balance is 0.

        uint256 _supplyAmount = IERC20(_newCollateral).balanceOf(address(this));
        IERC20(_newCollateral).forceApprove(AAVE_LENDING_POOL, _supplyAmount);
        IAavePool(AAVE_LENDING_POOL).supply(_newCollateral, _supplyAmount, _user, 0);

        // Once the old collateral is unlocked, move it's atoken to this contract and withdraw to the user
        address _oldCollateralAToken = IAavePool(AAVE_LENDING_POOL).getReserveAToken(_oldCollateral);
        IERC20(_oldCollateralAToken).transferFrom(_user, address(this), _pullAmount);
        IAavePool(AAVE_LENDING_POOL).withdraw(_oldCollateral, type(uint256).max, _user);
    }
}
