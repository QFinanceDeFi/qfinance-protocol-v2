// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./TokenBase.sol";

abstract contract PoolToken is TokenBase, IERC20 {
    string private _name = "QPool Deposit Token";
    string private _symbol = "QPDT";
    uint8 private _decimals = 18;

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function allowance(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return _allowance[owner][spender];
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balance[account];
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function increaseApproval(address spender, uint256 amount)
        external
        returns (bool)
    {
        _allowance[msg.sender][spender] = add(_allowance[msg.sender][spender], amount);
        emit Approval(msg.sender, spender, _allowance[msg.sender][spender]);
        return true;
    }

    function decreaseApproval(address spender, uint256 amount)
        external
        returns (bool)
    {
        uint256 oldValue = _allowance[msg.sender][spender];
        if (amount > oldValue) {
            _allowance[msg.sender][spender] = 0;
        } else {
            _allowance[msg.sender][spender] = sub(oldValue, amount);
        }
        emit Approval(msg.sender, spender, _allowance[msg.sender][spender]);
        return true;
    }

    function transfer(address dst, uint256 amt) external returns (bool) {
        _move(msg.sender, dst, amt);
        return true;
    }

    function transferFrom(
        address src,
        address dst,
        uint256 amt
    ) external returns (bool) {
        require(
            msg.sender == src || amt <= _allowance[src][msg.sender],
            "ERR_BTOKEN_BAD_CALLER"
        );
        _move(src, dst, amt);
        if (
            msg.sender != src &&
            _allowance[src][msg.sender] != type(uint256).max
        ) {
            _allowance[src][msg.sender] = sub(_allowance[src][msg.sender], amt);
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }
        return true;
    }
}
