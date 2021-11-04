// SPDX-License-Identifier: MIT
// QFinance Contracts V2.0.1

pragma solidity ^0.8.0;

interface IRewardsPool {
    function staked(address account) external view returns (uint256);
}