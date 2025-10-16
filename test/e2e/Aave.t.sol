// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {AaveCollateralSwapWrapper, IAavePool} from "src/AaveCollateralSwapWrapper.sol";
import {CowSettlement} from "src/vendored/CowWrapper.sol";
import {ISignatureTransfer} from "src/vendored/ISignatureTransfer.sol";

import {Constants} from "./lib/Constants.sol";
import {CowProtocol} from "./lib/CowProtocol.sol";
import {ForkedRpc} from "./lib/ForkedRpc.sol";
import {PermitHash} from "./lib/PermitHash.sol";
import {TokenBalanceAccumulator} from "./lib/TokenBalanceAccumulator.sol";

library AaveSetup {
    // The pool address is retrieved from the Aave aToken address corresponding
    // to the desired collateral through the POOL() function. The token address
    // can retrieved from the web interface:
    // https://app.aave.com/reserve-overview/?underlyingAsset=0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2&marketName=proto_mainnet_v3
    IAavePool internal constant WETH_POOL = IAavePool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    function prepareBorrower() internal returns (AaveCollateralSwapWrapper borrower) {
        borrower = new AaveCollateralSwapWrapper(WETH_POOL, Constants.SOLVER_AUTHENTICATOR);
    }
}

/// @dev Documentation for the ERC-3156-compatible flash loans by Maker can be
/// found at:
/// <https://docs.makerdao.com/smart-contract-modules/flash-mint-module>
contract E2eAave is Test {
    using ForkedRpc for Vm;

    // This is the block immediately before a mainnet fee withdrawal:
    // <https://etherscan.io/tx/0x2ac75cbf67d74ae3ad736314acb9dba170922849d411cc7ccbe81e4e0cff157e>
    // It guarantees that there are some WETH available in the buffers to pay
    // for the flash loan.
    uint256 private constant MAINNET_FORK_BLOCK = 21883877;
    address private solver = makeAddr("E2eAaveV2: solver");

    AaveCollateralSwapWrapper private borrower;
    TokenBalanceAccumulator private tokenBalanceAccumulator;

    function setUp() external {
        vm.forkEthereumMainnetAtBlock(MAINNET_FORK_BLOCK);
        tokenBalanceAccumulator = new TokenBalanceAccumulator();
        borrower = AaveSetup.prepareBorrower();
        CowProtocol.addSolver(vm, solver);
        CowProtocol.addSolver(vm, address(borrower));
    }

    function test_settleWithFlashLoan() external {
        // Create a user who will swap DAI for WETH collateral
        uint256 userPrivateKey = 0xBEEF;
        address user = vm.addr(userPrivateKey);

        uint256 amountIn = 1000 ether; // 1000 DAI to swap
        uint256 loanedAmount = 500 ether; // 500 WETH

        // Fund the user with DAI and approve Permit2
        deal(address(Constants.DAI), user, amountIn);
        vm.prank(user);
        Constants.DAI.approve(address(Constants.PERMIT), type(uint256).max);

        uint256 relativeFlashFee = AaveSetup.WETH_POOL.FLASHLOAN_PREMIUM_TOTAL();
        assertGt(relativeFlashFee, 0);
        uint256 absoluteFlashFee = loanedAmount * relativeFlashFee / 1000;

        uint256 settlementInitialWethBalance = Constants.WETH.balanceOf(address(Constants.SETTLEMENT_CONTRACT));
        assertGt(settlementInitialWethBalance, absoluteFlashFee);

        // Create CollateralSwapOperation
        AaveCollateralSwapWrapper.CollateralSwapOperation memory op = AaveCollateralSwapWrapper.CollateralSwapOperation({
            owner: user,
            deadline: block.timestamp + 1000,
            nonce: 0,
            swapFrom: address(Constants.DAI),
            swapTo: address(Constants.WETH),
            amountIn: amountIn,
            minAmountOut: loanedAmount
        });

        // Encode CollateralSwapOperation for wrapperData
        bytes memory encoded = abi.encode(op);

        // Hash the witness struct according to EIP-712
        // The witness hash must be: keccak256(abi.encode(TYPEHASH, ...fields...))
        bytes32 witnessHash = keccak256(
            abi.encode(
                keccak256(bytes(borrower.COLLATERAL_SWAP_WITNESS_TYPE())),
                op.owner,
                op.deadline,
                op.nonce,
                op.swapFrom,
                op.swapTo,
                op.amountIn,
                op.minAmountOut
            )
        );

        // Build the full witness type string for Permit2
        // Format: "WitnessType witness)WitnessType(...)TokenPermissions(...)"
        string memory witnessTypeString = string(abi.encodePacked(
            "CollateralSwapOperation witness)",
            borrower.COLLATERAL_SWAP_WITNESS_TYPE(),
            "TokenPermissions(address token,uint256 amount)"
        ));

        // Generate Permit2 signature
        bytes memory signature = _signPermitWitness(
            userPrivateKey,
            address(borrower), // spender
            address(Constants.DAI),
            amountIn,
            0, // nonce
            block.timestamp + 1000, // deadline
            witnessHash,
            witnessTypeString
        );

        bytes memory wrapperData = abi.encodePacked(
            encoded,
            abi.encode(signature),
            Constants.SETTLEMENT_CONTRACT
        );

        TokenBalanceAccumulator.Balance[] memory expectedBalances = new TokenBalanceAccumulator.Balance[](3);
        expectedBalances[2] = TokenBalanceAccumulator.Balance(
            Constants.WETH, address(Constants.SETTLEMENT_CONTRACT), settlementInitialWethBalance + loanedAmount
        );

        // add the token the settlement contract would need to return to the buffer
        deal(address(Constants.WETH), address(Constants.SETTLEMENT_CONTRACT), op.minAmountOut + absoluteFlashFee);

        vm.prank(solver);
        borrower.wrappedSettle(
            _encodeSettleWithSingleOrder(op.swapFrom, op.swapTo, op.amountIn, op.minAmountOut + absoluteFlashFee, address(borrower)),
            wrapperData
        );
    }

    // Helper function to generate Permit2 witness signature
    function _signPermitWitness(
        uint256 privateKey,
        address spender,
        address token,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes32 witness,
        string memory witnessTypeString
    ) internal view returns (bytes memory) {
        bytes32 msgHash;
        {
            ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: token,
                    amount: amount
                }),
                nonce: nonce,
                deadline: deadline
            });

            // Use PermitHash library to generate the correct hash
            bytes32 permitHash = PermitHash.hashWithWitness(permit, spender, witness, witnessTypeString);

            msgHash = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    Constants.PERMIT.DOMAIN_SEPARATOR(),
                    permitHash
                )
            );
        }

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return abi.encodePacked(r, s, v);
    }

    // Helper function to generate a settle with a single order
    function _encodeSettleWithSingleOrder(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        address receiver
    ) internal view returns (bytes memory) {
        // Create token array with sell and buy tokens
        address[] memory tokens = new address[](2);
        tokens[0] = sellToken;
        tokens[1] = buyToken;

        // Create clearing prices (not critical for this test, can be 1:1)
        uint256[] memory clearingPrices = new uint256[](2);
        clearingPrices[0] = buyAmount;
        clearingPrices[1] = sellAmount;

        // Create a single trade
        CowSettlement.CowTradeData[] memory trades = new CowSettlement.CowTradeData[](1);
        trades[0] = CowSettlement.CowTradeData({
            sellTokenIndex: 0, // Index of sellToken in tokens array
            buyTokenIndex: 1,  // Index of buyToken in tokens array
            receiver: receiver,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: 0xffffffff, // Max validity
            appData: bytes32(0),
            feeAmount: 0,
            flags: 1 << 6, // set the flag for EIP-1271
            executedAmount: sellAmount,
            signature: abi.encodePacked(address(borrower))
        });

        // No interactions
        CowSettlement.CowInteractionData[] memory noInteractions = new CowSettlement.CowInteractionData[](0);
        CowSettlement.CowInteractionData[][3] memory interactions = [noInteractions, noInteractions, noInteractions];

        return abi.encodeCall(CowSettlement.settle, (tokens, clearingPrices, trades, interactions));
    }
}
