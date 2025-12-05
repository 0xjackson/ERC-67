// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IModule, IExecutorModule, MODULE_TYPE_EXECUTOR} from "./interfaces/IERC7579Module.sol";
import {IKernel, ExecMode} from "./interfaces/IKernel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//     ___         __              _ __      __
//    /   | __  __/ /_____  ____  (_) /___  / /_
//   / /| |/ / / / __/ __ \/ __ \/ / / __ \/ __/
//  / ___ / /_/ / /_/ /_/ / /_/ / / / /_/ / /_
// /_/  |_\__,_/\__/\____/ .___/_/_/\____/\__/
//                      /_/
//
// ERC-7579 executor module for automatic yield management
// https://github.com/autopilot-wallet

/**
 * @title AutoYieldModule
 * @author Autopilot
 * @notice Automatically manages yield allocation for smart wallet balances
 * @dev Interacts directly with ERC-4626 vaults for dynamic vault selection
 */
contract AutoYieldModule is IExecutorModule {
    using SafeERC20 for IERC20;

    ExecMode constant EXEC_MODE_DEFAULT = ExecMode.wrap(bytes32(0));

    error NotInitialized();
    error AlreadyInitialized();
    error InvalidVault();
    error VaultNotAllowed();
    error InsufficientBalance();
    error UnauthorizedCaller();
    error InvalidRouter();

    event Initialized(address indexed account, address indexed vault);
    event ThresholdUpdated(address indexed account, address indexed token, uint256 threshold);
    event VaultUpdated(address indexed account, address indexed token, address vault);
    event VaultAllowed(address indexed account, address indexed vault, bool allowed);
    event AutomationKeyUpdated(address indexed account, address indexed automationKey);
    event Deposited(address indexed account, address indexed token, uint256 amount);
    event Withdrawn(address indexed account, address indexed token, uint256 amount);
    event Rebalanced(address indexed account, address indexed token, uint256 deposited);
    event StrategyMigrated(address indexed account, address indexed token, address from, address to);
    event ExecutedWithAutoYield(address indexed account, address indexed to, uint256 value);
    event DustSwept(address indexed account, address indexed consolidationToken, uint256 tokensSwept, uint256 amountConsolidated);

    mapping(address account => bool) public isInitialized;
    mapping(address account => mapping(address token => uint256)) public checkingThreshold;
    mapping(address account => mapping(address token => address)) public currentVault;
    mapping(address account => mapping(address vault => bool)) public allowedVaults;
    mapping(address account => address) public automationKey;

    modifier onlyAuthorized(address account) {
        if (msg.sender != account && msg.sender != automationKey[account]) {
            revert UnauthorizedCaller();
        }
        _;
    }

    modifier onlyAccount(address account) {
        if (msg.sender != account) {
            revert UnauthorizedCaller();
        }
        _;
    }

    /**
     * @notice Called when module is installed on an account
     * @param data Encoded (defaultVault, automationKey, initialThreshold)
     */
    function onInstall(bytes calldata data) external override {
        address account = msg.sender;
        if (isInitialized[account]) revert AlreadyInitialized();

        (address defaultVault, address _automationKey, uint256 initialThreshold) =
            abi.decode(data, (address, address, uint256));

        if (defaultVault == address(0)) revert InvalidVault();

        isInitialized[account] = true;
        automationKey[account] = _automationKey;

        address asset = IERC4626(defaultVault).asset();
        allowedVaults[account][defaultVault] = true;
        currentVault[account][asset] = defaultVault;
        checkingThreshold[account][asset] = initialThreshold;

        emit Initialized(account, defaultVault);
        emit VaultAllowed(account, defaultVault, true);
        emit AutomationKeyUpdated(account, _automationKey);
    }

    /**
     * @notice Called when module is uninstalled from an account
     * @param data Unused
     */
    function onUninstall(bytes calldata data) external override {
        address account = msg.sender;
        isInitialized[account] = false;
        data;
    }

    /**
     * @notice Check if this module is of a certain type
     * @param moduleTypeId Module type ID to check
     * @return True if this is an executor module
     */
    function isModuleType(uint256 moduleTypeId) external pure override returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }

    /**
     * @notice Execute a call with automatic yield management
     * @param token Token being spent
     * @param to Target address for the call
     * @param value ETH value to send
     * @param data Calldata for the call
     */
    function executeWithAutoYield(
        address token,
        address to,
        uint256 value,
        bytes calldata data
    ) external {
        address account = msg.sender;
        if (!isInitialized[account]) revert NotInitialized();

        uint256 threshold = checkingThreshold[account][token];
        address vault = currentVault[account][token];

        uint256 checking = IERC20(token).balanceOf(account);
        uint256 amountNeeded = _extractTransferAmount(data, token);
        uint256 required = amountNeeded + threshold;

        if (checking < required && vault != address(0)) {
            uint256 deficit = required - checking;
            uint256 yieldBalance = _getYieldBalance(account, vault);

            if (yieldBalance > 0) {
                uint256 toWithdraw = deficit > yieldBalance ? yieldBalance : deficit;
                _withdrawFromYield(account, vault, toWithdraw);
                emit Withdrawn(account, token, toWithdraw);
            }
        }

        _executeOnKernel(account, to, value, data);

        uint256 newChecking = IERC20(token).balanceOf(account);
        if (newChecking > threshold && vault != address(0)) {
            uint256 surplus = newChecking - threshold;
            _depositToYield(account, vault, token, surplus);
            emit Deposited(account, token, surplus);
        }

        emit ExecutedWithAutoYield(account, to, value);
    }

    /**
     * @notice Rebalance funds between checking and yield
     * @param token Token to rebalance
     */
    function rebalance(address token) external onlyAuthorized(msg.sender) {
        address account = msg.sender;
        if (!isInitialized[account]) revert NotInitialized();

        uint256 threshold = checkingThreshold[account][token];
        address vault = currentVault[account][token];

        if (vault == address(0)) return;

        uint256 checking = IERC20(token).balanceOf(account);

        if (checking > threshold) {
            uint256 surplus = checking - threshold;
            _depositToYield(account, vault, token, surplus);
            emit Rebalanced(account, token, surplus);
        }
    }

    /**
     * @notice Migrate funds from current vault to a new one
     * @param token Token to migrate
     * @param newVault Address of the new vault
     */
    function migrateStrategy(
        address token,
        address newVault
    ) external onlyAuthorized(msg.sender) {
        address account = msg.sender;
        if (!isInitialized[account]) revert NotInitialized();

        address oldVault = currentVault[account][token];
        if (oldVault == newVault) return;

        if (oldVault != address(0)) {
            uint256 yieldBalance = _getYieldBalance(account, oldVault);
            if (yieldBalance > 0) {
                _withdrawFromYield(account, oldVault, yieldBalance);
            }
        }

        allowedVaults[account][newVault] = true;

        uint256 threshold = checkingThreshold[account][token];
        uint256 checking = IERC20(token).balanceOf(account);

        if (checking > threshold) {
            uint256 toDeposit = checking - threshold;
            _depositToYield(account, newVault, token, toDeposit);
        }

        currentVault[account][token] = newVault;

        emit StrategyMigrated(account, token, oldVault, newVault);
    }

    /**
     * @notice Withdraw all funds from yield to checking
     * @param token Token to flush
     */
    function flushToChecking(address token) external onlyAccount(msg.sender) {
        address account = msg.sender;
        address vault = currentVault[account][token];

        if (vault != address(0)) {
            uint256 yieldBalance = _getYieldBalance(account, vault);
            if (yieldBalance > 0) {
                _withdrawFromYield(account, vault, yieldBalance);
                emit Withdrawn(account, token, yieldBalance);
            }
        }
    }

    /**
     * @notice Set the checking threshold for a token
     * @param token Token address
     * @param threshold New threshold
     */
    function setCheckingThreshold(address token, uint256 threshold) external onlyAccount(msg.sender) {
        checkingThreshold[msg.sender][token] = threshold;
        emit ThresholdUpdated(msg.sender, token, threshold);
    }

    /**
     * @notice Set the current vault for a token
     * @param token Token address
     * @param vault Vault address
     */
    function setCurrentVault(address token, address vault) external onlyAccount(msg.sender) {
        if (vault != address(0) && !allowedVaults[msg.sender][vault]) {
            revert VaultNotAllowed();
        }
        currentVault[msg.sender][token] = vault;
        emit VaultUpdated(msg.sender, token, vault);
    }

    /**
     * @notice Add or remove a vault from the allowlist
     * @param vault Vault address
     * @param allowed Whether to allow or disallow
     */
    function setVaultAllowed(address vault, bool allowed) external onlyAccount(msg.sender) {
        allowedVaults[msg.sender][vault] = allowed;
        emit VaultAllowed(msg.sender, vault, allowed);
    }

    /**
     * @notice Set the automation key for background operations
     * @param key New automation key
     */
    function setAutomationKey(address key) external onlyAccount(msg.sender) {
        automationKey[msg.sender] = key;
        emit AutomationKeyUpdated(msg.sender, key);
    }

    /**
     * @notice Get total balance (checking + yield) for a token
     * @param account Account address
     * @param token Token address
     * @return Total balance
     */
    function getTotalBalance(address account, address token) external view returns (uint256) {
        uint256 checking = IERC20(token).balanceOf(account);
        address vault = currentVault[account][token];

        if (vault == address(0)) return checking;

        uint256 yield_ = _getYieldBalance(account, vault);
        return checking + yield_;
    }

    /**
     * @notice Get checking balance for a token
     * @param account Account address
     * @param token Token address
     * @return Checking balance
     */
    function getCheckingBalance(address account, address token) external view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }

    /**
     * @notice Get yield balance for a token
     * @param account Account address
     * @param token Token address
     * @return Yield balance
     */
    function getYieldBalance(address account, address token) external view returns (uint256) {
        address vault = currentVault[account][token];
        if (vault == address(0)) return 0;
        return _getYieldBalance(account, vault);
    }

    function _getYieldBalance(address account, address vault) internal view returns (uint256) {
        uint256 shares = IERC4626(vault).balanceOf(account);
        if (shares == 0) return 0;
        return IERC4626(vault).convertToAssets(shares);
    }

    function _depositToYield(
        address account,
        address vault,
        address token,
        uint256 amount
    ) internal {
        bytes memory approveData = abi.encodeCall(IERC20.approve, (vault, amount));
        _executeOnKernel(account, token, 0, approveData);

        bytes memory depositData = abi.encodeCall(IERC4626.deposit, (amount, account));
        _executeOnKernel(account, vault, 0, depositData);
    }

    function _withdrawFromYield(
        address account,
        address vault,
        uint256 amount
    ) internal {
        bytes memory withdrawData = abi.encodeCall(IERC4626.withdraw, (amount, account, account));
        _executeOnKernel(account, vault, 0, withdrawData);
    }

    function _executeOnKernel(
        address account,
        address target,
        uint256 value,
        bytes memory data
    ) internal {
        bytes memory executionCalldata = abi.encodePacked(target, value, data);
        IKernel(account).executeFromExecutor(EXEC_MODE_DEFAULT, executionCalldata);
    }

    function _extractTransferAmount(bytes calldata data, address token) internal pure returns (uint256) {
        if (data.length >= 68) {
            bytes4 selector = bytes4(data[:4]);
            if (selector == IERC20.transfer.selector) {
                return abi.decode(data[36:68], (uint256));
            }
        }
        token;
        return 0;
    }

    /// @dev Aerodrome Route struct for swap routing
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    /**
     * @notice Sweep dust tokens to consolidation token and deposit surplus to yield
     * @dev Backend determines which tokens are dust (< $1.10) and only calls when total >= $3
     * @param router DEX router address (e.g., Aerodrome)
     * @param consolidationToken Token to swap dust into (e.g., USDC)
     * @param dustTokens Array of dust token addresses to sweep
     */
    function sweepDustAndCompound(
        address router,
        address consolidationToken,
        address[] calldata dustTokens
    ) external onlyAuthorized(msg.sender) {
        address account = msg.sender;
        if (!isInitialized[account]) revert NotInitialized();
        if (router == address(0)) revert InvalidRouter();

        uint256 balanceBefore = IERC20(consolidationToken).balanceOf(account);
        uint256 swappedCount = 0;

        // Swap each dust token to consolidation token
        for (uint256 i = 0; i < dustTokens.length; i++) {
            address dustToken = dustTokens[i];
            if (dustToken == consolidationToken) continue;

            uint256 balance = IERC20(dustToken).balanceOf(account);
            if (balance == 0) continue;

            // Approve router
            bytes memory approveData = abi.encodeCall(IERC20.approve, (router, balance));
            _executeOnKernel(account, dustToken, 0, approveData);

            // Build Aerodrome Route array and swap
            Route[] memory routes = new Route[](1);
            routes[0] = Route(dustToken, consolidationToken, false, address(0));

            bytes memory swapData = abi.encodeWithSignature(
                "swapExactTokensForTokens(uint256,uint256,(address,address,bool,address)[],address,uint256)",
                balance,
                0, // Accept any amount out (slippage handled by backend decision to sweep)
                routes,
                account,
                block.timestamp + 300
            );
            _executeOnKernel(account, router, 0, swapData);
            swappedCount++;
        }

        uint256 balanceAfter = IERC20(consolidationToken).balanceOf(account);
        uint256 consolidated = balanceAfter - balanceBefore;

        // Deposit surplus to yield if vault is configured
        address vault = currentVault[account][consolidationToken];
        uint256 threshold = checkingThreshold[account][consolidationToken];

        if (vault != address(0) && balanceAfter > threshold) {
            uint256 surplus = balanceAfter - threshold;
            _depositToYield(account, vault, consolidationToken, surplus);
            emit Deposited(account, consolidationToken, surplus);
        }

        emit DustSwept(account, consolidationToken, swappedCount, consolidated);
    }
}
