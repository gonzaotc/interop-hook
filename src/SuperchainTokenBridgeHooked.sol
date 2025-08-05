// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// External
import {Predeploys} from "@optimism/contracts-bedrock/src/libraries/Predeploys.sol";
import {ZeroAddress, Unauthorized} from "@optimism/contracts-bedrock/src/libraries/errors/CommonErrors.sol";
import {ISuperchainERC20} from "@optimism/contracts-bedrock/interfaces/L2/ISuperchainERC20.sol";
import {IERC7802, IERC165} from "@optimism/contracts-bedrock/interfaces/L2/IERC7802.sol";
import {IL2ToL2CrossDomainMessenger} from "@optimism/contracts-bedrock/interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import {SuperchainTokenBridge} from "@optimism/contracts-bedrock/src/L2/SuperchainTokenBridge.sol";

// Internal
import {BridgeHooksLib} from "./BridgeHooksLib.sol";
import {ISuperchainTokenBridgeHooks} from "./ISuperchainTokenBridgeHooks.sol";
import {ISuperchainTokenBridgeHooked} from "./ISuperchainTokenBridgeHooked.sol";

// @title SuperchainTokenBridgeHooked (Draft)
// @notice Extension of the SuperchainTokenBridge that allows to execute callbacks at predefined points
// of the bridging process lifecycle (defined as hooks).
//
// @dev This iteration enables developers to easily perform sincronously chained actions such as
// "bridge and then execute", "execute and then bridge", "execute, bridge, and then execute",
// that otherwise would need to be handled asynchonously by sending multiple cross-chain messages and 
// ensuring a correct order of relaying and execution.
//
// Note that "beforeRelayERC20" and "afterRelayERC20" seems to cover most of the use cases, but others may also be fit.
//
contract SuperchainTokenBridgeHooked is SuperchainTokenBridge, ISuperchainTokenBridgeHooked {
    using BridgeHooksLib for BridgeHooksLib.HooksData;

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
    ) external returns (bytes32 msgHash_) {
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
    /// @param _hooksData Hook data configuration. See {BridgeHooksLib.HooksData}.
    function relayERC20Hooked(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        BridgeHooksLib.HooksData calldata _hooksData
    ) external {
        if (msg.sender != MESSENGER) revert Unauthorized();

        (address crossDomainMessageSender, uint256 source) =
            IL2ToL2CrossDomainMessenger(MESSENGER).crossDomainMessageContext();

        if (crossDomainMessageSender != address(this)) revert InvalidCrossDomainSender();

        if (_hooksData.isHookEnabled(BridgeHooksLib.Hooks.BeforeRelayERC20)) {
            _to.call(
                abi.encodeCall(
                    ISuperchainTokenBridgeHooks.beforeRelayERC20,
                    (_token, _from, _to, _amount, _hooksData.beforeRelayERC20Data)
                )
            );
        }

        ISuperchainERC20(_token).crosschainMint(_to, _amount);

        emit RelayERC20(_token, _from, _to, _amount, source);

        if (_hooksData.isHookEnabled(BridgeHooksLib.Hooks.AfterRelayERC20)) {
            _to.call(
                abi.encodeCall(
                    ISuperchainTokenBridgeHooks.afterRelayERC20,
                    (_token, _from, _to, _amount, _hooksData.afterRelayERC20Data)
                )
            );
        }
    }
}
