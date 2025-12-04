/**
 * Generate Global Session Key for AutoYield Automation
 *
 * This script generates a keypair used by the backend to sign automation
 * UserOperations (rebalance, migrateStrategy, sweepDustAndCompound).
 *
 * The session key has restricted permissions - it can only call specific
 * yield management functions and CANNOT transfer funds or change settings.
 *
 * Usage: npm run generate-session-key
 *
 * After running:
 * 1. Add AUTOMATION_PRIVATE_KEY and AUTOMATION_PUBLIC_ADDRESS to backend/.env
 * 2. Share AUTOMATION_PUBLIC_ADDRESS with Jackson to hardcode in AutopilotFactory.sol
 * 3. NEVER commit the private key to version control
 *
 * @see TEAM-TASKS.md - Bryce Task 1
 * @see hackathon-prd.md - Section 4.2 (Dual-Key Validation Model)
 */

import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import * as fs from "fs";
import * as path from "path";

// ANSI color codes for terminal output
const colors = {
  reset: "\x1b[0m",
  bright: "\x1b[1m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
  cyan: "\x1b[36m",
};

function log(color: string, message: string): void {
  console.log(`${color}${message}${colors.reset}`);
}

function checkExistingEnvVars(): { privateKeySet: boolean; publicAddressSet: boolean } {
  return {
    privateKeySet: !!process.env.AUTOMATION_PRIVATE_KEY,
    publicAddressSet: !!process.env.AUTOMATION_PUBLIC_ADDRESS,
  };
}

function checkExistingEnvFile(): { exists: boolean; hasAutomationKey: boolean } {
  const envPath = path.join(__dirname, "..", ".env");

  if (!fs.existsSync(envPath)) {
    return { exists: false, hasAutomationKey: false };
  }

  const content = fs.readFileSync(envPath, "utf-8");
  const hasAutomationKey =
    content.includes("AUTOMATION_PRIVATE_KEY") ||
    content.includes("AUTOMATION_PUBLIC_ADDRESS");

  return { exists: true, hasAutomationKey };
}

function main(): void {
  console.log("");
  log(colors.bright + colors.cyan, "╔═══════════════════════════════════════════════════════════════╗");
  log(colors.bright + colors.cyan, "║       AutoYield Session Key Generator                          ║");
  log(colors.bright + colors.cyan, "╚═══════════════════════════════════════════════════════════════╝");
  console.log("");

  // Safety checks
  const envVars = checkExistingEnvVars();
  const envFile = checkExistingEnvFile();

  if (envVars.privateKeySet || envVars.publicAddressSet) {
    log(colors.yellow, "⚠️  WARNING: Automation key environment variables are already set!");
    log(colors.yellow, "   AUTOMATION_PRIVATE_KEY: " + (envVars.privateKeySet ? "SET" : "not set"));
    log(colors.yellow, "   AUTOMATION_PUBLIC_ADDRESS: " + (envVars.publicAddressSet ? "SET" : "not set"));
    console.log("");
    log(colors.yellow, "   If you want to generate a NEW key, first remove these from your .env file.");
    log(colors.yellow, "   Continuing will display a new key, but it will NOT overwrite existing values.");
    console.log("");
  }

  if (envFile.hasAutomationKey) {
    log(colors.yellow, "⚠️  WARNING: Found existing automation key entries in .env file!");
    log(colors.yellow, "   Remove existing AUTOMATION_* entries before adding new ones.");
    console.log("");
  }

  // Generate new keypair
  log(colors.blue, "🔑 Generating new session keypair...");
  console.log("");

  const privateKey = generatePrivateKey();
  const account = privateKeyToAccount(privateKey);

  // Display results
  log(colors.green, "╔═══════════════════════════════════════════════════════════════╗");
  log(colors.green, "║                    SESSION KEY GENERATED                       ║");
  log(colors.green, "╚═══════════════════════════════════════════════════════════════╝");
  console.log("");

  log(colors.bright, "Add the following to backend/.env:");
  console.log("");
  console.log(`AUTOMATION_PRIVATE_KEY=${privateKey}`);
  console.log(`AUTOMATION_PUBLIC_ADDRESS=${account.address}`);
  console.log("");

  log(colors.cyan, "─────────────────────────────────────────────────────────────────");
  console.log("");

  log(colors.bright, "Send this public address to Jackson for AutopilotFactory.sol:");
  console.log("");
  log(colors.green, `  AUTOMATION_PUBLIC_ADDRESS=${account.address}`);
  console.log("");

  log(colors.cyan, "─────────────────────────────────────────────────────────────────");
  console.log("");

  // Security reminders
  log(colors.red, "🔒 SECURITY REMINDERS:");
  console.log("");
  log(colors.yellow, "   1. NEVER commit the private key to version control");
  log(colors.yellow, "   2. Add 'backend/.env' to .gitignore (if not already)");
  log(colors.yellow, "   3. Store the private key securely - losing it requires");
  log(colors.yellow, "      deploying new wallet contracts with a new session key");
  console.log("");

  log(colors.bright, "📋 Session Key Permissions (enforced on-chain):");
  console.log("");
  console.log("   ✓ rebalance()           - Move excess checking balance into yield");
  console.log("   ✓ migrateStrategy()     - Move funds between whitelisted vaults");
  console.log("   ✓ sweepDustAndCompound() - Consolidate dust tokens into yield");
  console.log("");
  console.log("   ✗ transfer()            - CANNOT transfer funds externally");
  console.log("   ✗ executeWithAutoYield()- CANNOT initiate user spends");
  console.log("   ✗ setCheckingThreshold()- CANNOT change user config");
  console.log("");

  log(colors.green, "✅ Session key generation complete!");
  console.log("");
}

main();
