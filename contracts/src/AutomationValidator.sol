// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IModule, MODULE_TYPE_VALIDATOR} from "./interfaces/IERC7579Module.sol";
import {PackedUserOperation} from "./interfaces/PackedUserOperation.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title AutomationValidator
 * @notice ERC-7579 validator module for automation key signatures
 * @dev Allows a designated automation key to sign UserOps for specific functions.
 *      This enables gasless background operations (rebalance, migrate) without
 *      requiring the owner's signature.
 *
 *      Security model:
 *      - Automation key can ONLY call whitelisted selectors on the AutoYieldModule
 *      - Owner retains full control via the root ECDSA validator
 *      - Automation key cannot transfer funds or change settings
 *
 *      Compatible with:
 *      - Kernel v3 (ERC-7579)
 *      - EntryPoint v0.7
 *      - Base bundler + paymaster
 *      - permissionless.js
 */
contract AutomationValidator is IModule {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ============ Constants ============

    /// @notice ERC-4337 validation success
    uint256 internal constant SIG_VALIDATION_SUCCESS = 0;

    /// @notice ERC-4337 validation failure
    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    /// @notice ERC-1271 magic value for valid signature
    bytes4 internal constant ERC1271_MAGICVALUE = 0x1626ba7e;

    /// @notice ERC-1271 invalid signature
    bytes4 internal constant ERC1271_INVALID = 0xffffffff;

    // ============ Errors ============

    error AlreadyInitialized();
    error NotInitialized();
    error InvalidAutomationKey();
    error SelectorNotAllowed();

    // ============ Events ============

    event AutomationKeySet(address indexed account, address indexed automationKey);
    event SelectorAllowed(address indexed account, address indexed target, bytes4 selector, bool allowed);

    // ============ Storage ============

    /// @notice Automation key per account
    mapping(address account => address) public automationKey;

    /// @notice Whether account has been initialized
    mapping(address account => bool) public initialized;

    /// @notice Allowed selectors per account: account => target => selector => allowed
    mapping(address account => mapping(address target => mapping(bytes4 selector => bool))) public allowedSelectors;

    // ============ ERC-7579 Module Interface ============

    /**
     * @notice Called when module is installed on an account
     * @param data Encoded (automationKey, autoYieldModule, allowedSelectors[])
     */
    function onInstall(bytes calldata data) external override {
        address account = msg.sender;
        if (initialized[account]) revert AlreadyInitialized();

        // Decode: (automationKey, autoYieldModule, selectors[])
        (
            address _automationKey,
            address autoYieldModule,
            bytes4[] memory selectors
        ) = abi.decode(data, (address, address, bytes4[]));

        if (_automationKey == address(0)) revert InvalidAutomationKey();

        // Set automation key
        automationKey[account] = _automationKey;
        initialized[account] = true;

        // Whitelist the allowed selectors on AutoYieldModule
        for (uint256 i = 0; i < selectors.length; i++) {
            allowedSelectors[account][autoYieldModule][selectors[i]] = true;
            emit SelectorAllowed(account, autoYieldModule, selectors[i], true);
        }

        emit AutomationKeySet(account, _automationKey);
    }

    /**
     * @notice Called when module is uninstalled from an account
     * @param data Unused
     */
    function onUninstall(bytes calldata data) external override {
        address account = msg.sender;
        delete automationKey[account];
        delete initialized[account];
        // Note: selector mappings are not cleared for gas efficiency
        // They become irrelevant once automationKey is deleted
        data; // silence warning
    }

    /**
     * @notice Check if this module is of a certain type
     * @param moduleTypeId Module type ID to check
     * @return True if this is a validator module
     */
    function isModuleType(uint256 moduleTypeId) external pure override returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    /**
     * @notice Check if module is initialized for an account
     * @param account Account to check
     * @return True if initialized
     */
    function isInitialized(address account) external view returns (bool) {
        return initialized[account];
    }

    // ============ Validator Interface ============

    /**
     * @notice Validate a UserOperation signature
     * @dev Called by Kernel during ERC-4337 validation phase.
     *      Checks:
     *      1. Signature is from the automation key
     *      2. Target function selector is whitelisted
     *
     * @param userOp The UserOperation to validate
     * @param userOpHash Hash of the UserOperation
     * @return 0 on success, 1 on failure
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external view returns (uint256) {
        address account = userOp.sender;

        // Check initialization
        if (!initialized[account]) {
            return SIG_VALIDATION_FAILED;
        }

        // Extract target and selector from callData
        // Kernel's execute format: execute(address to, uint256 value, bytes calldata data)
        // We need to check if this is calling an allowed function
        if (!_isAllowedCall(account, userOp.callData)) {
            return SIG_VALIDATION_FAILED;
        }

        // Verify signature is from automation key
        address key = automationKey[account];
        if (!_validateSignature(userOpHash, userOp.signature, key)) {
            return SIG_VALIDATION_FAILED;
        }

        return SIG_VALIDATION_SUCCESS;
    }

    /**
     * @notice Validate signature for ERC-1271
     * @param sender The account address
     * @param hash Hash that was signed
     * @param signature The signature
     * @return Magic value if valid, invalid value otherwise
     */
    function isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4) {
        if (!initialized[sender]) {
            return ERC1271_INVALID;
        }

        address key = automationKey[sender];
        if (_validateSignature(hash, signature, key)) {
            return ERC1271_MAGICVALUE;
        }
        return ERC1271_INVALID;
    }

    // ============ Internal Functions ============

    /**
     * @dev Validate ECDSA signature against expected signer
     */
    function _validateSignature(
        bytes32 hash,
        bytes calldata signature,
        address expectedSigner
    ) internal pure returns (bool) {
        // Try direct recovery
        address recovered = hash.recover(signature);
        if (recovered == expectedSigner) {
            return true;
        }

        // Try with EthSignedMessage prefix
        recovered = hash.toEthSignedMessageHash().recover(signature);
        return recovered == expectedSigner;
    }

    /**
     * @dev Check if the callData targets an allowed function
     *      Parses Kernel's execute(to, value, data) format
     */
    function _isAllowedCall(
        address account,
        bytes calldata callData
    ) internal view returns (bool) {
        // Minimum length: 4 (selector) + 32 (to) + 32 (value) + 32 (data offset) = 100 bytes
        if (callData.length < 100) {
            return false;
        }

        // Extract execute selector
        bytes4 executeSelector = bytes4(callData[:4]);

        // Check for Kernel.execute(address,uint256,bytes) selector: 0xb61d27f6
        if (executeSelector != bytes4(0xb61d27f6)) {
            return false;
        }

        // Decode target address (first param after selector)
        address target = address(uint160(uint256(bytes32(callData[4:36]))));

        // Decode the inner data (third param)
        // The data is dynamic, so we need to read the offset and then the data
        uint256 dataOffset = uint256(bytes32(callData[68:100]));

        // Data starts at 4 + dataOffset, first 32 bytes is length
        uint256 dataStart = 4 + dataOffset;
        if (callData.length < dataStart + 32) {
            return false;
        }

        uint256 dataLength = uint256(bytes32(callData[dataStart:dataStart + 32]));
        if (dataLength < 4) {
            return false; // No selector in inner data
        }

        // Extract inner selector
        bytes4 innerSelector = bytes4(callData[dataStart + 32:dataStart + 36]);

        // Check if this selector is allowed for this target
        return allowedSelectors[account][target][innerSelector];
    }
}
