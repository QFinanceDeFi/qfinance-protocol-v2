// SPDX-License-Identifier: MIT
// QFinance Contracts v2.0.1

pragma solidity ^0.8.0;

import "./Num.sol";

/**
 * @dev Base contract for LP tokens.
 */
contract TokenBase is Num {
    mapping(address => uint256) internal _balance;
    mapping(address => mapping(address => uint256)) internal _allowance;
    uint256 internal _totalSupply;

    event Approval(address indexed sender, address indexed receiver, uint256 amount);
    event Transfer(address indexed sender, address indexed receiver, uint256 amount);

    function _mint(uint256 amount) internal {
        _balance[address(this)] = add(_balance[address(this)], amount);
        _totalSupply = add(_totalSupply, amount);
        emit Transfer(address(0), address(this), amount);
    }

    function _burn(uint256 amount) internal {
        require(_balance[address(this)] >= amount, "ERR_INSUFFICIENT_BAL");
        _balance[address(this)] = sub(_balance[address(this)], amount);
        _totalSupply = sub(_totalSupply, amount);
        emit Transfer(address(this), address(0), amount);
    }

    function _move(
        address sender,
        address receiver,
        uint256 amount
    ) internal {
        require(_balance[sender] >= amount, "ERR_INSUFFICIENT_BAL");
        _balance[sender] = sub(_balance[sender], amount);
        _balance[receiver] = add(_balance[receiver], amount);
        emit Transfer(sender, receiver, amount);
    }

    function _push(address to, uint256 amount) internal {
        _move(address(this), to, amount);
    }

    function _pull(address from, uint256 amount) internal {
        _move(from, address(this), amount);
    }
}
