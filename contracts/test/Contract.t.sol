// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "../../lib/ds-test/src/test.sol";
import "../Contract.sol";

contract ContractTest is DSTest {
    
    Contract testContract;

    function setUp() public {
        testContract = new Contract();
    }

    function testExample() public {
        assertTrue(true);
    }

    function testDouble(uint256 x) public {
        unchecked {
            uint256 expected = x * 2;
            assertEq(expected, testContract.double(x));
        }
    }
}
