// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../../contracts/interfaces/ITridentCallee.sol";
import "../../contracts/interfaces/IBentoBoxMinimal.sol";

/// @notice Trident pool callback interface.
contract SymbolicTridentCallee is ITridentCallee {
    IBentoBoxMinimal public bento;
    address public token;
    address public from;
    address public recipient;
    uint256 public shares;

    function tridentSwapCallback(bytes calldata data) external override {
        // TODO: we would get a counter example that 'from' is ConstantProductPool, but we
        // know that ConstantProductPool wouldn't give access to any random TridentCallee

        // TODO: don't restrict recipient, but needs to be the currentContract (ConstantProductPool) (but needed)
        // (address token, address from, address recipient, uint256 shares) = abi.decode(data, (address, address, address, uint256));
        // TODO: have everything as a variable
        // TODO: --setting -t=600

        // address token;
        // address from;
        // address recipient;
        // uint256 shares;

        bento.transfer(token, from, recipient, shares);
    }

    // NOTE: not used in ConstantProductPool
    function tridentMintCallback(bytes calldata data) external override {}
}

// flashSwap:
// get the tokenOut first, do whatever you want, then submit the tokenIn.
