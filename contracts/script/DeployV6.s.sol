// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {AutoYieldModule} from "../src/AutoYieldModule.sol";
import {AutopilotFactory} from "../src/AutopilotFactory.sol";

/**
 * @title DeployV6
 * @notice Deploy v6 contracts with sweep functionality
 *
 * v6 Changes:
 * - AutoYieldModule: Added sweepDustAndCompound() function for dust token swaps
 * - AutopilotFactory: SELECTOR_SWEEP (0x8fd059b6) whitelisted in validator
 *
 * Usage:
 *   forge script script/DeployV6.s.sol:DeployV6 \
 *     --rpc-url https://mainnet.base.org \
 *     --broadcast \
 *     --verify
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY - Private key for deployment
 *   BASESCAN_API_KEY - For contract verification (optional)
 */
contract DeployV6 is Script {
    // ZeroDev infrastructure (unchanged)
    address constant KERNEL_FACTORY = 0x2577507b78c2008Ff367261CB6285d44ba5eF2E9;
    address constant ECDSA_VALIDATOR = 0x845ADb2C711129d4f3966735eD98a9F09fC4cE57;

    // Reuse existing AutomationValidator (unchanged from v3)
    address constant AUTOMATION_VALIDATOR = 0x47A6b2f3bD564F9DeA17AcF8AbE73890c546900b;

    // Default vault (Moonwell Flagship USDC)
    address constant DEFAULT_VAULT = 0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca;

    // Default automation key
    address constant DEFAULT_AUTOMATION_KEY = 0xD78F5099987389e33bD6Ec15FF3Ca4dBedD507f3;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address automationKey = vm.envOr("AUTOMATION_KEY", DEFAULT_AUTOMATION_KEY);

        console.log("=== Autopilot v6 Deployment (Sweep Functionality) ===");
        console.log("");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Automation Key:", automationKey);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new AutoYieldModule with sweep function
        console.log("1. Deploying AutoYieldModule v6...");
        AutoYieldModule module = new AutoYieldModule();
        console.log("   AutoYieldModule v6:", address(module));

        // 2. Deploy new AutopilotFactory with sweep selector whitelisted
        console.log("2. Deploying AutopilotFactory v6...");
        AutopilotFactory factory = new AutopilotFactory(
            KERNEL_FACTORY,
            ECDSA_VALIDATOR,
            address(module),
            AUTOMATION_VALIDATOR,
            DEFAULT_VAULT,
            automationKey
        );
        console.log("   AutopilotFactory v6:", address(factory));

        vm.stopBroadcast();

        console.log("");
        console.log("=== v6 Deployment Complete ===");
        console.log("");
        console.log("NEW ADDRESSES:");
        console.log("  AutoYieldModule v6:", address(module));
        console.log("  AutopilotFactory v6:", address(factory));
        console.log("  AutomationValidator:", AUTOMATION_VALIDATOR, "(reused from v3)");
        console.log("");
        console.log("COPY-PASTE FOR backend/src/bundler/constants.ts:");
        console.log("  FACTORY:", address(factory));
        console.log("  MODULE:", address(module));
        console.log("  VALIDATOR:", AUTOMATION_VALIDATOR);
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Update DEPLOYMENTS.md with v6 addresses");
        console.log("2. Update backend/src/bundler/constants.ts");
        console.log("3. Create test wallet via new factory");
        console.log("4. Send dust tokens (DEGEN, AERO) to test wallet");
        console.log("5. Test sweep via dashboard");
    }
}
