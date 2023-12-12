// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract TestERC721 is ERC721("Test721", "TEST") {
    function mint(address to, uint256 id) external {
        _mint(to, id);
        // approve(to, id);
        // transferFrom(to, address(this), id);
    }
}