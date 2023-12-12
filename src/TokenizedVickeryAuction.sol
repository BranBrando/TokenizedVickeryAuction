// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

/// @title An on-chain, over-collateralization, sealed-bid, second-price auction
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

contract TokenizedVickeryAuction is Initializable, UUPSUpgradeable{
    /// @dev Representation of an auction in storage. Occupies three slots.
    /// @param seller The address selling the auctioned asset.
    /// @param startTime The unix timestamp at which bidding can start.
    /// @param endOfBiddingPeriod The unix timestamp after which bids can no
    ///        longer be placed.
    /// @param endOfRevealPeriod The unix timestamp after which commitments can
    ///        no longer be opened.
    /// @param numUnrevealedBids The number of bid commitments that have not
    ///        yet been opened.
    /// @param highestBid The value of the highest bid revealed so far, or
    ///        the reserve price if no bids have exceeded it.
    /// @param secondHighestBid The value of the second-highest bid revealed
    ///        so far, or the reserve price if no two bids have exceeded it.
    /// @param highestBidder The bidder that placed the highest bid.
    /// @param index Auctions selling the same asset (i.e. tokenContract-tokenId
    ///        pair) share the same storage. This value is incremented for
    ///        each new auction of a particular asset.
    struct Auction {
        address seller;
        uint32 startTime;
        uint32 endOfBiddingPeriod;
        uint32 endOfRevealPeriod;
        // =====================
        uint64 numUnrevealedBids;
        uint96 highestBid;
        uint96 secondHighestBid;
        // =====================
        address highestBidder;
        uint64 index;
        address erc20Token;
    }

    /// @param commitment The hash commitment of a bid value.
    /// @param collateral The amount of collateral backing the bid.
    struct Bid {
        bytes20 commitment;
        uint96 collateral;
    }

    /// @notice A mapping storing auction parameters and state, indexed by
    ///         the ERC721 contract address and token ID of the asset being
    ///         auctioned.
    mapping(address => mapping(uint256 => Auction)) public auctions;

    /// @notice A mapping storing bid commitments and records of collateral,
    ///         indexed by: ERC721 contract address, token ID, auction index,
    ///         and bidder address. If the commitment is `bytes20(0)`, either
    ///         no commitment was made or the commitment was opened.
    mapping(
        address // ERC721 token contract
            => mapping(
                uint256 // ERC721 token ID
                    => mapping(
                    uint64 // Auction index
                        => mapping(address // Bidder
                            => Bid
                )
            )
        )
    ) public bids;

    function initialize() public initializer {}
    
    function _authorizeUpgrade(address) internal override {}

    function testNumber() virtual public pure returns (uint256) {
        return 1;
    }

    /// @notice Creates an auction for the given ERC721 asset with the given
    ///         auction parameters.
    /// @param tokenContract The address of the ERC721 contract for the asset
    ///        being auctioned.
    /// @param tokenId The ERC721 token ID of the asset being auctioned.
    /// @param startTime The unix timestamp at which bidding can start.
    /// @param bidPeriod The duration of the bidding period, in seconds.
    /// @param revealPeriod The duration of the commitment reveal period,
    ///        in seconds.
    /// @param reservePrice The minimum price that the asset will be sold for.
    ///        If no bids exceed this price, the asset is returned to `seller`.
    function createAuction(
        address tokenContract,
        uint256 tokenId,
        address erc20Token,
        uint32 startTime,
        uint32 bidPeriod,
        uint32 revealPeriod,
        uint96 reservePrice
    ) virtual external {
        Auction storage auction = auctions[tokenContract][tokenId];
        
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

    /// @notice Commits to a bid on an item being auctioned. If a bid was
    ///         previously committed to, overwrites the previous commitment.
    ///         Value attached to this call is used as collateral for the bid.
    /// @param tokenContract The address of the ERC721 contract for the asset
    ///        being auctioned.
    /// @param tokenId The ERC721 token ID of the asset being auctioned.
    /// @param commitment The commitment to the bid, computed as
    ///        `bytes20(keccak256(abi.encode(nonce, bidValue, tokenContract, tokenId, auctionIndex)))`.
    /// @param erc20Tokens The amount of ERC20 tokens to be used as collateral
    function commitBid(address tokenContract, uint256 tokenId, bytes20 commitment, uint256 erc20Tokens) external {
        if (commitment == bytes20(0)) {
            revert ("Zero Commitment Error");
        }

        Auction storage auction = auctions[tokenContract][tokenId];

        if (
            block.timestamp < auction.startTime || 
            block.timestamp > auction.endOfBiddingPeriod
        ) {
            revert ("Not In Bid Period Error");
        }

        uint64 auctionIndex = auction.index;
        Bid storage bid = bids[tokenContract][tokenId][auctionIndex][msg.sender];
        // If this is the bidder's first commitment, increment `numUnrevealedBids`.
        if (bid.commitment == bytes20(0)) {
            auction.numUnrevealedBids++;
        }
        bid.commitment = commitment;
        if (erc20Tokens != 0) {
            bid.collateral += uint96(erc20Tokens);
            ERC20(auction.erc20Token).transferFrom(msg.sender, address(this), erc20Tokens);
        }
    }

    /// @notice Reveals the value of a bid that was previously committed to.
    /// @param tokenContract The address of the ERC721 contract for the asset
    ///        being auctioned.
    /// @param tokenId The ERC721 token ID of the asset being auctioned.
    /// @param bidValue The value of the bid.
    /// @param nonce The random input used to obfuscate the commitment.
    function revealBid(address tokenContract, uint256 tokenId, uint96 bidValue, bytes32 nonce) external {
        Auction storage auction = auctions[tokenContract][tokenId];

        if (
            block.timestamp <= auction.endOfBiddingPeriod ||
            block.timestamp > auction.endOfRevealPeriod
        ) {
            revert ("Not In Reveal Period Error");
        }

        uint64 auctionIndex = auction.index;
        Bid storage bid = bids[tokenContract][tokenId][auctionIndex][msg.sender];

        // Check that the opening is valid
        bytes20 bidHash = bytes20(keccak256(abi.encode(
            nonce,
            bidValue,
            tokenContract,
            tokenId,
            auctionIndex
        )));
        if (bidHash != bid.commitment) {
            revert("Invalid Opening Error");
        } else {
            // Mark commitment as open
            bid.commitment = bytes20(0);
            auction.numUnrevealedBids--;
        }

        uint96 collateral = bid.collateral;
        if (collateral < bidValue) {
            // Return collateral
            bid.collateral = 0;
            //payable(msg.sender).transfer(collateral);
            ERC20(auction.erc20Token).transferFrom(address(this), msg.sender, collateral);
        } else {
            // Update record of (second-)highest bid as necessary
            uint96 currentHighestBid = auction.highestBid;
            if (bidValue > currentHighestBid) {
                auction.highestBid = bidValue;
                auction.secondHighestBid = currentHighestBid;
                auction.highestBidder = msg.sender;
            } else {
                if (bidValue > auction.secondHighestBid) {
                    auction.secondHighestBid = bidValue;
                }
                // Return collateral
                bid.collateral = 0;
                //payable(msg.sender).transfer(collateral);
                ERC20(auction.erc20Token).transferFrom(address(this), msg.sender, collateral);
            }
        }
    }

    /// @notice Ends an active auction. Can only end an auction if the bid reveal
    ///         phase is over, or if all bids have been revealed. Disburses the auction
    ///         proceeds to the seller. Transfers the auctioned asset to the winning
    ///         bidder and returns any excess collateral. If no bidder exceeded the
    ///         auction's reserve price, returns the asset to the seller.
    /// @param tokenContract The address of the ERC721 contract for the asset auctioned.
    /// @param tokenId The ERC721 token ID of the asset auctioned.
    function endAuction(address tokenContract, uint256 tokenId) external {
        Auction storage auction = auctions[tokenContract][tokenId];
        if (auction.index == 0) {
            revert ("InvalidAuctionIndexError");
        }

        if (block.timestamp <= auction.endOfBiddingPeriod) {
            revert ("BidPeriodOngoingError");
        } else if (block.timestamp <= auction.endOfRevealPeriod) {
            if (auction.numUnrevealedBids != 0) {
                // cannot end auction early unless all bids have been revealed
                revert ("RevealPeriodOngoingError");
            }
        }

        address highestBidder = auction.highestBidder;
        if (highestBidder == address(0)) {
            // No winner, return asset to seller.
            ERC721(tokenContract).safeTransferFrom(address(this), auction.seller, tokenId);
        } else {
            // Transfer auctioned asset to highest bidder
            ERC721(tokenContract).safeTransferFrom(address(this), highestBidder, tokenId);
            uint96 secondHighestBid = auction.secondHighestBid;
            ERC20(auction.erc20Token).transferFrom(address(this), auction.seller, uint256(secondHighestBid));
            //payable(auction.seller).transfer(secondHighestBid);

            // Return excess collateral
            Bid storage bid = bids[tokenContract][tokenId][auction.index][highestBidder];
            uint96 collateral = bid.collateral;
            bid.collateral = 0;
            if (collateral - secondHighestBid != 0) {
                ERC20(auction.erc20Token).transferFrom(address(this), highestBidder, uint256(collateral - secondHighestBid));
                //payable(highestBidder).transfer(collateral - secondHighestBid);
            }
        }
    }

    /// @notice Withdraws collateral. Bidder must have opened their bid commitment
    ///         and cannot be in the running to win the auction.
    /// @param tokenContract The address of the ERC721 contract for the asset
    ///        that was auctioned.
    /// @param tokenId The ERC721 token ID of the asset that was auctioned.
    /// @param auctionIndex The index of the auction that was being bid on.
    function withdrawCollateral(address tokenContract, uint256 tokenId, uint64 auctionIndex) external {
        Auction storage auction = auctions[tokenContract][tokenId];
        uint64 currentAuctionIndex = auction.index;
        if (auctionIndex > currentAuctionIndex) {
            revert ("Invalid Auction Index Error");
        }

        Bid storage bid = bids[tokenContract][tokenId][auctionIndex][msg.sender];
        if (bid.commitment != bytes20(0)) {
            revert ("Unrevealed Bid Error");
        }

        if (auctionIndex == currentAuctionIndex) {
            // If bidder has revealed their bid and is not currently in the 
            // running to win the auction, they can withdraw their collateral.
            if (msg.sender == auction.highestBidder) {
                revert ("Cannot Withdraw Error");    
            }
        }
        // Return collateral
        uint96 collateral = bid.collateral;
        bid.collateral = 0;
        ERC20(auction.erc20Token).transferFrom(address(this), msg.sender, collateral);
    }

    /// @notice Gets the parameters and state of an auction in storage.
    /// @param tokenContract The address of the ERC721 contract for the asset auctioned.
    /// @param tokenId The ERC721 token ID of the asset auctioned.
    function getAuction(address tokenContract, uint256 tokenId) external view returns (Auction memory auction) {
        auction = auctions[tokenContract][tokenId];
    }
}