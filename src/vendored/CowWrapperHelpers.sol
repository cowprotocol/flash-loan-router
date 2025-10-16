// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import "forge-std/console.sol";

import {CowAuthentication, ICowWrapper} from "./CowWrapper.sol";

/// @title CoW Protocol Wrapper Helpers
/// @notice Helper contract providing validation and encoding utilities for CoW Protocol wrapper chains
/// @dev This contract is not designed to be gas-efficient and is intended for off-chain use only.
contract CowWrapperHelpers {
    /// @notice Thrown when a provided address is not an authenticated wrapper
    /// @param wrapperIndex The index of the invalid wrapper in the array
    /// @param unauthorized The address that is not authenticated as a wrapper
    /// @param authenticatorContract The authentication contract that rejected the wrapper
    error NotAWrapper(uint256 wrapperIndex, address unauthorized, address authenticatorContract);

    /// @notice Thrown when a wrapper's parseWrapperData doesn't fully consume its data
    /// @param wrapperIndex The index of the wrapper that didn't consume all its data
    /// @param remainingWrapperData The data that was not consumed by the wrapper
    error WrapperDataNotFullyConsumed(uint256 wrapperIndex, bytes remainingWrapperData);

    /// @notice Thrown when a wrapper's parseWrapperData reverts, which is assumed to be due to malformed data
    /// @param wrapperIndex The index of the wrapper with malformed data
    /// @param wrapperError The error returned by the wrapper's parseWrapperData
    error WrapperDataMalformed(uint256 wrapperIndex, bytes wrapperError);

    /// @notice Thrown when the settlement contract is authenticated as a solver
    /// @dev The settlement contract should not be a solver to prevent direct settlement calls bypassing wrappers
    /// @param settlementContract The settlement contract address
    /// @param authenticatorContract The authentication contract that authenticated the settlement as a solver
    error SettlementContractShouldNotBeSolver(address settlementContract, address authenticatorContract);

    /// @notice A definition for a single call to a wrapper
    /// @dev This corresponds to the `wrappers` item structure on the CoW Orderbook API
    struct WrapperCall {
        /// @notice The smart contract that will be receiving the call
        address target;

        /// @notice Any additional data which will be required to execute the wrapper call
        bytes data;
    }

    /// @notice The authentication contract used to verify wrapper contracts
    CowAuthentication public immutable WRAPPER_AUTHENTICATOR;

    /// @notice The authentication contract used to verify solvers
    CowAuthentication public immutable SOLVER_AUTHENTICATOR;

    /// @notice Constructs a new CowWrapperHelpers contract
    /// @param wrapperAuthenticator_ The CowAuthentication contract used to verify wrapper contracts
    /// @param solverAuthenticator_ The CowAuthentication contract used to verify solvers
    constructor(CowAuthentication wrapperAuthenticator_, CowAuthentication solverAuthenticator_) {
        WRAPPER_AUTHENTICATOR = wrapperAuthenticator_;
        SOLVER_AUTHENTICATOR = solverAuthenticator_;
    }

    /// @notice Validates a wrapper chain configuration and builds the properly formatted wrapper data
    /// @dev Performs comprehensive validation of the wrapper chain before encoding:
    ///      1. Verifies each wrapper is authenticated via WRAPPER_AUTHENTICATOR
    ///      2. Verifies each wrapper's data is valid and fully consumed by calling parseWrapperData
    ///      3. Verifies the settlement contract is not authenticated as a solver
    ///      The returned wrapper data format is: [data0][addr1][data1][addr2][data2]...[settlement]
    ///      where data0 is for the first wrapper, addr1 is the second wrapper address, etc.
    /// @param wrapperCalls Array of calls in execution order
    /// @param settlementContract The final settlement contract address to call after all wrappers
    /// @return wrapperData The encoded wrapper data ready to be passed to the first wrapper's wrappedSettle
    function verifyAndBuildWrapperData(WrapperCall[] memory wrapperCalls, address settlementContract) external view returns (bytes memory wrapperData) {
        for (uint256 i = 0;i < wrapperCalls.length;i++) {
            // Wrapper must be authorized
            if (!WRAPPER_AUTHENTICATOR.isSolver(wrapperCalls[i].target)) {
                revert NotAWrapper(i, wrapperCalls[i].target, address(WRAPPER_AUTHENTICATOR));
            }


            // The wrapper data must be parsable and fully consumed
            try ICowWrapper(wrapperCalls[i].target).parseWrapperData(wrapperCalls[i].data) returns (bytes memory remainingWrapperData) {
                if (remainingWrapperData.length > 0) {
                    revert WrapperDataNotFullyConsumed(i, remainingWrapperData);
                }
            } catch (bytes memory err) {
                revert WrapperDataMalformed(i, err);
            }
        }

        // The Settlement Contract should not be a solver
        if (SOLVER_AUTHENTICATOR.isSolver(settlementContract)) {
            revert SettlementContractShouldNotBeSolver(settlementContract, address(SOLVER_AUTHENTICATOR));
        }

        if (wrapperCalls.length > 0) {
            wrapperData = abi.encodePacked(wrapperCalls[0].data);

            for (uint256 i = 1;i < wrapperCalls.length;i++) {
                wrapperData = abi.encodePacked(wrapperData, wrapperCalls[i].target, wrapperCalls[i].data);
            }
        }

        wrapperData = abi.encodePacked(wrapperData, settlementContract);

        return wrapperData;
    }
}
