// SPDX-License-Identifier: MIT
// QFinance Contracts v2.0.1

pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../interfaces/IPriceAggregator.sol";

contract PriceOracle {

    IPriceAggregator private _priceFeed;

    mapping (address => uint) private _prices;
    mapping (address => address) private _tokenLookups;

    // solhint-disable-next-line
    constructor () { }

    function addPriceLookup(address token, address feed) public returns (bool) {
        _tokenLookups[token] = feed;
        return true;
    }

    function getLatestPrice(address token) public view returns (int) {
        require(_tokenLookups[token] != address(0), "No price feed");
        IPriceAggregator agg = IPriceAggregator(_tokenLookups[token]);
        (, int price, , ,) = agg.latestRoundData();
        return price;
    }
}