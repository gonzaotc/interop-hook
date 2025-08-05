//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// External
import {IL2ToL2CrossDomainMessenger} from "@optimism/contracts-bedrock/interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import {ISuperchainTokenBridge} from "@optimism/contracts-bedrock/interfaces/L2/ISuperchainTokenBridge.sol";
import {Predeploys} from "@optimism/contracts-bedrock/src/libraries/Predeploys.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrossDomainSelfBridgeable {
    IL2ToL2CrossDomainMessenger public immutable messenger =
        IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    // @dev Thrown if the caller is not the cross-domain messenger
    error OnlyCrossDomainMessenger();

    // @dev Thrown if the caller is not the cross-domain self
    error OnlyCrossDomainSelf();

    // @dev Thrown if the caller is not the SuperchainTokenBridge
    error OnlySuperchainTokenBridge();

    /// @dev Thrown if the chain is not part of the Superchain cluster
    error NotSuperchain();

    /// @dev Thrown if the token is not ERC-7802 compliant
    error InvalidERC7802();

    // @dev Thrown if the caller does not have sufficient allowance to perform the transferFrom prior to bridging
    error InsufficientAllowance();

    modifier onlyCrossDomainMessenger() {
        if (msg.sender != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER) revert OnlyCrossDomainMessenger();
        _;
    }

    modifier onlyCrossDomainSelf() {
        address sender = messenger.crossDomainMessageSender();
        if (sender != address(this)) revert OnlyCrossDomainSelf();
        _;
    }

    function _validateIsSuperchain() internal view {
        if (Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER.code.length == 0) revert NotSuperchain();
        if (Predeploys.SUPERCHAIN_TOKEN_BRIDGE.code.length == 0) revert NotSuperchain();
    }

    function _validateIsERC7802(address token) internal pure {
        // TODO: Implement ERC-7802 validation using ERC-165
        // For now, just ensure it's not zero address
        if (token == address(0)) {
            revert InvalidERC7802();
        }
    }

    // @dev Bridge tokens from this contract to the destination chain
    function _bridge(address token, address to, uint256 amount, uint256 chainId) internal {
        ISuperchainTokenBridge(Predeploys.SUPERCHAIN_TOKEN_BRIDGE).sendERC20(token, to, amount, chainId);
    }

    // @dev Take tokens from the user and bridge them to the destination chain
    function _takeAndBridge(address token, address to, uint256 amount, uint256 chainId) internal {
        if (IERC20(token).allowance(to, address(this)) < amount) revert InsufficientAllowance();
        IERC20(token).transferFrom(to, address(this), amount);
        _bridge(token, to, amount, chainId);
    }
}
