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
    string private networksJson;

    DeployAllContracts private script;
    CowProtocolMock private cowProtocolMock;

    // Contracts deployed by the deployment script. If you add a new deployment,
    // remember to update the test `test_consistentNetworksJsonFile`!
    FlashLoanRouter private router;
    AaveBorrower private aaveBorrower;
    ERC3156Borrower private erc3156Borrower;

    function setUp() external {
        string memory projectRoot = vm.projectRoot();
        networksJson = vm.readFile(string.concat(projectRoot, "/networks.json"));

        script = new DeployAllContracts();
        cowProtocolMock =
            new CowProtocolMock(vm, address(Constants.SETTLEMENT_CONTRACT), address(Constants.SOLVER_AUTHENTICATOR));

        (router, aaveBorrower, erc3156Borrower) = script.deployAll();
    }

    function disabledtest_unchangedAddresses() external view {
        // We want to make sure we don't introduce changes that cause the
        // deterministic addresses of the contract to change.
        // In particular, the router address is specified in CIP 66. Changing
        // this address requires a CIP.
        // https://snapshot.box/#/s:cow.eth/proposal/0x6f3d88347bcc8de87ecded2442c090d8eb1d3ef99eca75a831ee220ff5705f00
        assertEq(address(router), 0x9da8B48441583a2b93e2eF8213aAD0EC0b392C69);

        assertEq(address(aaveBorrower), 0x7d9C4DeE56933151Bc5C909cfe09DEf0d315CB4A);
        assertEq(address(erc3156Borrower), 0x47d71b4B3336AB2729436186C216955F3C27cD04);
    }

    function disabledtest_consistentNetworksJsonFile() external view {
        assertDeploymentsMatchNetworksJson("FlashLoanRouter", address(router));
        assertDeploymentsMatchNetworksJson("AaveBorrower", address(aaveBorrower));
        assertDeploymentsMatchNetworksJson("ERC3156Borrower", address(erc3156Borrower));
    }

    function assertDeploymentsMatchNetworksJson(string memory contractName, address expected) private view {
        address[] memory addresses = deploymentAddressesFromNetworksJson(contractName);
        for (uint256 i = 0; i < addresses.length; i++) {
            vm.assertEq(addresses[i], expected);
        }
    }

    function deploymentAddressesFromNetworksJson(string memory contractName)
        private
        view
        returns (address[] memory addresses)
    {
        // The notation ".." matches all subnodes of a node, meaning in this
        // case each contract deployment for each chain.
        // https://book.getfoundry.sh/cheatcodes/parse-json?highlight=json#jsonpath-key
        // https://www.rfc-editor.org/rfc/rfc9535.html#section-2.5.2
        string memory addressesSelector = string.concat(".", contractName, "..address");
        bytes memory data = vm.parseJson(networksJson, addressesSelector);
        addresses = abi.decode(data, (address[]));
        // Sanity check.
        vm.assertNotEq(addresses.length, 0);
    }
}
