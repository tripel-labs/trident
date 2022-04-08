// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import {PoolDeployer} from "../../abstract/PoolDeployer.sol";
import {SolidlyPool} from "./SolidlyPool.sol";
import {IMasterDeployer} from "../../interfaces/IMasterDeployer.sol";
import {ISolidlyPoolFactory} from "../../interfaces/ISolidlyPoolFactory.sol";

/// @notice Contract for deploying Trident Solidly Pool with configurations.
contract ConstantProductPoolFactory is ISolidlyPoolFactory, PoolDeployer {
    bytes32 public constant bytecodeHash = keccak256(type(SolidlyPool).creationCode);

    bytes private cachedDeployData;

    constructor(address _masterDeployer) PoolDeployer(_masterDeployer) {}

    function deployPool(bytes memory _deployData) external returns (address pool) {
        (address tokenA, address tokenB) = abi.decode(_deployData, (address, address));

        if (tokenA > tokenB) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        // Strips any extra data.
        _deployData = abi.encode(tokenA, tokenB);

        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;

        bytes32 salt = keccak256(_deployData);

        cachedDeployData = _deployData;

        pool = address(new SolidlyPool{salt: salt}());

        cachedDeployData = "";

        _registerPool(pool, tokens, salt);
    }

    // This called in the ConstantProductPool constructor.
    function getDeployData() external view override returns (bytes memory, IMasterDeployer) {
        return (cachedDeployData, IMasterDeployer(masterDeployer));
    }

    function calculatePoolAddress(address token0, address token1) external view returns (address) {
        bytes32 salt = keccak256(abi.encode(token0, token1));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash));
        return address(uint160(uint256(hash)));
    }
}
