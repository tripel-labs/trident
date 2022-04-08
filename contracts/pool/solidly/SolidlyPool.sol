// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {ReentrancyGuard} from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import {IBentoBoxMinimal} from "../../interfaces/IBentoBoxMinimal.sol";
import {ISolidlyPoolFactory} from "../../interfaces/ISolidlyPoolFactory.sol";
import {IMasterDeployer} from "../../interfaces/IMasterDeployer.sol";
import {IPool} from "../../interfaces/IPool.sol";

contract SolidlyPool is IPool, ERC20, ReentrancyGuard {
    uint256 internal constant MINIMUM_LIQUIDITY = 10**3;

    address public immutable token0;
    address public immutable token1;

    IBentoBoxMinimal public immutable bento;
    IMasterDeployer public immutable masterDeployer;

    uint256 internal immutable decimals0;
    uint256 internal immutable decimals1;

    uint128 public reserve0;
    uint128 public reserve1;

    error NotSupported();

    event Mint(address indexed sender, uint256 amount0, uint256 amount1, address indexed recipient);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Sync(uint256 reserve0, uint256 reserve1);

    bytes32 public constant override poolIdentifier = "Trident:SolidlyPool";

    constructor() ERC20("", "SLP", 18) {
        (bytes memory _deployData, IMasterDeployer _masterDeployer) = ISolidlyPoolFactory(msg.sender).getDeployData();

        (address _token0, address _token1) = abi.decode(_deployData, (address, address));

        (token0, token1) = (_token0, _token1);

        name = string(abi.encodePacked("Trident Solidly Pool - ", ERC20(_token0).symbol(), "/", ERC20(_token1).symbol()));

        decimals0 = 10**ERC20(_token0).decimals();
        decimals1 = 10**ERC20(_token1).decimals();

        bento = IBentoBoxMinimal(_masterDeployer.bento());
        masterDeployer = _masterDeployer;
    }

    function getAssets() public view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    function getReserves() public view returns (uint256 _reserve0, uint256 _reserve1) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    function _update(uint256 balance0, uint256 balance1) internal {
        reserve0 = uint128(balance0);
        reserve1 = uint128(balance1);
        emit Sync(reserve0, reserve1);
    }

    function mint(bytes calldata data) external nonReentrant returns (uint256 liquidity) {
        address recipient = abi.decode(data, (address));
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        // todo mintFee

        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            liquidity = _kFromShares(amount0, amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            // todo uneven mint
            liquidity = _min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }
        _mint(recipient, liquidity);
        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1, recipient);
    }

    function burn(bytes calldata data) external override nonReentrant returns (IPool.TokenAmount[] memory withdrawnAmounts) {
        address to = abi.decode(data, (address));
        (address _token0, address _token1) = (token0, token1);
        (uint256 balance0, uint256 balance1) = _balance();
        uint256 _liquidity = balanceOf[address(this)];

        // todo mintFee

        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        uint256 amount0 = (_liquidity * balance0) / _totalSupply; // using balances ensures pro-rata distribution
        uint256 amount1 = (_liquidity * balance1) / _totalSupply; // using balances ensures pro-rata distribution

        _burn(address(this), _liquidity);
        _transferShares(_token0, amount0, to, false);
        _transferShares(_token1, amount1, to, false);

        // This is safe from underflow - amounts are lesser figures derived from balances.
        unchecked {
            balance0 -= amount0;
            balance1 -= amount1;
        }

        withdrawnAmounts = new TokenAmount[](2);
        withdrawnAmounts[0] = TokenAmount({token: address(token0), amount: amount0});
        withdrawnAmounts[1] = TokenAmount({token: address(token1), amount: amount1});

        _update(balance0, balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(bytes calldata data) external override nonReentrant returns (uint256 amountOut) {
        (bool zeroForOne, address recipient) = abi.decode(data, (bool, address));
        (address _token0, address _token1) = (token0, token1);
        (uint128 _reserve0, uint128 _reserve1) = (reserve0, reserve1);

        require(_reserve0 != 0);

        (uint256 balance0, uint256 balance1) = _balance();
        uint256 amountIn;

        if (zeroForOne) {
            amountIn = balance0 - _reserve0;
            amountOut = _getAmountOutFromShares(amountIn, _token0, _reserve0, _reserve1);
            balance1 -= amountOut;
        } else {
            amountIn = balance1 - _reserve1;
            amountOut = _getAmountOutFromShares(amountIn, _token1, _reserve1, _reserve0);
            balance0 -= amountOut;
        }

        _transferShares(zeroForOne ? token1 : token0, amountOut, recipient, false);
        _update(balance0, balance1);

        emit Swap(recipient, zeroForOne ? token0 : token1, zeroForOne ? token1 : token0, amountIn, amountOut);
    }

    function getAmountOut(bytes calldata data) public view override returns (uint256 finalAmountOut) {
        (address tokenIn, uint256 amountIn) = abi.decode(data, (address, uint256));
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        amountIn -= amountIn / 10000; // remove fee from amount received
        finalAmountOut = _getAmountOut(amountIn, tokenIn, _reserve0, _reserve1);
    }

    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256) {
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        amountIn -= amountIn / 10000; // remove fee from amount received
        return _getAmountOut(amountIn, tokenIn, _reserve0, _reserve1);
    }

    function _getAmountOutFromShares(
        uint256 amountIn,
        address tokenIn,
        uint256 _reserve0,
        uint256 _reserve1
    ) internal view returns (uint256 amountOut) {
        // todo optimise use of tokenIn parameter
        amountOut = _getAmountOut(
            bento.toAmount(tokenIn, amountIn, false),
            tokenIn,
            bento.toAmount(token0, _reserve0, false),
            bento.toAmount(token1, _reserve1, false)
        );
        amountOut = bento.toShare(tokenIn == token0 ? token1 : token0, amountOut, false);
    }

    function _getAmountOut(
        uint256 amountIn,
        address tokenIn,
        uint256 _reserve0,
        uint256 _reserve1
    ) internal view returns (uint256) {
        uint256 xy = _k(_reserve0, _reserve1);
        _reserve0 = (_reserve0 * 1e18) / decimals0;
        _reserve1 = (_reserve1 * 1e18) / decimals1;
        (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
        amountIn = tokenIn == token0 ? (amountIn * 1e18) / decimals0 : (amountIn * 1e18) / decimals1;
        uint256 y = reserveB - _get_y(amountIn + reserveA, xy, reserveB);
        return (y * (tokenIn == token0 ? decimals1 : decimals0)) / 1e18;
    }

    function _kFromShares(uint256 x, uint256 y) internal view returns (uint256) {
        x = bento.toAmount(token0, x, false);
        y = bento.toAmount(token0, y, false);
        return _k(x, y);
    }

    function _k(uint256 x, uint256 y) internal view returns (uint256) {
        uint256 _x = (x * 1e18) / decimals0;
        uint256 _y = (y * 1e18) / decimals1;
        uint256 _a = (_x * _y) / 1e18;
        uint256 _b = ((_x * _x) / 1e18 + (_y * _y) / 1e18);
        return (_a * _b) / 1e18; // x3y+y3x >= k
    }

    function _f(uint256 x0, uint256 y) internal pure returns (uint256) {
        return (x0 * ((((y * y) / 1e18) * y) / 1e18)) / 1e18 + (((((x0 * x0) / 1e18) * x0) / 1e18) * y) / 1e18;
    }

    function _d(uint256 x0, uint256 y) internal pure returns (uint256) {
        return (3 * x0 * ((y * y) / 1e18)) / 1e18 + ((((x0 * x0) / 1e18) * x0) / 1e18);
    }

    function _get_y(
        uint256 x0,
        uint256 xy,
        uint256 y
    ) internal pure returns (uint256) {
        for (uint256 i = 0; i < 255; i++) {
            uint256 y_prev = y;
            uint256 k = _f(x0, y);
            if (k < xy) {
                uint256 dy = ((xy - k) * 1e18) / _d(x0, y);
                y = y + dy;
            } else {
                uint256 dy = ((k - xy) * 1e18) / _d(x0, y);
                y = y - dy;
            }
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                }
            } else {
                if (y_prev - y <= 1) {
                    return y;
                }
            }
        }
        return y;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _transferShares(
        address token,
        uint256 shares,
        address to,
        bool unwrapBento
    ) internal {
        if (unwrapBento) {
            bento.withdraw(token, address(this), to, 0, shares);
        } else {
            bento.transfer(token, address(this), to, shares);
        }
    }

    function _balance() internal view returns (uint256 balance0, uint256 balance1) {
        balance0 = bento.balanceOf(token0, address(this));
        balance1 = bento.balanceOf(token1, address(this));
    }

    function getAmountIn(bytes calldata) public pure override returns (uint256) {
        revert NotSupported();
    }

    function flashSwap(bytes calldata) public pure override returns (uint256) {
        revert NotSupported();
    }

    function burnSingle(bytes calldata) public pure override returns (uint256) {
        revert NotSupported();
    }
}
