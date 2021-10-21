// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./WrappedToken.sol";

contract WrapRegistry {
    mapping (address => address) private _registry;

    constructor () {}

    function checkToken(address token) public view returns (address) {
        return _registry[token];
    }

    function createWrappedToken(address token) public returns (address) {
        require(_registry[token] == address(0), "Token already wrapped");
        IERC20 baseToken = IERC20(token);
        string memory name = baseToken.name();
        string memory symbol = baseToken.symbol();
        WrappedToken wToken = new WrappedToken(string(abi.encodePacked("QWrap ", name)), string(abi.encodePacked("q", symbol)), address(this));
        _registry[token] = address(wToken);
        return address(wToken);
    }

    function mintWrapped(address token, uint amount) public {
        require(_registry[token] != address(0), "Token doesn't exist");
        IERC20 wToken = IERC20(_registry[token]);
        IERC20 baseToken = IERC20(token);
        baseToken.transferFrom(msg.sender, address(this), amount);
        wToken.mint(msg.sender, amount);
        wToken.approveFactory(msg.sender, type(uint).max);
    }
    
    function burnWrapped(address token, uint amount) public {
        require(_registry[token] != address(0), "Token doesn't exist");
        IERC20 wToken = IERC20(_registry[token]);
        IERC20 baseToken = IERC20(token);
        wToken.burn(msg.sender, amount);
        baseToken.transfer(msg.sender, amount);
    }
}