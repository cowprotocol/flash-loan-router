// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, console} from "forge-std/Test.sol";
import {IBorrower, ICowSettlement, IFlashLoanRouter} from "src/FlashLoanRouter.sol";

import {Constants} from "../script/libraries/Constants.sol";

import {AaveBorrower, DeployAAVEBorrower} from "../script/single-deployment/DeployAAVEBorrower.s.sol";
import {DeployFlashLoanRouter, FlashLoanRouter} from "../script/single-deployment/DeployFlashLoanRouter.s.sol";

import {CowProtocolMock} from "test/test-lib/CowProtocolMock.sol";

/// @title ContractDeploymentTest
/// @dev This contract is used for testing the deployment of the FlashLoanRouter and AaveBorrower contracts.
/// It ensures that the deployed contracts match the expected contract addresses
/// provided in the `networks.json` deployed contract addresses file.
contract ContractDeploymentTest is Test, DeployFlashLoanRouter, DeployAAVEBorrower {
    /// @dev A struct representing a single contract deployment.
    /// It includes the network's chain ID, the contract's address, and the transaction hash.
    /// @param chainId The chain ID where the contract is deployed.
    /// @param contractAddress The address of the deployed contract.
    /// @param transactionHash The transaction hash of the deployment.
    struct Deployment {
        address contractAddress;
        bytes32 transactionHash;
    }

    /// @dev Mock instance of FlashLoanRouter
    FlashLoanRouter private mockRouter;
    /// @dev Mock instance of CowProtocol
    CowProtocolMock private cowProtocolMock;

    /// @dev Settlement contract address to mock
    address constant mockSettlement = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    /// @dev Authenticator contract address to mock
    address constant mockAuthenticator = 0x2c4c28DDBdAc9C5E7055b4C863b72eA0149D8aFE;
    /// @dev Chain ids for official contact deployments
    uint256[] private CHAIN_IDS = [1, 100, 11155111, 42161, 8453];

    /// @dev Override function from DeployFlashLoanRouter and DeployAAVEBorrower to run deployments.
    function run() public override(DeployFlashLoanRouter, DeployAAVEBorrower) {}

    /// @dev Set up mock instances of the CowProtocol for testing.
    /// This function is called before each test function to initialize required state.
    function setUp() external {
        // Initialize the CowProtocolMock with deployed contract addresses
        cowProtocolMock = new CowProtocolMock(vm, mockSettlement, mockAuthenticator);
    }

    /// @dev Test function to verify that the deployed FlashLoanRouter and AaveBorrower contracts
    /// match the expected contract addresses as defined in the JSON configuration file.
    function test_flashloan_and_borrower_deployment() public {
        (uint256 flashLoanRouterChainId, uint256 aaveBorrowerChainId) = test_contract_addresses_are_the_same_across_chains();

        // Parse the network data from the JSON configuration file and
        // extract the deployment data for FlashLoanRouter and AaveBorrower
        Deployment memory flashloanRouterDeployment = _parseJsonData("FlashLoanRouter", flashLoanRouterChainId);
        Deployment memory aaveBorrowerDeployment = _parseJsonData("AaveBorrower", aaveBorrowerChainId);

        // Deploy the FlashLoanRouter and AaveBorrower contracts using
        // the deployment contracts
        FlashLoanRouter router = deployFlashLoanRouter();
        AaveBorrower aaveBorrower = deployAAVEBorrower(router);

        // Verify that the deployed contract addresses match the expected addresses
        assertEq(
            address(router),
            flashloanRouterDeployment.contractAddress,
            "Deployed FlashLoanRouter addresses should match"
        );
        assertEq(
            address(aaveBorrower),
            aaveBorrowerDeployment.contractAddress,
            "Deployed AaveBorrower addresses should match"
        );
    }

    function test_contract_addresses_are_the_same_across_chains() public returns(uint256, uint256) {
        (bool flashLoanRouterAddressAreTheSame, uint256 flashLoanRouterChainId) = _parseContractAddresses("FlashLoanRouter");
        (bool aaveBorrowerAddressAreTheSame, uint256 aaveBorrowerChainId) = _parseContractAddresses("AaveBorrower");

        assertTrue(flashLoanRouterAddressAreTheSame, "FlashLoanRouter contract address should all be the same");
        assertTrue(aaveBorrowerAddressAreTheSame, "AAVEBorrower contract address should all be the same");
        assertTrue(flashLoanRouterChainId != 0, "Invalid chain id returned for FlashLoanRouter");
        assertTrue(aaveBorrowerChainId !=  0, "Invalid chain id returned for AAVEBorrower");

        return (flashLoanRouterChainId, aaveBorrowerChainId);
    }

    /// @dev Test function to verify that the deployment with a different FlashLoanRouter
    /// causes the address equality checks to fail as it will alter the bytecode for
    /// AaveBorrower contract too
    function test_router_mismatch_changes_deployment() public {
        (uint256 flashLoanRouterChainId, uint256 aaveBorrowerChainId) = test_contract_addresses_are_the_same_across_chains();

        // Extract the deployment data for FlashLoanRouter and AaveBorrower
        Deployment memory flashloanRouterDeployment = _parseJsonData("FlashLoanRouter", flashLoanRouterChainId);
        Deployment memory aaveBorrowerDeployment = _parseJsonData("AaveBorrower", aaveBorrowerChainId);

        // Deploy the FlashLoanRouter and AaveBorrower contracts
        FlashLoanRouter router = new FlashLoanRouter(ICowSettlement(mockSettlement));
        AaveBorrower aaveBorrower = deployAAVEBorrower(router);

        // Verify that the deployed addresses should not match the expected addresses when
        // FlashLoanRouter mismatches
        assertNotEq(address(router), flashloanRouterDeployment.contractAddress, "FlashLoanRouter deployment should be different");
        assertNotEq(address(aaveBorrower), aaveBorrowerDeployment.contractAddress, "AaveBorrower deployment should be different");
    }

    /// @dev Internal function to read and parse the JSON configuration file, and decode it into
    /// the Deployment struct.
    /// @return deploymentData The parsed and decoded network data containing contract deployment details.
    function _parseJsonData(string memory contractName, uint256 chain)
        internal
        returns (Deployment memory deploymentData)
    {
        // Get the contents of the JSON file
        string memory json = getJsonFileContents();

        // Parse the JSON data into bytes
        bytes memory data = vm.parseJson(json, string.concat(".", contractName, ".", vm.toString(chain)));

        // Decode the JSON data into the deploymentData struct
        deploymentData = abi.decode(data, (Deployment));
    }

    function _parseContractAddresses(string memory contractName)
        internal
        returns (bool isSameAcrossAllChains, uint256 chosenChainId)
    {
        address firstAddress;

        // Get the contents of the JSON file
        string memory json = getJsonFileContents();

        for (uint256 i = 0; i < CHAIN_IDS.length; i++) {
            string memory jsonPath = string.concat(".", contractName, ".", vm.toString(CHAIN_IDS[i]));

            if (!vm.keyExists(json, jsonPath)) continue;

            bytes memory data = vm.parseJson(json, jsonPath);
            Deployment memory deploymentData = abi.decode(data, (Deployment));

            if (firstAddress == address(0)) {
                firstAddress = deploymentData.contractAddress;
                chosenChainId = CHAIN_IDS[i];
                isSameAcrossAllChains = true;
            } else if (deploymentData.contractAddress != firstAddress) {
                isSameAcrossAllChains = false;
                break;
            }
        }

        if (firstAddress == address(0)) {
            console.log("Skipping tests: No valid chain IDs found for", contractName);
            vm.skip(true);
        }
    }

    function getJsonFileContents() internal returns (string memory json) {
        // Get the root directory of the project
        string memory root = vm.projectRoot();
        // Construct the path to the networks.json file
        string memory path = string.concat(root, "/networks.json");

        // Check if the file exists and
        // skip the test execution if the file does not exist
        if (!vm.exists(path)) {
            console.log("Skipping test: networks.json file not found.");
            vm.skip(true);
        }

        // Read the contents of the JSON file
        json = vm.readFile(path);
    }
}
