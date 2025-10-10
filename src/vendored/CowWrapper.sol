// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

/// @title Gnosis Protocol v2 Authentication Interface
/// @author Gnosis Developers
interface GPv2Authentication {
    /// @dev determines whether the provided address is an authenticated solver.
    /// @param prospectiveSolver the address of prospective solver.
    /// @return true when prospectiveSolver is an authenticated solver, otherwise false.
    function isSolver(address prospectiveSolver) external view returns (bool);
}

/// @title CoW Settlement Interface
/// @notice Minimal interface for CoW Protocol's settlement contract
/// @dev Used for type-safe calls to the settlement contract's settle function
interface CowSettlement {
    /// @notice Trade data structure matching GPv2Settlement
    struct GPv2TradeData {
        uint256 sellTokenIndex;
        uint256 buyTokenIndex;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        uint256 flags;
        uint256 executedAmount;
        bytes signature;
    }

    /// @notice Interaction data structure for pre/intra/post-settlement hooks
    struct GPv2InteractionData {
        address target;
        uint256 value;
        bytes callData;
    }

    /// @notice Settles a batch of trades atomically
    /// @param tokens Array of token addresses involved in the settlement
    /// @param clearingPrices Array of clearing prices for each token
    /// @param trades Array of trades to execute
    /// @param interactions Array of three interaction arrays (pre, intra, post-settlement)
    function settle(
        address[] calldata tokens,
        uint256[] calldata clearingPrices,
        GPv2TradeData[] calldata trades,
        GPv2InteractionData[][3] calldata interactions
    ) external;
}

/// @title CoW Wrapper Interface
/// @notice Interface for wrapper contracts that add custom logic around CoW settlements
/// @dev Wrappers can be chained together to compose multiple settlement operations
interface ICowWrapper {
    /// @notice Initiates a wrapped settlement call
    /// @dev This is the entry point for wrapped settlements. The wrapper will execute custom logic
    ///      before calling the next wrapper or settlement contract in the chain.
    /// @param settleData ABI-encoded call to CowSettlement.settle()
    /// @param wrapperData Encoded chain of wrapper-specific data followed by addresses of next wrappers/settlement
    function wrappedSettle(
        bytes calldata settleData,
        bytes calldata wrapperData
    ) external;

    /// @notice Parses and validates wrapper-specific data
    /// @dev Used by CowWrapperHelpers to validate wrapper data before execution.
    ///      Implementations should consume their portion of wrapperData and return the rest.
    /// @param wrapperData The wrapper-specific data to parse
    /// @return remainingWrapperData Any wrapper data that was not consumed by this wrapper
    function parseWrapperData(bytes calldata wrapperData) external view returns (bytes calldata remainingWrapperData);
}

/// @title CoW Wrapper Base Contract
/// @notice Abstract base contract for creating wrapper contracts around CoW Protocol settlements
/// @dev A wrapper enables custom pre/post-settlement and context-setting logic and can be chained with other wrappers.
///      Wrappers must:
///      - Be approved by the GPv2Authentication contract
///      - Verify the caller is an authenticated solver
///      - Eventually call settle() on the approved GPv2Settlement contract
///      - Implement _wrap() for custom logic
///      - Implement parseWrapperData() for validation of implementation-specific wrapperData
abstract contract CowWrapper {
    /// @notice Thrown when the caller is not an authenticated solver
    /// @param unauthorized The address that attempted to call wrappedSettle
    error NotASolver(address unauthorized);

    /// @notice Thrown when wrapper data doesn't contain a settlement target address
    /// @param wrapperDataLength The actual length of wrapper data provided
    /// @param requiredWrapperDataLength The minimum required length (20 bytes for an address)
    error WrapperHasNoSettleTarget(uint256 wrapperDataLength, uint256 requiredWrapperDataLength);

    /// @notice Thrown when settle data doesn't contain the correct function selector
    /// @param invalidSettleData The invalid settle data that was provided
    error InvalidSettleData(bytes invalidSettleData);

    /// @notice The authentication contract used to verify solvers
    /// @dev This is typically the GPv2AllowListAuthentication contract
    GPv2Authentication public immutable AUTHENTICATOR;

    /// @notice Constructs a new CowWrapper
    /// @param authenticator_ The GPv2Authentication contract to use for solver or upstream wrapper verification
    constructor(GPv2Authentication authenticator_) {
        AUTHENTICATOR = authenticator_;
    }

    /// @notice Initiates a wrapped settlement call
    /// @dev Entry point for solvers to execute wrapped settlements. Verifies the caller is a solver,
    ///      validates wrapper data, then delegates to _wrap() for custom logic.
    /// @param settleData ABI-encoded call to CowSettlement.settle() containing trade data
    /// @param wrapperData Encoded data for this wrapper and the chain of next wrappers/settlement.
    ///                    Format: [wrapper-specific-data][next-address][remaining-wrapper-data]
    ///                    Must be at least 20 bytes to contain the next settlement target address.
    function wrappedSettle(
        bytes calldata settleData,
        bytes calldata wrapperData
    ) external {
        // Revert if not a valid solver
        if (!AUTHENTICATOR.isSolver(msg.sender)) {
            revert NotASolver(msg.sender);
        }

        // Require wrapper data to contain at least the next settlement address (20 bytes)
        if (wrapperData.length < 20) {
            revert WrapperHasNoSettleTarget(wrapperData.length, 20);
        }

        // Delegate to the wrapper's custom logic
        _wrap(settleData, wrapperData);
    }

    /// @notice Parses and validates wrapper-specific data
    /// @dev Must be implemented by concrete wrapper contracts. Used for pre-execution validation.
    ///      The implementation should consume its wrapper-specific data and return the remainder.
    /// @param wrapperData The full wrapper data to parse
    /// @return remainingWrapperData The portion of wrapper data not consumed by this wrapper
    function parseWrapperData(bytes calldata wrapperData) external virtual view returns (bytes calldata remainingWrapperData);

    /// @notice Internal function containing the wrapper's custom logic
    /// @dev Must be implemented by concrete wrapper contracts. Should execute custom logic
    ///      then eventually call _internalSettle() to continue the settlement chain.
    /// @param settleData ABI-encoded call to CowSettlement.settle()
    /// @param wrapperData The wrapper data, which may be parsed and consumed as needed
    function _wrap(bytes calldata settleData, bytes calldata wrapperData) internal virtual;

    /// @notice Continues the settlement chain by calling the next wrapper or settlement contract
    /// @dev Extracts the next target address from wrapperData and either:
    ///      - Calls CowSettlement.settle() directly if no more wrappers remain, or
    ///      - Calls the next CowWrapper.wrappedSettle() to continue the chain
    /// @param settleData ABI-encoded call to CowSettlement.settle()
    /// @param wrapperData Remaining wrapper data starting with the next target address (20 bytes)
    function _internalSettle(bytes calldata settleData, bytes calldata wrapperData) internal {
        // Extract the next settlement address from the first 20 bytes of wrapperData
        // Assembly is used to efficiently read the address from calldata
        address nextSettlement;
        assembly {
            // Load 32 bytes starting 12 bytes before wrapperData offset to get the address
            // (addresses are 20 bytes, right-padded in 32-byte words)
            nextSettlement := calldataload(sub(wrapperData.offset, 12))
        }

        // Skip past the address we just read
        wrapperData = wrapperData[20:];

        if (wrapperData.length == 0) {
            // No more wrapper data - we're calling the final settlement contract
            // Verify the settle data has the correct function selector
            if (bytes4(settleData[:4]) != CowSettlement.settle.selector) {
                revert InvalidSettleData(settleData);
            }

            // Call the settlement contract directly with the settle data
            (bool success, bytes memory returnData) = nextSettlement.call(settleData);

            if (!success) {
                // Bubble up the revert reason from the settlement contract
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }
        else {
            // More wrapper data remains - call the next wrapper in the chain
            CowWrapper(nextSettlement).wrappedSettle(settleData, wrapperData);
        }
    }
}
