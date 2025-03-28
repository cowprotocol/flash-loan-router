// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";
import {
    IBorrower,
    ICowSettlement,
    IFlashLoanRouter
} from "src/FlashLoanRouter.sol";

import {Constants} from "../script/libraries/Constants.sol";
import {DeployFlashLoanRouter, FlashLoanRouter} from "../script/single-deployment/DeployFlashLoanRouter.s.sol";
import {DeployAAVEBorrower, AaveBorrower} from "../script/single-deployment/DeployAAVEBorrower.s.sol";

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
        string chainId;           // The chain ID where the contract is deployed
        address contractAddress;  // The contract's address
        bytes32 transactionHash;  // The transaction hash of the deployment
    }

    
    /// @dev A struct holding the deployments of different contracts such as AaveBorrower
    /// and FlashLoanRouter. Each contract type has an array of deployments for different network configurations.
    /// @param AaveBorrower An array of AaveBorrower contract deployments.
    /// @param FlashLoanRouter An array of FlashLoanRouter contract deployments.
    struct NetworkData {
        Deployment[] AaveBorrower;       // Array of AaveBorrower contract deployments
        Deployment[] FlashLoanRouter;    // Array of FlashLoanRouter contract deployments
    }

    FlashLoanRouter private mockRouter;   // Mock instance of FlashLoanRouter
    CowProtocolMock private cowProtocolMock;   // Mock instance of CowProtocol

    address constant mockSettlement = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41; // Settlement contract address to mock
    address constant mockAuthenticator = 0x2c4c28DDBdAc9C5E7055b4C863b72eA0149D8aFE; // Authenticator contract address to mock

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
        // Parse the network data from the JSON configuration file
        NetworkData memory networkData = _parseJsonData();

        // Extract the deployment data for FlashLoanRouter and AaveBorrower
        Deployment memory flashloanRouterDeployment = networkData.FlashLoanRouter[0];
        Deployment memory aaveBorrowerDeployment = networkData.AaveBorrower[0];

        // Deploy the FlashLoanRouter and AaveBorrower contracts
        FlashLoanRouter router = deployFlashLoanRouter();
        AaveBorrower aaveBorrower = deployAAVEBorrower(router);

        // Verify that the deployed addresses match the expected addresses
        assertEq(address(router), flashloanRouterDeployment.contractAddress, "Deployed FlashLoanRouter addresses should match");
        assertEq(address(aaveBorrower), aaveBorrowerDeployment.contractAddress, "Deployed AaveBorrower addresses should match");
    }

    function test_flashloan_and_borrower_deployment_withDifferentRouter() public {
        // Parse the network data from the JSON configuration file
        NetworkData memory networkData = _parseJsonData();

        // Extract the deployment data for FlashLoanRouter and AaveBorrower
        Deployment memory flashloanRouterDeployment = networkData.FlashLoanRouter[0];
        Deployment memory aaveBorrowerDeployment = networkData.AaveBorrower[0];

        // Deploy the FlashLoanRouter and AaveBorrower contracts
        FlashLoanRouter router = new FlashLoanRouter(ICowSettlement(mockSettlement));
        AaveBorrower aaveBorrower = deployAAVEBorrower(router);

        // Verify that the deployed addresses match the expected addresses
        assertFalse(address(router) == flashloanRouterDeployment.contractAddress);
        assertFalse(address(aaveBorrower) == aaveBorrowerDeployment.contractAddress);
    }

    
    /// @dev Internal function to read and parse the JSON configuration file, and decode it into
    /// the NetworkData struct.
    /// @return networkData The parsed and decoded network data containing contract deployment details.
    function _parseJsonData() internal view returns (NetworkData memory networkData) {
        // Read the JSON file
        string memory root = vm.projectRoot();  // Get the root directory of the project
        string memory path = string.concat(root, "/networks.json");  // Construct the path to the networks.json file
        string memory json = vm.readFile(path);  // Read the contents of the JSON file

        // Parse the JSON data into bytes
        bytes memory data = vm.parseJson(json);  // Parse the JSON file content into bytes

        // Decode the JSON data into the NetworkData struct
        networkData = abi.decode(data, (NetworkData));
    }
}
