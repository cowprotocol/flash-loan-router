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
    error AppDataDoesNotMatch();
    error OrderDoesNotMatchMessageHash();
    error BadSellToken();
    error BadBuyToken();
    error WrongValidTo();
    error NotSellOrder();
    error BadReceiver();
    error BadSellAmount();
    error FeeIsNotZero();
    error NotEnoughBuyAmount();
    error NoPartiallyFillable();
    error OnlyBalanceERC20();
    error NotEnoughSupplyAmount();
    error NotLongerValid();
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
    uint256 public oldCollateralAmount;
    IERC20 public newCollateral;
    uint256 public minSupplyAmount;
    uint32 public validTo;
    bytes32 public appData;

    function initialize(
        address _owner,
        address _borrower,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo,
        bytes32 _appData
    ) external initializer {
        // TODO: check the other params?
        if (_owner == address(0)) {
            revert OrderHelperError.BadParameters();
        }

        if (_validTo < block.timestamp) {
            revert OrderHelperError.BadParameters();
        }

        owner = _owner;
        borrower = _borrower;
        oldCollateral = IERC20(_oldCollateral);
        newCollateral = IERC20(_newCollateral);
        oldCollateralAmount = _oldCollateralAmount;
        minSupplyAmount = _minSupplyAmount;
        validTo = _validTo;
        appData = _appData;

        // Approve the _oldCollateral token for the swap
        IERC20(_oldCollateral).forceApprove(ISettlement(SETTLEMENT).vaultRelayer(), type(uint256).max);

        // Approve the new collateral to deposit into aave after the trade
        IERC20(_newCollateral).forceApprove(AAVE_LENDING_POOL, type(uint256).max);
    }

    function isValidSignature(bytes32 _orderHash, bytes calldata _signature) external view returns (bytes4) {
        GPv2Order.Data memory _order = abi.decode(_signature, (GPv2Order.Data));

        if (_order.appData != appData) {
            revert OrderHelperError.AppDataDoesNotMatch();
        }

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

        if (_order.validTo != validTo) {
            revert OrderHelperError.WrongValidTo();
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

        if (_order.feeAmount != 0) {
            revert OrderHelperError.FeeIsNotZero();
        }

        if (_order.buyAmount < minSupplyAmount) {
            revert OrderHelperError.NotEnoughBuyAmount();
        }

        if (_order.partiallyFillable) {
            revert OrderHelperError.NoPartiallyFillable();
        }

        if (_order.sellTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert OrderHelperError.OnlyBalanceERC20();
        }

        if (_order.buyTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert OrderHelperError.OnlyBalanceERC20();
        }

        return this.isValidSignature.selector;
    }

    function swapCollateral() external {
        if (validTo < block.timestamp) {
            revert OrderHelperError.NotLongerValid();
        }

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
