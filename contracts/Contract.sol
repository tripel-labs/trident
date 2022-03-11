// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

contract Contract {
    function double(uint256 a) external pure returns (uint256) {
        unchecked {return a * 2;}
    }
}
