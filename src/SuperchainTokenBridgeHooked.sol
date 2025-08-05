// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Libraries
import { Predeploys } from "@optimism/contracts-bedrock/src/libraries/Predeploys.sol";
import { ZeroAddress, Unauthorized } from "@optimism/contracts-bedrock/src/libraries/errors/CommonErrors.sol";

// Interfaces
import { ISuperchainERC20 } from "@optimism/contracts-bedrock/interfaces/L2/ISuperchainERC20.sol";
import { IERC7802, IERC165 } from "@optimism/contracts-bedrock/interfaces/L2/IERC7802.sol";
import { IL2ToL2CrossDomainMessenger } from "@optimism/contracts-bedrock/interfaces/L2/IL2ToL2CrossDomainMessenger.sol";

// Internal
import { BridgeHooks, ISuperchainTokenBridgeHooks } from "./BridgeHooksLib.sol";

// @
contract SuperchainTokenBridgeHooked is SuperchainTokenBridge {
    using BridgeHooks for BridgeHooks.HooksData;

    /// @notice Send tokens to a target address on another chain and execute a hook.
    /// @dev Tokens are burned on the source chain.
    /// @param _token    Token to send.
    /// @param _to       Address to send tokens to.
    /// @param _amount   Amount of tokens to send.
    /// @param _chainId  Chain ID of the destination chain.
    /// @param _hookData Data to pass to the hook.
    /// @return msgHash_ Hash of the message sent.
    function sendERC20Hooked(
        address _token,
        address _to,
        uint256 _amount,
        uint256 _chainId,
        BridgeHooks.HooksData calldata _hooksData
    )
        external
        returns (bytes32 msgHash_)
    {
        if (_to == address(0)) revert ZeroAddress();

        if (!IERC165(_token).supportsInterface(type(IERC7802).interfaceId)) revert InvalidERC7802();

        ISuperchainERC20(_token).crosschainBurn(msg.sender, _amount);

        bytes memory message = abi.encodeCall(this.relayERC20Hooked, (_token, msg.sender, _to, _amount, _hooksData));
        msgHash_ = IL2ToL2CrossDomainMessenger(MESSENGER).sendMessage(_chainId, address(this), message);

        emit SendERC20(_token, msg.sender, _to, _amount, _chainId);
    }

    /// @notice Relay tokens received from another chain and execute a hook.
    /// @dev Tokens are minted on the destination chain.
    /// @param _token   Token to relay.
    /// @param _from    Address of the msg.sender of sendERC20 on the source chain.
    /// @param _to      Address to relay tokens to.
    /// @param _amount  Amount of tokens to relay.
    /// @param _hooksData Data to pass to the hook.
    function relayERC20Hooked(address _token, address _from, address _to, uint256 _amount, BridgeHooks.HooksData calldata _hooksData) external {
        if (msg.sender != MESSENGER) revert Unauthorized();

        (address crossDomainMessageSender, uint256 source) =
            IL2ToL2CrossDomainMessenger(MESSENGER).crossDomainMessageContext();

        if (crossDomainMessageSender != address(this)) revert InvalidCrossDomainSender();

        if (_hooksData.isHookEnabled(Hooks.BeforeRelayERC20)) {
            _to.call(abi.encodeCall(ISuperchainTokenBridgeHooks.beforeRelayERC20,
                (_token, _from, _to, _amount, source, _hooksData.beforeRelayERC20Data)
            ));
        }

        ISuperchainERC20(_token).crosschainMint(_to, _amount);

        emit RelayERC20(_token, _from, _to, _amount, source);

        if (_hooksData.isHookEnabled(Hooks.AfterRelayERC20)) {
            _to.call(abi.encodeCall(ISuperchainTokenBridgeHooks.afterRelayERC20,
                (_token, _from, _to, _amount, source, _hooksData.afterRelayERC20Data)
            ));
        }
    }
}
