// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// @title BridgeHooksLib
/// @notice Library for working with the SuperchainTokenBridge hooks.
library BridgeHooksLib {
    // @TBD make this cleaner unsing bitwise operations
    // and make it able to use multiple hooks at once.
    enum Hooks {
        BeforeRelayERC20,
        AfterRelayERC20
    }

    struct HooksData {
        // The enabled hooks in the HookData.
        Hooks hooks;
        // Hook data for beforeRelayERC20.
        bytes beforeRelayERC20Data;
        // Hook data for afterRelayERC20.
        bytes afterRelayERC20Data;
    }

    function isHookEnabled(HooksData calldata _hooksData, Hooks _hook) internal pure returns (bool) {
        return _hooksData.hooks == _hook;
    }
}
