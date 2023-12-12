// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {TokenizedVickeryAuction} from "./TokenizedVickeryAuction.sol";

/// @title An on-chain, over-collateralization, sealed-bid, second-price auction
contract TokenizedVickeryAuctionV2 is TokenizedVickeryAuction {
    mapping(address=>bool) public isBlacklisted;

    function testNumber() override public pure returns (uint256) {
        return 2;
    }
    
    function blackList(address seller) public {
        require(!isBlacklisted[seller], "user already blacklisted");
        isBlacklisted[seller] = true;
        // emit events as well
    }
    
    function removeFromBlacklist(address seller) public {
        require(isBlacklisted[seller], "user already whitelisted");
        isBlacklisted[seller] = false;
        // emit events as well
    }

    function getBlacklistStatus(address seller) external view returns (bool) {
        return isBlacklisted[seller];
    }
    
    function createAuction(
        address tokenContract,
        uint256 tokenId,
        address erc20Token,
        uint32 startTime,
        uint32 bidPeriod,
        uint32 revealPeriod,
        uint96 reservePrice
    ) override external {
        Auction storage auction = auctions[tokenContract][tokenId];

        if (isBlacklisted[msg.sender]) {
            revert ("User Blacklisted Error");
        }
        
        auction.seller = msg.sender;
        auction.startTime = startTime;
        auction.endOfBiddingPeriod = startTime + bidPeriod;
        auction.endOfRevealPeriod = startTime + bidPeriod + revealPeriod;
        // Reset
        auction.numUnrevealedBids = 0;
        // Both highest and second-highest bid are set to the reserve price.
        // Any winning bid must be at least this price, and the winner will 
        // pay at least this price.
        auction.highestBid = reservePrice;
        auction.secondHighestBid = reservePrice;
        // Reset
        auction.highestBidder = address(0);
        // Increment auction index for this item
        auction.index++;
        auction.erc20Token = erc20Token;

        // ERC20(erc20Token).approve(msg.sender, reservePrice);
        ERC721(tokenContract).transferFrom(msg.sender, address(this), tokenId);
        ERC20(erc20Token).transferFrom(msg.sender, address(this), reservePrice);
    }
}