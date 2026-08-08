// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

library ForkedRpc {
    function forkEthereumMainnetAtBlock(Vm vm, uint256 blockNumber) internal returns (uint256 forkId) {
        bool useSpecificBlock;
        try vm.envBool("USE_ARCHIVE_MAINNET_BLOCK") returns (bool flag) {
            useSpecificBlock = flag;
        } catch {}

        if (!useSpecificBlock) {
            blockNumber = 0;
        }

        string[3] memory urls;
        uint256 urlCount;

        try vm.envString("MAINNET_ARCHIVE_NODE_URL") returns (string memory url) {
            urls[urlCount++] = url;
        } catch {}

        urls[urlCount++] = "https://eth.llamarpc.com";
        urls[urlCount++] = "https://eth.merkle.io";

        for (uint256 i = 0; i < urlCount; ++i) {
            string memory candidate = urls[i];
            if (bytes(candidate).length == 0) continue;

            bool duplicate;
            for (uint256 j = 0; j < i; ++j) {
                if (keccak256(bytes(candidate)) == keccak256(bytes(urls[j]))) {
                    duplicate = true;
                    break;
                }
            }
            if (duplicate) continue;

            if (blockNumber == 0) {
                try vm.createSelectFork(candidate) returns (uint256 idLatest) {
                    return idLatest;
                } catch {
                    continue;
                }
            }

            try vm.createSelectFork(candidate, blockNumber) returns (uint256 id) {
                return id;
            } catch {
                try vm.createSelectFork(candidate) returns (uint256 idLatest) {
                    return idLatest;
                } catch {
                    continue;
                }
            }
        }

        revert("ForkedRpc: no available mainnet RPC");
    }
}
