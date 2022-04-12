// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "../../lib/ds-test/src/test.sol";
import "../pool/solidly/SolidlyPool.sol";
import "../pool/solidly/SolidlyPoolFactory.sol";
import {MasterDeployer} from "../deployer/MasterDeployer.sol";
import {WETH9} from "../mocks/WETH9mock.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {BentoBoxMock as BentoBox, IERC20 as BentoIERC20} from "../mocks/BentoBoxMock.sol";
import "hardhat/console.sol";

contract SolidlyPoolTest is DSTest {
    WETH9 public weth;
    BentoBox public bentoBox;
    MasterDeployer public masterDeployer;
    SolidlyPoolFactory public factory;
    ERC20Mock public token0;
    ERC20Mock public token1;
    SolidlyPool public pool;

    address johnDoe = 0x0000002aC830ED0bac7cce24b1f7a48AA853c30C;

    function setUp() public {
        weth = new WETH9();
        bentoBox = new BentoBox(BentoIERC20(address(weth)));
        masterDeployer = new MasterDeployer(15, address(this), address(bentoBox));
        factory = new SolidlyPoolFactory(address(masterDeployer));
        masterDeployer.addToWhitelist(address(factory));
        token0 = new ERC20Mock("", "", 1e19);
        token1 = new ERC20Mock("", "", 1e19);
        token0.transfer(address(bentoBox), 1e19);
        token1.transfer(address(bentoBox), 1e19);
        bentoBox.deposit(BentoIERC20(address(token0)), address(bentoBox), address(this), 1e19, 0);
        bentoBox.deposit(BentoIERC20(address(token1)), address(bentoBox), address(this), 1e19, 0);
        (token0, token1) = address(token0) < address(token1) ? (token0, token1) : (token1, token0);
        pool = SolidlyPool(masterDeployer.deployPool(address(factory), abi.encode(address(token0), address(token1))));
        _addLiquidity(1e18, 1e18, address(0));
    }

    function testExample() public {
        assertTrue(true);
    }

    function testInitialisation() public {
        assertTrue(pool.totalSupply() > 0);
        assertEq(pool.token0(), address(token0));
        assertEq(pool.token1(), address(token1));
    }

    function testAddEqualLiquidity() public {
        uint256 liquidity = _addLiquidity(1e18, 1e18, address(this));
        uint256 balance = pool.balanceOf(address(this));
        assertTrue(balance == liquidity);
        assertTrue(liquidity > 0);
    }

    function testSwap() public {
        uint256 inAmount = 5e13;
        uint256 outputFirst = inAmount - 5;
        uint256 outputSecond = inAmount - 48;
        assertEq(_swap(inAmount, true, johnDoe), outputFirst);
        assertEq(_swap(inAmount, true, johnDoe), outputSecond);
        assertEq(pool.reserve0(), 1e18 + inAmount * 2);
        assertEq(pool.reserve1(), 1e18 - (outputFirst + outputSecond));
    }

    function _swap(
        uint256 amountIn,
        bool zeroForOne,
        address to
    ) internal returns (uint256 out) {
        bentoBox.transfer(BentoIERC20(address(zeroForOne ? token0 : token1)), address(this), address(pool), amountIn);
        out = pool.swap(abi.encode(zeroForOne, to));
        // check balances match reserves
        if (to != address(pool)) {
            assertEq(pool.reserve0(), bentoBox.balanceOf(BentoIERC20(address(token0)), address(pool)));
            assertEq(pool.reserve1(), bentoBox.balanceOf(BentoIERC20(address(token1)), address(pool)));
        } else {
            assertEq(pool.reserve0() + (zeroForOne ? 0 : out), bentoBox.balanceOf(BentoIERC20(address(token0)), address(pool)));
            assertEq(pool.reserve1() + (zeroForOne ? out : 0), bentoBox.balanceOf(BentoIERC20(address(token1)), address(pool)));
        }
    }

    function _addLiquidity(
        uint256 amount0,
        uint256 amount1,
        address to
    ) internal returns (uint256) {
        bentoBox.transfer(BentoIERC20(address(token0)), address(this), address(pool), amount0);
        bentoBox.transfer(BentoIERC20(address(token1)), address(this), address(pool), amount1);
        return pool.mint(abi.encode(to));
    }
}
