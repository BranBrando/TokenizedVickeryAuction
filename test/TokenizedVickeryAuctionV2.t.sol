// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;
import {TokenizedVickeryAuctionV2} from "../src/TokenizedVickeryAuctionV2.sol";
import "forge-std/Test.sol";
import {TestERC721} from "./TestERC721.sol";
import {TestERC20} from "./TestERC20.sol";
import "forge-std/console.sol";

contract BasicTokenizedVickeryAuctionV2Test is Test {
    bytes32[] proposalNames;
    address private alice;
    address private bob;
    address private carol;
    TokenizedVickeryAuctionV2 auction;
    TestERC721 erc721;
    TestERC20 erc20;

    uint256 constant erc20Tokens = 10;
    uint96 constant oneERC20Token = 1;
    uint256 constant TOKEN_ID = 1;

    function setUp() public {
        auction = new TokenizedVickeryAuctionV2();
        alice = vm.addr(1);
        bob = vm.addr(2);
        carol = vm.addr(3);

        erc721 = new TestERC721();
        erc20 = new TestERC20();
        erc721.mint(carol, TOKEN_ID);
        
        erc20.mint(alice, erc20Tokens);
        erc20.mint(bob, erc20Tokens);
        erc20.mint(carol, erc20Tokens);
        hoax(carol);
        erc721.setApprovalForAll(address(auction), true);
    }

    function testCanAddBlacklist() external {
        auction.blackList(bob);
        assertEq(auction.getBlacklistStatus(bob), true);
    }

    function testCannotAddBlacklistIfAlreadyBlacklisted() external {
        auction.blackList(bob);
        assertEq(auction.getBlacklistStatus(bob), true);
        vm.expectRevert("user already blacklisted");
        auction.blackList(bob);
    }
    function testCanRemoveFromBlacklist() external {
        auction.blackList(bob);
        assertEq(auction.getBlacklistStatus(bob), true);
        auction.removeFromBlacklist(bob);
        assertEq(auction.getBlacklistStatus(bob), false);
    }

    function testCannotRemoveFromBlacklistIfNotBlacklisted() external {
        vm.expectRevert("user already whitelisted");
        auction.removeFromBlacklist(bob);
    }
    
    function testCannotCreateAuctionIfBlacklisted() external {
        auction.blackList(carol);
        assertEq(auction.getBlacklistStatus(carol), true);
        hoax(carol);
        vm.expectRevert("User Blacklisted Error");
        auction.createAuction(
            address(erc721),
            TOKEN_ID,
            address(erc20),
            uint32(block.timestamp + 1 hours),
            1 hours,
            1 hours,
            oneERC20Token
        );
    }

    function testCanCreateAuctionIfNotBlacklisted() external {
        hoax(carol);
        auction.createAuction(
            address(erc721),
            TOKEN_ID,
            address(erc20),
            uint32(block.timestamp + 1 hours),
            1 hours,
            1 hours,
            oneERC20Token
        );
    }
}
