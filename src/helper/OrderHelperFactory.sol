// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IERC20} from "../vendored/IERC20.sol";
import {SafeERC20} from "../vendored/SafeERC20.sol";
import {Clones} from "./Clones.sol";

interface IOrderHelper {
    function initialize(
        address _owner,
        address _tracker,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo,
        uint256 _flashloanFee,
        address _factory
    ) external;

    function owner() external view returns (address);
    function tracker() external view returns (address);
    function oldCollateral() external view returns (address);
    function oldCollateralAmount() external view returns (uint256);
    function newCollateral() external view returns (address);
    function minSupplyAmount() external view returns (uint256);
    function validTo() external view returns (uint32);
    function flashloanFee() external view returns (uint256);
}

library FactoryErrors {
    error InvalidImplementationContract();
    error ContractAlreadyDeployed();
    error OrderHelperDeploymentFailed();
    error BadHelper();
    error OwnerDidNotApproveTransfer();
}

contract OrderHelperFactory {
    using SafeERC20 for IERC20;

    event NewOrderHelper(address indexed helper);

    address internal immutable HELPER_IMPLEMENTATION;
    address public immutable AAVE_LENDING_POOL;

    // owner -> orderHelper instance -> order digest -> bool
    //mapping(address => mapping(address => mapping(bytes32 => bool))) preSignedOrders;

    constructor(address _helperImplementation, address _aaveLendingPool) {
        HELPER_IMPLEMENTATION = _helperImplementation;
        if (HELPER_IMPLEMENTATION.code.length == 0) {
            revert FactoryErrors.InvalidImplementationContract();
        }

        AAVE_LENDING_POOL = _aaveLendingPool;
    }

    function getOrderHelperAddress(
        address _owner,
        address _tracker,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo,
        uint256 _flashloanFee
    ) public view returns (address orderHelperAddress) {
        bytes32 _salt = keccak256(
            abi.encode(
                _owner,
                _tracker,
                _oldCollateral,
                _oldCollateralAmount,
                _newCollateral,
                _minSupplyAmount,
                _validTo,
                _flashloanFee
            )
        );
        orderHelperAddress = Clones.predictDeterministicAddress(HELPER_IMPLEMENTATION, _salt, address(this));
    }

    function deployOrderHelper(
        address _owner,
        address _tracker,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint32 _validTo,
        uint256 _flashloanFee
    ) external returns (address orderHelperAddress) {
        bytes32 _salt = keccak256(
            abi.encode(
                _owner,
                _tracker,
                _oldCollateral,
                _oldCollateralAmount,
                _newCollateral,
                _minSupplyAmount,
                _validTo,
                _flashloanFee
            )
        );
        orderHelperAddress = Clones.predictDeterministicAddress(HELPER_IMPLEMENTATION, _salt, address(this));

        if (orderHelperAddress.code.length > 0) {
            revert FactoryErrors.ContractAlreadyDeployed();
        }

        orderHelperAddress = Clones.cloneDeterministic(HELPER_IMPLEMENTATION, _salt);

        try IOrderHelper(orderHelperAddress).initialize(
            _owner,
            _tracker,
            _oldCollateral,
            _oldCollateralAmount,
            _newCollateral,
            _minSupplyAmount,
            _validTo,
            _flashloanFee,
            address(this)
        ) {
            emit NewOrderHelper(orderHelperAddress);
        } catch {
            revert FactoryErrors.OrderHelperDeploymentFailed();
        }
    }

    function transferFromOwner(address _token, uint256 _amount) external {
        IOrderHelper _helper = IOrderHelper(msg.sender);
        if (_predeterministicAddressFromHelper(_helper) != address(_helper)) {
            revert FactoryErrors.BadHelper();
        }

        // if (!preApprovedContracts[_helper.owner()][address(_helper)]) {
        //     revert FactoryErrors.OwnerDidNotApproveTransfer();
        // }

        IERC20(_token).safeTransferFrom(_helper.owner(), address(_helper), _amount);
    }

    function _predeterministicAddressFromHelper(IOrderHelper _helper) internal view returns (address) {
        return getOrderHelperAddress(
            _helper.owner(),
            _helper.tracker(),
            _helper.oldCollateral(),
            _helper.oldCollateralAmount(),
            _helper.newCollateral(),
            _helper.minSupplyAmount(),
            _helper.validTo(),
            _helper.flashloanFee()
        );
    }
}
