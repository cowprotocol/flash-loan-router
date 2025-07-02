// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IAavePool} from "../vendored/IAavePool.sol";
import {IERC20} from "../vendored/IERC20.sol";
import {SafeERC20} from "../vendored/SafeERC20.sol";

import {GPv2Order} from "./GPv2Order.sol";
import {ISettlement} from "./ISettlement.sol";
import {Initializable} from "./Initializable.sol";

interface IAaveToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}

library OrderHelperError {
    error BadParameters();
    error OrderDoesNotMatchMessageHash();
    error BadSellToken();
    error BadBuyToken();
    error NotSellOrder();
    error BadReceiver();
    error BadSellAmount();
    error NotEnoughSupplyAmount();
}

/// @title OrderHelper
/// @author CoW DAO developers
/// @notice A contract per order to handle collateral for collateral swap
contract OrderHelper is Initializable {
    using SafeERC20 for IERC20;
    using GPv2Order for GPv2Order.Data;

    address public constant SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address public constant AAVE_LENDING_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    address public owner;
    address public borrower;
    IERC20 public oldCollateral;
    IERC20 public newCollateral;
    uint256 public oldCollateralAmount;
    uint256 public flashloanFee;
    uint256 public minSupplyAmount;

    function initialize(
        address _owner,
        address _borrower,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint256 _flashloanFee
    ) external initializer {
        // TODO: check the other params?
        if (_owner == address(0)) {
            revert OrderHelperError.BadParameters();
        }

        owner = _owner;
        borrower = _borrower;
        oldCollateral = IERC20(_oldCollateral);
        newCollateral = IERC20(_newCollateral);
        oldCollateralAmount = _oldCollateralAmount;
        minSupplyAmount = _minSupplyAmount;
        flashloanFee = _flashloanFee;

        // Approve the _oldCollateral token for the swap
        IERC20(_oldCollateral).forceApprove(ISettlement(SETTLEMENT).vaultRelayer(), type(uint256).max);

        // Approve the new collateral to deposit into aave after the trade
        IERC20(_newCollateral).forceApprove(AAVE_LENDING_POOL, type(uint256).max);
    }

    function isValidSignature(bytes32 _orderHash, bytes calldata _signature) external view returns (bytes4) {
        // TODO: Grab order, user's signature from _signature
        // Validate the owner signed the order

        GPv2Order.Data memory _order = abi.decode(_signature, (GPv2Order.Data));

        bytes32 _rebuiltOrderHash = _order.hash(ISettlement(SETTLEMENT).domainSeparator());
        if (_orderHash != _rebuiltOrderHash) {
            revert OrderHelperError.OrderDoesNotMatchMessageHash();
        }

        if (_order.sellToken != oldCollateral) {
            revert OrderHelperError.BadSellToken();
        }

        if (_order.buyToken != newCollateral) {
            revert OrderHelperError.BadBuyToken();
        }

        if (_order.kind != GPv2Order.KIND_SELL) {
            revert OrderHelperError.NotSellOrder();
        }

        if (_order.receiver != address(this)) {
            revert OrderHelperError.BadReceiver();
        }

        if (_order.sellAmount != oldCollateralAmount) {
            revert OrderHelperError.BadSellAmount();
        }

        return this.isValidSignature.selector;
    }

    function swapCollateral() external {
        // TODO make this trampoline only?

        uint256 _supplyAmount = newCollateral.balanceOf(address(this));
        if (_supplyAmount < minSupplyAmount) {
            revert OrderHelperError.NotEnoughSupplyAmount();
        }
        IAavePool(AAVE_LENDING_POOL).supply(address(newCollateral), _supplyAmount, owner, 0);

        // Once the old collateral is unlocked, move it's atoken to this contract and withdraw to the borrower
        address _oldCollateralAToken = IAavePool(AAVE_LENDING_POOL).getReserveAToken(address(oldCollateral));
        IERC20(_oldCollateralAToken).transferFrom(owner, address(this), oldCollateralAmount);
        IAavePool(AAVE_LENDING_POOL).withdraw(address(oldCollateral), type(uint256).max, borrower);
    }
}
