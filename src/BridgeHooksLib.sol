// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// @title ISuperchainTokenBridgeHooks
/// @notice Interface for the SuperchainTokenBridge hooks.
interface ISuperchainTokenBridgeHooks {
    // @notice Called before the ERC20 is relayed.
    // @param _token The token that is being relayed.
    // @param _from The address of the sender.
    // @param _to The address of the recipient.
    // @param _amount The amount of tokens being relayed.
    // @param _source The source chain ID.
    // @param _hookData The data to pass to the hook.
    function beforeRelayERC20(address _token, address _from, address _to, uint256 _amount, uint256 _source, bytes calldata _hookData) external;

    // @notice Called after the ERC20 is relayed.
    // @param _token The token that is being relayed.
    // @param _from The address of the sender.
    // @param _to The address of the recipient.
    // @param _amount The amount of tokens being relayed.
    // @param _source The source chain ID.
    // @param _hookData The data to pass to the hook.
    function afterRelayERC20(address _token, address _from, address _to, uint256 _amount, uint256 _source, bytes calldata _hookData) external;
}

// @title BridgeHooks
/// @notice Library for working with the SuperchainTokenBridge hooks.
library BridgeHooks {
    type HooksBitmask is uint8;

    enum Hooks {
        BeforeRelayERC20,
        AfterRelayERC20
    }

    struct HooksData {
        // 00 => no hook
        // 01 => beforeRelayERC20
        // 10 => afterRelayERC20
        // 11 => beforeRelayERC20 and afterRelayERC20
        HooksBitmask hooks; 
        // hook data for beforeRelayERC20
        bytes beforeRelayERC20Data;
        // hook data for afterRelayERC20
        bytes afterRelayERC20Data;
    }

    function isHookEnabled(HooksData calldata _hooksData, Hooks _hook) internal pure returns (bool) {
        return (_hooksData.hooks & (1 << uint256(_hook))) != 0;
    }
}