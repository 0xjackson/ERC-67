// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {AutoYieldModule} from "../src/AutoYieldModule.sol";
import {AutopilotFactory} from "../src/AutopilotFactory.sol";
import {AutomationValidator} from "../src/AutomationValidator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IKernel, ExecMode} from "../src/interfaces/IKernel.sol";
import {PackedUserOperation} from "../src/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title UserOpSimulationTest
 * @notice Tests the full ERC-4337 UserOp flow for sweep and other automation operations
 * @dev Run with: BASESCAN_API_KEY=dummy forge test --match-contract UserOpSimulationTest --fork-url https://mainnet.base.org -vvv
 */
contract UserOpSimulationTest is Test {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    // ============ Base Mainnet Addresses ============
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant KERNEL_FACTORY = 0x2577507b78c2008Ff367261CB6285d44ba5eF2E9;
    address constant ECDSA_VALIDATOR = 0x845ADb2C711129d4f3966735eD98a9F09fC4cE57;
    address constant ENTRYPOINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    address constant VAULT_MOONWELL = 0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca;
    address constant AERODROME_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address constant DEGEN = 0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed;
    address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    // ============ Selectors ============
    bytes4 constant SELECTOR_EXECUTE = 0xe9ae5c53;
    bytes4 constant SELECTOR_REBALANCE = 0x21c28191;
    bytes4 constant SELECTOR_MIGRATE = 0x6cb56d19;
    bytes4 constant SELECTOR_SWEEP = 0x8fd059b6;

    // ============ ExecMode ============
    ExecMode constant EXEC_MODE_DEFAULT = ExecMode.wrap(bytes32(0));

    // ============ State ============
    AutoYieldModule public module;
    AutopilotFactory public factory;
    AutomationValidator public validator;
    IEntryPoint public entryPoint;

    address public owner;
    uint256 public ownerPrivateKey;
    address public automationKey;
    uint256 public automationPrivateKey;
    address public wallet;
    address public beneficiary;

    // ============ Setup ============

    function setUp() public {
        if (block.chainid != 8453) {
            return;
        }

        entryPoint = IEntryPoint(ENTRYPOINT);
        beneficiary = makeAddr("beneficiary");

        // Use deterministic private keys for testing
        automationPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        automationKey = vm.addr(automationPrivateKey);

        ownerPrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        owner = vm.addr(ownerPrivateKey);

        // Deploy fresh contracts
        module = new AutoYieldModule();
        validator = new AutomationValidator();
        factory = new AutopilotFactory(
            KERNEL_FACTORY,
            ECDSA_VALIDATOR,
            address(module),
            address(validator),
            VAULT_MOONWELL,
            automationKey
        );

        // Create wallet
        wallet = factory.createAccountFor(owner, bytes32(uint256(1)));

        // Fund wallet with USDC and ETH for gas
        deal(USDC, wallet, 10_000e6);
        vm.deal(wallet, 1 ether);

        // Fund EntryPoint deposit for the wallet (needed for self-paying UserOps)
        vm.deal(address(this), 1 ether);
        entryPoint.depositTo{value: 0.5 ether}(wallet);
    }

    modifier onlyFork() {
        if (block.chainid != 8453) {
            console.log("SKIPPED: Not on Base mainnet (chainid:", block.chainid, ")");
            return;
        }
        _;
    }

    // ============ Validator Installation Tests ============

    function test_userOp_01_validatorInstalled() public onlyFork {
        assertTrue(validator.initialized(wallet), "Validator should be initialized");
        assertEq(validator.automationKey(wallet), automationKey, "Automation key should be set");
    }

    function test_userOp_02_sweepSelectorWhitelisted() public onlyFork {
        assertTrue(
            validator.allowedSelectors(wallet, address(module), SELECTOR_SWEEP),
            "Sweep selector should be whitelisted"
        );
    }

    function test_userOp_03_rebalanceSelectorWhitelisted() public onlyFork {
        assertTrue(
            validator.allowedSelectors(wallet, address(module), SELECTOR_REBALANCE),
            "Rebalance selector should be whitelisted"
        );
    }

    function test_userOp_04_migrateSelectorWhitelisted() public onlyFork {
        assertTrue(
            validator.allowedSelectors(wallet, address(module), SELECTOR_MIGRATE),
            "Migrate selector should be whitelisted"
        );
    }

    function test_userOp_05_unknownSelectorNotWhitelisted() public onlyFork {
        assertFalse(
            validator.allowedSelectors(wallet, address(module), bytes4(0xdeadbeef)),
            "Random selector should NOT be whitelisted"
        );
    }

    // ============ CallData Parsing Tests ============

    function test_userOp_06_callDataParsing_sweep() public onlyFork {
        address[] memory dustTokens = new address[](1);
        dustTokens[0] = DEGEN;

        bytes memory callData = _buildSweepCallData(dustTokens);

        // Verify the execute selector
        bytes4 executeSelector;
        assembly {
            executeSelector := mload(add(callData, 32))
        }
        assertEq(executeSelector, SELECTOR_EXECUTE, "Should have execute selector");

        // Verify target extraction at bytes 100:120
        // In Solidity, bytes memory has a 32-byte length prefix, so actual data starts at offset 32
        address extractedTarget;
        assembly {
            // Load 32 bytes starting at position 100 (+ 32 for length prefix)
            // Then shift right to get the address in the lower 20 bytes
            extractedTarget := shr(96, mload(add(add(callData, 32), 100)))
        }
        assertEq(extractedTarget, address(module), "Target should be module");

        // Verify inner selector extraction at bytes 152:156
        bytes4 extractedInnerSelector;
        assembly {
            extractedInnerSelector := mload(add(add(callData, 32), 152))
        }
        assertEq(extractedInnerSelector, SELECTOR_SWEEP, "Inner selector should be sweep");
    }

    function test_userOp_07_callDataParsing_rebalance() public onlyFork {
        bytes memory callData = _buildRebalanceCallData(USDC);

        // Verify the execute selector
        bytes4 executeSelector;
        assembly {
            executeSelector := mload(add(callData, 32))
        }
        assertEq(executeSelector, SELECTOR_EXECUTE, "Should have execute selector");

        // Verify target extraction at bytes 100:120
        address extractedTarget;
        assembly {
            extractedTarget := shr(96, mload(add(add(callData, 32), 100)))
        }
        assertEq(extractedTarget, address(module), "Target should be module");

        // Verify inner selector extraction at bytes 152:156
        bytes4 extractedInnerSelector;
        assembly {
            extractedInnerSelector := mload(add(add(callData, 32), 152))
        }
        assertEq(extractedInnerSelector, SELECTOR_REBALANCE, "Inner selector should be rebalance");
    }

    // ============ Validator validateUserOp Tests ============

    function test_userOp_08_validateUserOp_rebalance_succeeds() public onlyFork {
        bytes memory callData = _buildRebalanceCallData(USDC);
        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);

        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0, "Validation should succeed");
    }

    function test_userOp_09_validateUserOp_sweep_succeeds() public onlyFork {
        address[] memory dustTokens = new address[](1);
        dustTokens[0] = DEGEN;

        bytes memory callData = _buildSweepCallData(dustTokens);
        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);

        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 0, "Validation should succeed");
    }

    function test_userOp_10_validateUserOp_wrongSigner_fails() public onlyFork {
        bytes memory callData = _buildRebalanceCallData(USDC);
        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);

        bytes32 userOpHash = _getUserOpHash(userOp);

        // Sign with owner key instead of automation key
        userOp.signature = _signWithKey(userOpHash, ownerPrivateKey);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1, "Validation should fail with wrong signer");
    }

    function test_userOp_11_validateUserOp_wrongTarget_fails() public onlyFork {
        // Build callData targeting a different address
        bytes memory moduleCallData = abi.encodeWithSelector(SELECTOR_REBALANCE, USDC);
        bytes memory executionCalldata = abi.encodePacked(
            address(0xdeadbeef), // Wrong target
            uint256(0),
            moduleCallData
        );
        bytes memory callData = abi.encodeWithSelector(
            SELECTOR_EXECUTE,
            EXEC_MODE_DEFAULT,
            executionCalldata
        );

        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);
        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1, "Validation should fail with wrong target");
    }

    function test_userOp_12_validateUserOp_wrongSelector_fails() public onlyFork {
        // Build callData with non-whitelisted selector (e.g., setCheckingThreshold)
        bytes memory moduleCallData = abi.encodeWithSignature(
            "setCheckingThreshold(address,uint256)",
            USDC,
            1000e6
        );
        bytes memory executionCalldata = abi.encodePacked(
            address(module),
            uint256(0),
            moduleCallData
        );
        bytes memory callData = abi.encodeWithSelector(
            SELECTOR_EXECUTE,
            EXEC_MODE_DEFAULT,
            executionCalldata
        );

        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);
        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        uint256 result = validator.validateUserOp(userOp, userOpHash);
        assertEq(result, 1, "Validation should fail with non-whitelisted selector");
    }

    // ============ Full EntryPoint Flow Tests ============

    function test_userOp_13_entryPoint_rebalance() public onlyFork {
        uint256 checkingBefore = IERC20(USDC).balanceOf(wallet);
        assertGt(checkingBefore, 0, "Should have USDC");

        bytes memory callData = _buildRebalanceCallData(USDC);
        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);

        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Execute via EntryPoint
        entryPoint.handleOps(ops, payable(beneficiary));

        // Verify rebalance happened
        uint256 checkingAfter = IERC20(USDC).balanceOf(wallet);
        uint256 vaultShares = IERC4626(VAULT_MOONWELL).balanceOf(wallet);

        assertEq(checkingAfter, 0, "Checking should be at threshold (0)");
        assertGt(vaultShares, 0, "Should have vault shares");

        console.log("Rebalance via EntryPoint:");
        console.log("  Checking before:", checkingBefore / 1e6, "USDC");
        console.log("  Checking after:", checkingAfter / 1e6, "USDC");
        console.log("  Vault shares:", vaultShares);
    }

    function test_userOp_14_entryPoint_sweep_singleToken() public onlyFork {
        // First rebalance via UserOp to move USDC to yield
        {
            bytes memory rebalanceCallData = _buildRebalanceCallData(USDC);
            PackedUserOperation memory rebalanceOp = _buildUserOp(wallet, rebalanceCallData);
            bytes32 rebalanceHash = _getUserOpHash(rebalanceOp);
            rebalanceOp.signature = _signWithAutomationKey(rebalanceHash);

            PackedUserOperation[] memory ops = new PackedUserOperation[](1);
            ops[0] = rebalanceOp;
            entryPoint.handleOps(ops, payable(beneficiary));
        }

        uint256 sharesBefore = IERC4626(VAULT_MOONWELL).balanceOf(wallet);
        assertGt(sharesBefore, 0, "Should have shares after rebalance");

        // Give wallet some DEGEN
        deal(DEGEN, wallet, 1000e18);
        assertEq(IERC20(DEGEN).balanceOf(wallet), 1000e18, "Should have DEGEN");

        // Build and execute sweep UserOp
        address[] memory dustTokens = new address[](1);
        dustTokens[0] = DEGEN;

        bytes memory callData = _buildSweepCallData(dustTokens);
        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);

        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        entryPoint.handleOps(ops, payable(beneficiary));

        // Verify sweep happened
        uint256 degenAfter = IERC20(DEGEN).balanceOf(wallet);
        uint256 sharesAfter = IERC4626(VAULT_MOONWELL).balanceOf(wallet);

        assertEq(degenAfter, 0, "DEGEN should be swept");
        assertGt(sharesAfter, sharesBefore, "Should have more vault shares");

        console.log("Sweep via EntryPoint:");
        console.log("  DEGEN swept: 1000");
        console.log("  Shares before:", sharesBefore);
        console.log("  Shares after:", sharesAfter);
        console.log("  Shares gained:", sharesAfter - sharesBefore);
    }

    function test_userOp_15_entryPoint_sweep_multipleTokens() public onlyFork {
        // First rebalance via UserOp
        {
            bytes memory rebalanceCallData = _buildRebalanceCallData(USDC);
            PackedUserOperation memory rebalanceOp = _buildUserOp(wallet, rebalanceCallData);
            bytes32 rebalanceHash = _getUserOpHash(rebalanceOp);
            rebalanceOp.signature = _signWithAutomationKey(rebalanceHash);

            PackedUserOperation[] memory ops = new PackedUserOperation[](1);
            ops[0] = rebalanceOp;
            entryPoint.handleOps(ops, payable(beneficiary));
        }

        uint256 sharesBefore = IERC4626(VAULT_MOONWELL).balanceOf(wallet);

        // Give wallet multiple dust tokens
        deal(DEGEN, wallet, 500e18);
        deal(AERO, wallet, 10e18);

        // Build and execute sweep UserOp
        address[] memory dustTokens = new address[](2);
        dustTokens[0] = DEGEN;
        dustTokens[1] = AERO;

        bytes memory callData = _buildSweepCallData(dustTokens);
        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);

        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        entryPoint.handleOps(ops, payable(beneficiary));

        // Verify both tokens swept
        assertEq(IERC20(DEGEN).balanceOf(wallet), 0, "DEGEN should be swept");
        assertEq(IERC20(AERO).balanceOf(wallet), 0, "AERO should be swept");

        uint256 sharesAfter = IERC4626(VAULT_MOONWELL).balanceOf(wallet);
        assertGt(sharesAfter, sharesBefore, "Should have more vault shares");

        console.log("Multi-token sweep via EntryPoint:");
        console.log("  Shares before:", sharesBefore);
        console.log("  Shares after:", sharesAfter);
    }

    function test_userOp_16_entryPoint_migrate() public onlyFork {
        // First rebalance via UserOp to get shares in Moonwell
        {
            bytes memory rebalanceCallData = _buildRebalanceCallData(USDC);
            PackedUserOperation memory rebalanceOp = _buildUserOp(wallet, rebalanceCallData);
            bytes32 rebalanceHash = _getUserOpHash(rebalanceOp);
            rebalanceOp.signature = _signWithAutomationKey(rebalanceHash);

            PackedUserOperation[] memory ops = new PackedUserOperation[](1);
            ops[0] = rebalanceOp;
            entryPoint.handleOps(ops, payable(beneficiary));
        }

        uint256 moonwellSharesBefore = IERC4626(VAULT_MOONWELL).balanceOf(wallet);
        assertGt(moonwellSharesBefore, 0, "Should have Moonwell shares");

        // Migrate to a different vault (Steakhouse)
        address VAULT_STEAKHOUSE = 0xbeeF010f9cb27031ad51e3333f9aF9C6B1228183;

        bytes memory moduleCallData = abi.encodeWithSelector(SELECTOR_MIGRATE, USDC, VAULT_STEAKHOUSE);
        bytes memory executionCalldata = abi.encodePacked(address(module), uint256(0), moduleCallData);
        bytes memory callData = abi.encodeWithSelector(SELECTOR_EXECUTE, EXEC_MODE_DEFAULT, executionCalldata);

        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);
        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        entryPoint.handleOps(ops, payable(beneficiary));

        // Verify migration
        uint256 moonwellSharesAfter = IERC4626(VAULT_MOONWELL).balanceOf(wallet);
        uint256 steakhouseShares = IERC4626(VAULT_STEAKHOUSE).balanceOf(wallet);

        // Morpho vaults may leave dust shares due to rounding - allow up to ~$0.001 worth
        assertLt(moonwellSharesAfter, 1e12, "Moonwell shares should be near zero");
        assertGt(steakhouseShares, 0, "Should have Steakhouse shares");

        console.log("Migration via EntryPoint:");
        console.log("  Moonwell shares before:", moonwellSharesBefore);
        console.log("  Moonwell shares after:", moonwellSharesAfter);
        console.log("  Steakhouse shares:", steakhouseShares);
    }

    // ============ Gas Measurement Tests ============

    function test_userOp_17_gasEstimate_rebalance() public onlyFork {
        bytes memory callData = _buildRebalanceCallData(USDC);
        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);

        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        uint256 gasBefore = gasleft();
        entryPoint.handleOps(ops, payable(beneficiary));
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for rebalance:", gasUsed);
        assertLt(gasUsed, 1_500_000, "Rebalance should use less than 1.5M gas");
    }

    function test_userOp_18_gasEstimate_sweep_1token() public onlyFork {
        deal(DEGEN, wallet, 1000e18);

        address[] memory dustTokens = new address[](1);
        dustTokens[0] = DEGEN;

        bytes memory callData = _buildSweepCallData(dustTokens);
        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);

        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        uint256 gasBefore = gasleft();
        entryPoint.handleOps(ops, payable(beneficiary));
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for 1-token sweep:", gasUsed);
        assertLt(gasUsed, 1_000_000, "1-token sweep should use less than 1M gas");
    }

    function test_userOp_19_gasEstimate_sweep_3tokens() public onlyFork {
        deal(DEGEN, wallet, 1000e18);
        deal(AERO, wallet, 10e18);
        address WETH = 0x4200000000000000000000000000000000000006;
        deal(WETH, wallet, 0.01e18);

        address[] memory dustTokens = new address[](3);
        dustTokens[0] = DEGEN;
        dustTokens[1] = AERO;
        dustTokens[2] = WETH;

        bytes memory callData = _buildSweepCallData(dustTokens);
        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);

        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        uint256 gasBefore = gasleft();
        entryPoint.handleOps(ops, payable(beneficiary));
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for 3-token sweep:", gasUsed);
        assertLt(gasUsed, 2_000_000, "3-token sweep should use less than 2M gas");
    }

    // ============ Edge Case Tests ============

    function test_userOp_20_sweep_emptyArray() public onlyFork {
        address[] memory dustTokens = new address[](0);

        bytes memory callData = _buildSweepCallData(dustTokens);
        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);

        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Should not revert
        entryPoint.handleOps(ops, payable(beneficiary));
    }

    function test_userOp_21_sweep_zeroBalanceTokens() public onlyFork {
        // Don't deal any DEGEN - wallet has 0 balance
        address[] memory dustTokens = new address[](1);
        dustTokens[0] = DEGEN;

        bytes memory callData = _buildSweepCallData(dustTokens);
        PackedUserOperation memory userOp = _buildUserOp(wallet, callData);

        bytes32 userOpHash = _getUserOpHash(userOp);
        userOp.signature = _signWithAutomationKey(userOpHash);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        // Should not revert
        entryPoint.handleOps(ops, payable(beneficiary));
    }

    // ============ Helper Functions ============

    function _buildRebalanceCallData(address token) internal view returns (bytes memory) {
        bytes memory moduleCallData = abi.encodeWithSelector(SELECTOR_REBALANCE, token);
        bytes memory executionCalldata = abi.encodePacked(address(module), uint256(0), moduleCallData);
        return abi.encodeWithSelector(SELECTOR_EXECUTE, EXEC_MODE_DEFAULT, executionCalldata);
    }

    function _buildSweepCallData(address[] memory dustTokens) internal view returns (bytes memory) {
        bytes memory moduleCallData = abi.encodeWithSelector(
            SELECTOR_SWEEP,
            AERODROME_ROUTER,
            USDC,
            dustTokens
        );
        bytes memory executionCalldata = abi.encodePacked(address(module), uint256(0), moduleCallData);
        return abi.encodeWithSelector(SELECTOR_EXECUTE, EXEC_MODE_DEFAULT, executionCalldata);
    }

    function _buildUserOp(address sender, bytes memory callData) internal view returns (PackedUserOperation memory) {
        // Kernel v3 nonce format (32 bytes total):
        // - Byte 0: Mode (0x00 = default)
        // - Byte 1: Validation type (0x00 = ROOT, 0x01 = VALIDATOR, 0x02 = PERMISSION)
        // - Bytes 2-21: Validator address (20 bytes) - for non-root types
        // - Bytes 22-23: Nonce key (2 bytes)
        // - Bytes 24-31: Sequence (8 bytes)
        //
        // For secondary validators (type 0x01), we encode the validator address in the nonce.
        // The EntryPoint nonce key (192 bits) encodes: mode (8) + type (8) + validator (160) + key (16)

        // Build nonce key for AutomationValidator:
        // mode = 0x00, type = 0x01 (VALIDATOR), address = validator
        uint192 nonceKey = uint192(
            (uint256(0x00) << 184) |  // mode at position 184-191
            (uint256(0x01) << 176) |  // type at position 176-183 (VALIDATOR = 0x01)
            (uint256(uint160(address(validator))) << 16) |  // validator address at position 16-175
            uint256(0)  // key at position 0-15
        );
        uint256 nonce = entryPoint.getNonce(sender, nonceKey);

        // Pack gas limits: verificationGasLimit (16 bytes) | callGasLimit (16 bytes)
        uint128 verificationGasLimit = 500_000;
        uint128 callGasLimit = 1_500_000;
        bytes32 accountGasLimits = bytes32(uint256(verificationGasLimit) << 128 | uint256(callGasLimit));

        // Pack gas fees: maxPriorityFeePerGas (16 bytes) | maxFeePerGas (16 bytes)
        uint128 maxPriorityFeePerGas = 1 gwei;
        uint128 maxFeePerGas = 10 gwei;
        bytes32 gasFees = bytes32(uint256(maxPriorityFeePerGas) << 128 | uint256(maxFeePerGas));

        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: "",
            callData: callData,
            accountGasLimits: accountGasLimits,
            preVerificationGas: 100_000,
            gasFees: gasFees,
            paymasterAndData: "", // Self-paying
            signature: "" // Will be filled later
        });
    }

    function _getUserOpHash(PackedUserOperation memory userOp) internal view returns (bytes32) {
        // Use the EntryPoint's actual hash computation to ensure correctness
        // We create a calldata copy to call the EntryPoint
        return entryPoint.getUserOpHash(userOp);
    }

    function _signWithAutomationKey(bytes32 hash) internal view returns (bytes memory) {
        return _signWithKey(hash, automationPrivateKey);
    }

    function _signWithKey(bytes32 hash, uint256 privateKey) internal pure returns (bytes memory) {
        bytes32 ethSignedHash = hash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

}

// ============ EntryPoint Interface ============

interface IEntryPoint {
    function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external;
    function getNonce(address sender, uint192 key) external view returns (uint256);
    function depositTo(address account) external payable;
    function balanceOf(address account) external view returns (uint256);
    function getUserOpHash(PackedUserOperation calldata userOp) external view returns (bytes32);
}
