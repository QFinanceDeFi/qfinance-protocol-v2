// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Pool.sol";

contract PoolFactory {
    address private _master;
    mapping(address => bool) private _isPool;

    event PoolCreated(address indexed caller, address indexed pool);

    event NewMaster(address indexed caller, address indexed master);

    constructor() {
        _master = msg.sender;
    }

    function isPool(address pool) external view returns (bool) {
        return _isPool[pool];
    }

    function newPool() external returns (Pool) {
        Pool pool = new Pool();
        _isPool[address(pool)] = true;
        emit PoolCreated(msg.sender, address(pool));
        return pool;
    }

    function getMaster() external view returns (address) {
        return _master;
    }

    function setMaster(address newMaster) external returns (bool) {
        require(msg.sender == _master, "Not owner");
        emit NewMaster(msg.sender, newMaster);
        _master = newMaster;
        return true;
    }

    function collect(Pool pool) external {
        require(msg.sender == _master, "Not owner");
        uint256 collected = IERC20(address(pool)).balanceOf(address(this));
        bool transferMade = pool.transfer(_master, collected);
        require(transferMade, "Transfer failed");
    }
}
