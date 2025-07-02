// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Clones} from "./Clones.sol";

interface IOrderHelper {
    function initialize(
        address _owner,
        address _borrower,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint256 _flashloanFee
    ) external;
}

library FactoryErrors {
    error InvalidImplementationContract();
    error ContractAlreadyDeployed();
    error OrderHelperDeploymentFailed();
}

contract OrderHelperFactory {
    event NewOrderHelper(address indexed helper);

    address internal immutable HELPER_IMPLEMENTATION;

    constructor(address _helperImplementation) {
        HELPER_IMPLEMENTATION = _helperImplementation;
        if (HELPER_IMPLEMENTATION.code.length == 0) {
            revert FactoryErrors.InvalidImplementationContract();
        }
    }

    function deployOrderHelper(
        address _owner,
        address _borrower,
        address _oldCollateral,
        uint256 _oldCollateralAmount,
        address _newCollateral,
        uint256 _minSupplyAmount,
        uint256 _flashloanFee
    ) external returns (address orderHelperAddress) {
        bytes32 _salt = keccak256(
            abi.encode(
                _owner, _borrower, _oldCollateral, _oldCollateralAmount, _newCollateral, _minSupplyAmount, _flashloanFee
            )
        );
        orderHelperAddress = Clones.predictDeterministicAddress(HELPER_IMPLEMENTATION, _salt, address(this));

        if (orderHelperAddress.code.length > 0) {
            revert FactoryErrors.ContractAlreadyDeployed();
        }

        orderHelperAddress = Clones.cloneDeterministic(HELPER_IMPLEMENTATION, _salt);

        try IOrderHelper(orderHelperAddress).initialize(
            _owner, _borrower, _oldCollateral, _oldCollateralAmount, _newCollateral, _minSupplyAmount, _flashloanFee
        ) {
            emit NewOrderHelper(orderHelperAddress);
        } catch {
            revert FactoryErrors.OrderHelperDeploymentFailed();
        }
    }
}
