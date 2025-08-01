//SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// Externals
import {BaseHook} from "@openzeppelin/uniswap-hooks/base/BaseHook.sol";
import {CrossDomainSelfBridgeable} from "./CrossDomainSelfBridgeable.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @dev A hook that converts a fragmented one-chain pool into a cross-chain pool in the Superchain cluster,
/// taking advantage of the 1-block latency to achieve real-time cross-chain swaps.
///
/// This cross-chain pool is replicated and interoperable across all the chains where it is deployed.
/// Note that even tough this same code is deployed across all chains, there are two different
/// instances classes of the hook: the canonical (stateful) chain and the proxy (stateless) chains.
///
/// For capital efficiency, one chain holds all liquidity (canonical), while others act as
/// routing proxies that forward swaps to the canonical chain.
///
/// Requirements:
/// - Chains must be part of the Superchain cluster.
/// - Tokens must be ERC-7802 compliant for cross-chain bridging.
/// - Uses the SuperchainTokenBridge predeploy for trust-minimized bridging.
/// - Requires the same contract address on all chains for cross-domain authentication.
///
/// Limitations:
///
/// - Only exactInput swaps are supported since the input must be bridged prior to the swap.
///
/// - Altrough slippage protection is achievable, it's gas costs are high. Specifically,
///   a failed swap due to slippage would incur in the gas costs for bridging A->B, B swap fail, and B->A
///
/// - Cross-chain messages can fail to be relayed, which can be solved by using a reliable network of
///   cross-domain message relayers.
///
/// - Cross-chain messages can be relayed in the wrong order, which can be solved by implementing a
///   mechanism for asynchronous cross-chain messages such as
///   https://github.com/ethereum-optimism/interop-lib/blob/main/src/Promise.sol OR
///   by improving the SuperchainTokenBridge to allow to "bridge and execute", which would ensure
///   message execution atomicity and correct order.
///
/// - The SuperchainTokenBridge is limited such that bridges can only by initialized by the token holder,
///   therefore, the hook must hold the user token in order to bridge them. This applies in the
///   origin chain to start the swap and in the destination chain to return the output tokens.
///   The SuperchainTokenBridge could be imported to allow "sendERC20From", which would require the 
///   "ERC20Burneable" extension in order to give "burn allowance" to the bridge.
///
///
contract CrosschainPoolHook is BaseHook, CrossDomainSelfBridgeable {
    using SafeCast for *;

    /// @dev Thrown if the swap is an exactOutput swap
    error ExactOutputCrosschainSwapUnsupported();

    struct CrosschainSwapCallbackData {
        uint256 originChainId;
        PoolKey key;
        SwapParams params;
    }

    /// @dev The chain ID where this pool's canonical state lives
    uint256 public immutable CANONICAL_CHAIN_ID;

    /// @dev Whether this instance is the canonical (stateful) pool
    bool public immutable IS_CANONICAL;

    constructor(IPoolManager _poolManager, uint256 _canonicalChainId) BaseHook(_poolManager) {
        // validate the chain where the hook is being deployed is part of the superchain cluster
        _validateIsSuperchain();

        CANONICAL_CHAIN_ID = _canonicalChainId;
        IS_CANONICAL = block.chainid == _canonicalChainId;
    }

    /// @inheritdoc BaseHook
    function _beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96)
        internal
        override
        returns (bytes4)
    {
        // validate both tokens are ERC-7802 compliant using ERC-165
        _validateIsERC7802(Currency.unwrap(key.currency0));
        _validateIsERC7802(Currency.unwrap(key.currency1));

        return (this.beforeInitialize.selector);
    }

    /// @inheritdoc BaseHook
    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (IS_CANONICAL) {
            // Canonical chain: execute swap normally
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        } else {
            // Proxy chain: bridge tokens and forward swap to canonical chain
            _initCrosschainSwap(key, params);

            // Return delta that neutralizes the specified amount to 0, effectively avoiding the swap on the proxy chain.
            return (this.beforeSwap.selector, toBeforeSwapDelta(params.amountSpecified.toInt128(), 0), 0);
        }
    }

    /// @dev Initializes a cross-chain swap by bridging the input tokens to the canonical chain
    /// and sending a cross-chain message to resolve the swap.
    function _initCrosschainSwap(PoolKey calldata key, SwapParams calldata params) internal {
        // We are forced to pre-bridge the exact amount of input tokens, therefore only exactInput swaps are supported.
        if (params.amountSpecified >= 0) revert ExactOutputCrosschainSwapUnsupported();

        // determine the tokenIn
        Currency tokenIn = (params.zeroForOne) ? key.currency0 : key.currency1;

        // bridge the input tokens to the canonical chain instance of this hook
        // @TBD The hook must hold the tokens in order to be able to bridge them!
        _bridge(Currency.unwrap(tokenIn), address(this), params.amountSpecified.toUint256(), CANONICAL_CHAIN_ID);

        // send cross-chain message to resolve the swap
        // @TBD if this message gets resolved before the bridge message, the swap will fail.
        bytes memory message = abi.encodeCall(this.resolveCrosschainSwap, (key, params));
        messenger.sendMessage(CANONICAL_CHAIN_ID, address(this), message);
    }

    /// @dev Resolves a cross-chain swap by performing the swap on the canonical chain and
    /// returning the output tokens to the proxy chain.
    function resolveCrosschainSwap(PoolKey calldata key, SwapParams calldata params)
        external
        onlyCrossDomainMessenger
        onlyCrossDomainSelf
        returns (BalanceDelta delta)
    {
        uint256 originChainId = messenger.crossDomainMessageSource();
        delta = abi.decode(
            poolManager.unlock(abi.encode(CrosschainSwapCallbackData(originChainId, key, params))), (BalanceDelta)
        );
    }

    /// @dev Called by the PoolManager to resolve the cross-chain swap request.
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        CrosschainSwapCallbackData memory callbackData = abi.decode(data, (CrosschainSwapCallbackData));

        // perform the swap on the canonical chain
        BalanceDelta delta = poolManager.swap(callbackData.key, callbackData.params, "");

        // determine the tokenOut
        (Currency tokenOut, int128 amountOut) = (callbackData.params.zeroForOne)
            ? (callbackData.key.currency0, delta.amount0())
            : (callbackData.key.currency1, delta.amount1());

        // bridge the output tokens back to the origin chain
        // @TBD if we return `tokenOut` directly, we are loosing the slippage protection entirely.
        // @TBD we can return the tokens to this hook instance, but they should go to the user.
        _bridge(Currency.unwrap(tokenOut), address(this), amountOut.toUint256(), callbackData.originChainId);

        return abi.encode(delta);
    }

    // @inheritdoc BaseHook
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
