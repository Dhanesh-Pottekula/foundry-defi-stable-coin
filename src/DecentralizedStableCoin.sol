// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralisedStableCoin
 * @author dhanesh
 * collatoral : exogrnous (ETH , BTC )
 * minting: algorithmic
 * relative stability : pegged to USD
 *
 * this is the contract meant to governed by DSCEngine. this contract is just the ERC20 implementation of our stable coin system
 */
contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin_AmountMustBeMoreThanZero();
    error DecentralisedStableCoin_BurnAmountExceedsBalance();
    error DecentralisedStableCoin_CantBeZeroAddress();

    /**
     * ERC20Burnable contract adds the burn function, and extends the ERC20 contract
     * ERC20 contract has the constructor so we need to implement the constructor in below
     */
    constructor() ERC20("DecentralisedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert DecentralizedStableCoin_AmountMustBeMoreThanZero();
        }
        if (balance <= _amount) {
            revert DecentralisedStableCoin_BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin_CantBeZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin_AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
