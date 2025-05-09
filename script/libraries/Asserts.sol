// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Constants} from "./Constants.sol";
import {FlashLoanRouter} from "src/FlashLoanRouter.sol";

/// @title Asserts Library
/// @author CoW DAO developers
/// @notice A library defining assertion functions for smart contract deployments.
library Asserts {
    /// @notice Asserts that the settlement contract in the flashLoanRouter is the default settlement contract.
    /// @param flashLoanRouter The flashLoanRouter to assert.
    function usesDefaultSettlementContract(FlashLoanRouter flashLoanRouter) internal view {
        require(
            address(flashLoanRouter.settlementContract()) == Constants.DEFAULT_SETTLEMENT_CONTRACT,
            "Settlement contract varies in flashLoanRouter"
        );
    }
}
