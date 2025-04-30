// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Constants} from "./Constants.sol";
import {FlashLoanRouter} from "src/FlashLoanRouter.sol";

library Asserts {
    function assertFlashLoanRouter(
        FlashLoanRouter flashLoanRouter
    ) internal pure {
        require(
            address(flashLoanRouter.settlementContract()) ==
                Constants.DEFAULT_SETTLEMENT_CONTRACT,
            "Settlement contract varies in flashLoanRouter"
        );
    }
}
