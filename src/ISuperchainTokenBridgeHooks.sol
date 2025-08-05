// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title ISuperchainTokenBridgeHooks
/// @notice Interface for the SuperchainTokenBridge hooks.
interface ISuperchainTokenBridgeHooks {
    /// @notice Called before the ERC20 is relayed.
    /// @param _token The token that is being relayed.
    /// @param _from The address of the sender.
    /// @param _to The address of the recipient.
    /// @param _amount The amount of tokens being relayed.
    /// @param _hookData The data to pass to the hook.
    function beforeRelayERC20(address _token, address _from, address _to, uint256 _amount, bytes calldata _hookData)
        external;

    /// @notice Called after the ERC20 is relayed.
    /// @param _token The token that is being relayed.
    /// @param _from The address of the sender.
    /// @param _to The address of the recipient.
    /// @param _amount The amount of tokens being relayed.
    /// @param _hookData The data to pass to the hook.
    function afterRelayERC20(address _token, address _from, address _to, uint256 _amount, bytes calldata _hookData)
        external;
}