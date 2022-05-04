// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "../../lib/ds-test/src/test.sol";
import "../pool/solidly/SolidlyPool.sol";
import "../pool/solidly/SolidlyPoolFactory.sol";
import {MasterDeployer} from "../deployer/MasterDeployer.sol";
import {WETH9} from "../mocks/WETH9Mock.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {BentoBoxMock as BentoBox, IERC20 as BentoIERC20} from "../mocks/BentoBoxMock.sol";
import "hardhat/console.sol";

interface Vm {
    function prank(address) external;
}

contract SolidlyPoolTest is DSTest {
    WETH9 public weth;
    BentoBox public bentoBox;
    MasterDeployer public masterDeployer;
    SolidlyPoolFactory public factory;
    ERC20Mock public token0;
    ERC20Mock public token1;
    SolidlyPool public pool;

    address public recipient = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public barFeeTo = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 public barFee = 1667;
    uint256 public maxFee = 10000;

    function setUp() public {
        weth = new WETH9();
        bentoBox = new BentoBox(BentoIERC20(address(weth)));
        masterDeployer = new MasterDeployer(barFee, barFeeTo, address(bentoBox));
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

    function testBurn() public {
        (uint256 b0, uint256 b1) = _getBalances(address(this));
        _burnLiquidity(_addLiquidity(1e18, 1e18, address(this)), address(this), address(this));
        (uint256 a0, uint256 a1) = _getBalances(address(this));
        assertEq(b0, a0);
        assertEq(b1, a1);
    }

    function testSwap(bool zeroForOne) public {
        assertEq(_swap(100000000000000, zeroForOne, recipient), 99989999999949);
        assertEq(_swap(100000000000000, zeroForOne, recipient), 99989999999249);
    }

    function testMintFee(bool zeroForOne, bool mintFeeBetweenSwaps) public {
        (uint256 reserve0Before, uint256 reserve1Before) = pool.getReserves();
        uint256 totalSupplyOld = pool.totalSupply();

        _swap(_swap(1e18, zeroForOne, recipient), !zeroForOne, recipient); // buy and sell

        if (mintFeeBetweenSwaps) _invokeMintFee();

        _swap(_swap(1e18, !zeroForOne, recipient), zeroForOne, recipient); // sell and buy

        (uint256 reserve0After, uint256 reserve1After) = pool.getReserves();

        uint256 change0 = reserve0After - reserve0Before; // Pool profit after swaps.
        uint256 change1 = reserve1After - reserve1Before; // Pool profit after swaps.

        _invokeMintFee();

        uint256 totalSupply = pool.totalSupply();
        uint256 barFees = pool.balanceOf(barFeeTo);
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();

        assertEq(totalSupplyOld + barFees, totalSupply);

        uint256 fees0 = (reserve0 * barFees) / totalSupply;
        uint256 fees1 = (reserve1 * barFees) / totalSupply;

        uint256 estimated0 = (change0 * barFee) / 10000;
        uint256 estimated1 = (change1 * barFee) / 10000;

        _assertEqualWithError(fees0, estimated0, 10000);
        _assertEqualWithError(fees1, estimated1, 10000);
    }

    function testMintFee(bool zeroForOne) public {
        (uint256 reserve0Before, uint256 reserve1Before) = pool.getReserves();

        uint256 swapOutput = _swap(1e15, zeroForOne, recipient); // buy and sell

        _claimFees();

        _swap((swapOutput * 10001) / 10000, !zeroForOne, recipient); // sell and buy

        (uint256 reserve0After, uint256 reserve1After) = pool.getReserves();

        _claimFees();

        uint256 profit0 = reserve0After - reserve0Before;
        uint256 profit1 = reserve1After - reserve1Before;

        (uint256 fees0, uint256 fees1) = _getBalances(barFeeTo);

        assertLt(fees0 * barFee, fees0 * maxFee); // Claiming fees when pool is out of balance is worse for the bar.
        assertLt(fees1 * barFee, fees1 * maxFee);

        _assertEqualWithError(profit0 * barFee, fees0 * maxFee, 10);
        _assertEqualWithError(profit1 * barFee, fees1 * maxFee, 10);
    }

    function _invokeMintFee() internal {
        pool.burn(abi.encode(recipient));
    }

    function _swap(
        uint256 amountIn,
        bool zeroForOne,
        address to
    ) internal returns (uint256 out) {
        bentoBox.transfer(BentoIERC20(address(zeroForOne ? token0 : token1)), address(this), address(pool), amountIn);
        (uint256 reserve0Before, uint256 reserve1Before) = pool.getReserves();
        out = pool.swap(abi.encode(zeroForOne, to));
        (uint256 reserve0After, uint256 reserve1After) = pool.getReserves();
        // Check reserves are correctly updated.
        if (zeroForOne) {
            assertEq(reserve0Before + amountIn, reserve0After);
            assertEq(reserve1Before - out, reserve1After);
        } else {
            assertEq(reserve0Before - out, reserve0After);
            assertEq(reserve1Before + amountIn, reserve1After);
        }
        // Check balances match reserves.
        (uint256 balance0, uint256 balance1) = _getPoolBalances();
        if (to != address(pool)) {
            assertEq(pool.reserve0(), balance0);
            assertEq(pool.reserve1(), balance1);
        } else {
            assertEq(pool.reserve0() + (zeroForOne ? 0 : out), balance0);
            assertEq(pool.reserve1() + (zeroForOne ? out : 0), balance1);
        }
    }

    function _getPoolBalances() internal view returns (uint256, uint256) {
        return _getBalances(address(pool));
    }

    function _getBalances(address acc) internal view returns (uint256 t0, uint256 t1) {
        t0 = bentoBox.balanceOf(BentoIERC20(address(token0)), address(acc));
        t1 = bentoBox.balanceOf(BentoIERC20(address(token1)), address(acc));
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

    function _burnLiquidity(
        uint256 amount,
        address from,
        address to
    ) internal {
        pool.burn(abi.encode(address(1))); // Gets rid of any token that are in the pool already and calls mint fee.
        Vm(HEVM_ADDRESS).prank(from);
        pool.transfer(address(pool), amount);

        uint256 liquidity = pool.balanceOf(address(pool));
        uint256 totalSupply = pool.totalSupply();
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        uint256 expected0 = (reserve0 * liquidity) / totalSupply;
        uint256 expected1 = (reserve1 * liquidity) / totalSupply;
        (uint256 toOldBalance0, uint256 toOldBalance1) = _getBalances(to);
        IPool.TokenAmount[] memory withdrawnAmounts = pool.burn(abi.encode(to));
        (uint256 toNewBalance0, uint256 toNewBalance1) = _getBalances(to);
        if (to != address(pool)) {
            assertEq(toNewBalance0 - toOldBalance0, withdrawnAmounts[0].amount);
            assertEq(toNewBalance1 - toOldBalance1, withdrawnAmounts[1].amount);
        }
        assertEq(expected0, withdrawnAmounts[0].amount);
        assertEq(expected1, withdrawnAmounts[1].amount);
    }

    function _assertEqualWithError(
        uint256 a,
        uint256 b,
        uint256 accuracy
    ) internal {
        a > b ? assertEq((a * accuracy) / b, accuracy) : assertEq((b * accuracy) / a, accuracy);
    }

    function _claimFees() internal {
        _invokeMintFee();
        uint256 feeBalance = pool.balanceOf(barFeeTo);
        Vm(HEVM_ADDRESS).prank(barFeeTo);
        pool.transfer(address(pool), feeBalance);
        pool.burn(abi.encode(barFeeTo));
    }
}
