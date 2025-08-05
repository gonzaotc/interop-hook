// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BridgeHooksLib} from "./BridgeHooksLib.sol";

/// @title ISuperchainTokenBridgeHooked
/// @notice Interface for the SuperchainTokenBridgeHooked.
interface ISuperchainTokenBridgeHooked {
    /// @notice Send tokens to a target address on another chain and execute enabled hooks.
    /// @dev Tokens are burned on the source chain.
    /// @param _token    Token to send.
    /// @param _to       Address to send tokens to.
    /// @param _amount   Amount of tokens to send.
    /// @param _chainId  Chain ID of the destination chain.
    /// @param _hooksData Hook data configuration. See {BridgeHooksLib.HooksData}.
    /// @return msgHash_ Hash of the message sent.
    function sendERC20Hooked(
        address _token,
        address _to,
        uint256 _amount,
        uint256 _chainId,
        BridgeHooksLib.HooksData calldata _hooksData
    ) external returns (bytes32 msgHash_);

    /// @notice Relay tokens received from another chain and execute a hook.
    /// @dev Tokens are minted on the destination chain.
    /// @param _token   Token to relay.
    /// @param _from    Address of the msg.sender of sendERC20 on the source chain.
    /// @param _to      Address to relay tokens to.
    /// @param _amount  Amount of tokens to relay.
    /// @param _hooksData Hook data configuration. See {BridgeHooksLib.HooksData}.
    function relayERC20Hooked(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        BridgeHooksLib.HooksData calldata _hooksData
    ) external;
}
