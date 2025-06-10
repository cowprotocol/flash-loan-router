// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IERC20} from "./vendored/IERC20.sol";
import {SafeERC20} from "./vendored/SafeERC20.sol";

contract Repayer {
    using SafeERC20 for IERC20;

    function transfer(IERC20 token, address to, uint256 amount) external {
        token.transfer(to, amount);
    }
}
