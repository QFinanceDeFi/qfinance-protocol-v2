// SPDX-License-Identifier: MIT
// QFinance Contracts V2.0.1

pragma solidity ^0.8.0;

interface IPoolFactory {
    function checkPool(address pool) external view returns (uint);

    function getPoolByIndex(uint index) external view returns (address);

    function getPools() external view returns (address[] memory);

    function checkStakingPool(address pool) external view returns (address);

    function totalVotes() external view returns (uint);
}