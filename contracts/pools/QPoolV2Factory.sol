// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./QPoolV2.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IMultiswap.sol";
import "../libraries/SafeMath.sol";
import "../libraries/SafeERC20.sol";
import "../libraries/Context.sol";
import "./QPoolDepositTokenV2.sol";

contract QPoolV2Factory is Context {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address private _duce;

    IMultiswap private router = IMultiswap(0x08b16410c53FA67b0CC2cA58bd0F6409f3349f7a);

    uint private _totalPools;

    mapping(uint => address) private _pools;
    mapping(address => uint) private _poolIndex;
    mapping(address => address) private _stakingPools;

    struct PoolData {
        uint160 creator;
        uint8 totalTokens;
    }

    constructor() {
        _duce = msg.sender;
    }

    function totalVotes() external view returns (uint) {
        return _totalPools;
    }

    function checkPool(address pool) external view returns (uint) {
        return _poolIndex[pool];
    }

    function getPoolByIndex(uint index) external view returns (address) {
        return _pools[index];
    }

    function getPools() external view returns (address[] memory) {
        address[] memory pools = new address[](_totalPools);
        
        for (uint i; i < _totalPools; i++) {
            pools[i] = _pools[i];
        }

        return pools;
    }

    function checkStakingPool(address pool) external view returns (address) {
        return _stakingPools[pool];
    }

    function createPool(string calldata name, string calldata symbol, address[] calldata tokens, uint[] calldata amounts) external {
        // Input checking occurs in pool contract
        QPoolV2 newPool = new QPoolV2(name, symbol, tokens, amounts);
        _totalPools += 1; // Increment prior to storing in mapping since indices start at 1
        _pools[_totalPools] = address(newPool);
        _poolIndex[address(newPool)] = _totalPools;
    }
}