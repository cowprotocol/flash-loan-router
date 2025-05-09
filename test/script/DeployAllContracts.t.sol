// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {DeployAllContracts} from "script/DeployAllContracts.s.sol";
import {AaveBorrower} from "src/AaveBorrower.sol";
import {ERC3156Borrower} from "src/ERC3156Borrower.sol";
import {FlashLoanRouter} from "src/FlashLoanRouter.sol";

import {Constants} from "test/e2e/lib/Constants.sol";
import {CowProtocolMock} from "test/test-lib/CowProtocolMock.sol";

contract DeployAllContractsTest is Test {
    DeployAllContracts private script;
    CowProtocolMock private cowProtocolMock;

    function setUp() external {
        script = new DeployAllContracts();
        cowProtocolMock =
            new CowProtocolMock(vm, address(Constants.SETTLEMENT_CONTRACT), address(Constants.SOLVER_AUTHENTICATOR));
    }

    function test_deterministicDeployments() external {
        (FlashLoanRouter router, AaveBorrower aaveBorrower, ERC3156Borrower erc3156Borrower) = script.deployAll();

        // Only test with mainnet. We assume the addresses on the other chains
        // match the ones on mainnet.
        uint256 chainId = 1;
        assertEq(address(router), addressFromNetworksJson("FlashLoanRouter", chainId));
        assertEq(address(aaveBorrower), addressFromNetworksJson("AaveBorrower", chainId));
        assertEq(address(erc3156Borrower), addressFromNetworksJson("ERC3156Borrower", chainId));
    }

    function addressFromNetworksJson(string memory contractName, uint256 chain) private view returns (address) {
        string memory projectRoot = vm.projectRoot();
        string memory networksJson = vm.readFile(string.concat(projectRoot, "/networks.json"));

        string memory addressJsonKey = string.concat(".", contractName, ".", vm.toString(chain), ".address");
        bytes memory data = vm.parseJson(networksJson, addressJsonKey);
        return abi.decode(data, (address));
    }
}
