// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20("Test20", "TEST") {
    function mint(address to, uint256 id) external {
        _mint(to, id);
        _approve(msg.sender, to, id);
        // transferFrom(to, address(this), id);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, recipient, amount);
        return true;
    }
}