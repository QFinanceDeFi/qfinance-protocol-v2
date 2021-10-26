// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract Const {
    uint256 public constant ONE = 10**18;

    uint256 public constant MIN_BOUND_TOKENS = 2;
    uint256 public constant MAX_BOUND_TOKENS = 8;

    uint256 public constant MIN_FEE = ONE / 10**6;
    uint256 public constant MAX_FEE = ONE / 10;
    uint256 public constant EXIT_FEE = 0;

    uint256 public constant MIN_WEIGHT = ONE;
    uint256 public constant MAX_WEIGHT = ONE * 50;
    uint256 public constant MAX_TOTAL_WEIGHT = ONE * 50;
    uint256 public constant MIN_BALANCE = ONE / 10**12;

    uint256 public constant INIT_POOL_SUPPLY = ONE * 100;

    uint256 public constant MIN_POW_BASE = 1 wei;
    uint256 public constant MAX_POW_BASE = (2 * ONE) - 1 wei;
    uint256 public constant POW_PRECISION = ONE / 10**10;

    uint256 public constant MAX_IN_RATIO = ONE / 2;
    uint256 public constant MAX_OUT_RATIO = (ONE / 3) + 1 wei;
}
