// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;
import {TokenizedVickeryAuction} from "../src/TokenizedVickeryAuction.sol";
import "forge-std/Test.sol";
import {TestERC721} from "./TestERC721.sol";
import {TestERC20} from "./TestERC20.sol";
import "forge-std/console.sol";

contract BasicTokenizedVickeryAuctionTest is Test {
    bytes32[] proposalNames;
    address private alice;
    address private bob;
    address private carol;
    TokenizedVickeryAuction auction;
    TestERC721 erc721;
    TestERC20 erc20;

    uint256 constant erc20Tokens = 10;
    uint96 constant oneERC20Token = 1;
    uint256 constant TOKEN_ID = 1;

    function setUp() public {
        auction = new TokenizedVickeryAuction();
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

    function testCreateAuction() external {
        TokenizedVickeryAuction.Auction memory expectedAuction = TokenizedVickeryAuction.Auction({
            seller: carol,
            startTime: uint32(block.timestamp + 1 hours),
            endOfBiddingPeriod: uint32(block.timestamp + 2 hours),
            endOfRevealPeriod: uint32(block.timestamp + 3 hours),
            numUnrevealedBids: 0,
            highestBid: oneERC20Token,
            secondHighestBid: oneERC20Token,
            highestBidder: address(0),
            index: 1,
            erc20Token: address(erc20)
        });
        TokenizedVickeryAuction.Auction memory actualAuction = createAuction(TOKEN_ID);
        assertAuctionsEqual(actualAuction, expectedAuction);
    }

    function createAuction(
        uint256 tokenId
    ) private returns (TokenizedVickeryAuction.Auction memory a) {
        vm.prank(carol);
        auction.createAuction(
            address(erc721),
            tokenId,
            address(erc20),
            uint32(block.timestamp + 1 hours),
            1 hours,
            1 hours,
            oneERC20Token
        );
        return auction.getAuction(address(erc721), tokenId);
    }


    function testCommitBid() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = oneERC20Token;
        bytes20 commitment = commitBid(
            TOKEN_ID,
            bob,
            oneERC20Token + 1,
            bytes32(uint256(123)),
            collateral
        );
        assertBid(1, bob, commitment, collateral, 1);
    }

    function testCannotCommitBidIfAuctionIsNotActive() external {
        bytes20 commitment = bytes20(keccak256(abi.encode(
            bytes32(uint256(123)),
            oneERC20Token + 1,
            bob,
            TOKEN_ID,
            auction.getAuction(address(erc721), TOKEN_ID).index // auction index
        )));
        hoax(bob);
        vm.expectRevert("Not In Bid Period Error");
        auction.commitBid(
            address(erc721),
            TOKEN_ID,
            commitment,
            erc20Tokens
        );
    }

    function testCannotCommitBidBeforeBiddingPeriod() external {
        createAuction(TOKEN_ID);
        skip(59 minutes);
        bytes20 commitment = bytes20(keccak256(abi.encode(
            bytes32(uint256(123)),
            oneERC20Token + 1,
            bob,
            TOKEN_ID,
            auction.getAuction(address(erc721), TOKEN_ID).index // auction index
        )));
        hoax(bob);
        vm.expectRevert("Not In Bid Period Error");
        auction.commitBid(
            address(erc721),
            TOKEN_ID,
            commitment,
            erc20Tokens
        );
    }

    function testCannotCommitBidAfterBiddingPeriod() external {
        createAuction(TOKEN_ID);
        skip(2 hours + 1);
        bytes20 commitment = bytes20(keccak256(abi.encode(
            bytes32(uint256(123)),
            oneERC20Token + 1,
            bob,
            TOKEN_ID,
            auction.getAuction(address(erc721), TOKEN_ID).index // auction index
        )));
        hoax(bob);
        vm.expectRevert("Not In Bid Period Error");
        auction.commitBid(
            address(erc721),
            TOKEN_ID,
            commitment,
            erc20Tokens
        );
    }

    function testCanUpdateCommitment() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 3 * oneERC20Token;
        commitBid(
            TOKEN_ID,
            bob,
            oneERC20Token + 1,
            bytes32(uint256(123)),
            collateral
        );
        bytes20 commitment = commitBid(
            TOKEN_ID,
            bob,
            oneERC20Token + 2,
            bytes32(uint256(123)),
            collateral
        );
        assertBid(1, bob, commitment, 2 * collateral, 1);
    }

    function testCanAddCollateral() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 3 * oneERC20Token;
        commitBid(
            TOKEN_ID,
            bob,
            oneERC20Token + 1,
            bytes32(uint256(123)),
            collateral
        );
        bytes20 commitment = commitBid(
            TOKEN_ID,
            bob,
            oneERC20Token + 1, // same bid
            bytes32(uint256(123)),
            collateral
        );
        assertBid(1, bob, commitment, 2 * collateral, 1);
    }

    function testRevealBid() external {
        TokenizedVickeryAuction.Auction memory expectedState = 
            createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 3 * oneERC20Token;
        uint96 bidValue = oneERC20Token + 1;
        bytes32 nonce = bytes32(uint256(123));
        commitBid(
            TOKEN_ID,
            bob,
            bidValue,
            nonce,
            collateral
        );
        skip(1 hours);
        hoax(bob);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            bidValue,
            nonce
        );

        expectedState.numUnrevealedBids = 0; // the only bid was revealed
        expectedState.highestBid = bidValue;
        expectedState.highestBidder = bob;
        assertAuctionsEqual(
            auction.getAuction(address(erc721), 1),
            expectedState
        );
    }

    function testCannotRevealBidAfterRevealPeriod() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 3 * oneERC20Token;
        uint96 bidValue = oneERC20Token + 1;
        bytes32 nonce = bytes32(uint256(123));
        commitBid(
            TOKEN_ID,
            bob,
            bidValue,
            nonce,
            collateral
        );
        skip(2 hours);
        hoax(bob);
        vm.expectRevert("Not In Reveal Period Error");
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            bidValue,
            nonce
        );
    }


    function testCannotRevealUsingDifferentNonce() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint96 bidValue = oneERC20Token + 1;
        bytes32 nonce = bytes32(uint256(123));
        skip(1 hours);
        //bytes32 wrongNonce = bytes32(uint256(nonce) + 1);        
        hoax(bob);
        vm.expectRevert("Invalid Opening Error");
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            bidValue,
            nonce
        );
    }

    function testCannotRevealUsingDifferentBidValue() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint96 bidValue = oneERC20Token + 1;
        bytes32 nonce = bytes32(uint256(123));
        skip(1 hours);
        //uint96 wrongValue = bidValue + 1;
        
        hoax(bob);
        vm.expectRevert("Invalid Opening Error");
        
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            bidValue,
            nonce
        );
    }

    function testRevealWithInsufficientCollateral() external {
        TokenizedVickeryAuction.Auction memory expectedState = 
            createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = oneERC20Token;
        uint96 bidValue = oneERC20Token + 1;
        bytes32 nonce = bytes32(uint256(123));
        commitBid(
            TOKEN_ID,
            bob,
            bidValue,
            nonce,
            collateral
        );
        skip(1 hours);
        hoax(bob);
        
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            bidValue,
            nonce
        );
        assertAuctionsEqual(
            auction.getAuction(address(erc721), TOKEN_ID),
            expectedState
        );
        assertBid(
            1,
            bob,
            bytes20(0), // commitment was cleared
            0, // collateral was zeroed
            0
        );
    }

    function testUpdateHighestBidder() external {
        TokenizedVickeryAuction.Auction memory expectedState = 
            createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 3 * oneERC20Token;
        commitBid(
            TOKEN_ID,
            bob,
            oneERC20Token + 1,
            bytes32(uint256(123)),
            collateral
        );
        commitBid(
            TOKEN_ID,
            alice,
            oneERC20Token + 2,
            bytes32(uint256(234)),
            collateral
        );
        skip(1 hours);
        hoax(bob);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            oneERC20Token + 1,
            bytes32(uint256(123))
        );
        expectedState.numUnrevealedBids = 1;
        expectedState.highestBid = oneERC20Token + 1;
        expectedState.highestBidder = bob;
        assertAuctionsEqual(
            auction.getAuction(address(erc721), TOKEN_ID),
            expectedState
        );
        hoax(alice);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            oneERC20Token + 2,
            bytes32(uint256(234))
        );
        expectedState.numUnrevealedBids = 0;
        expectedState.highestBid = oneERC20Token + 2;
        expectedState.highestBidder = alice;
        expectedState.secondHighestBid = oneERC20Token + 1;
        assertAuctionsEqual(
            auction.getAuction(address(erc721), TOKEN_ID),
            expectedState
        );
    }

    function testWithdrawsCollateralIfNotHighestBid() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 3 * oneERC20Token;
        uint96 bidValue = oneERC20Token;
        bytes32 nonce = bytes32(uint256(123));
        commitBid(
            TOKEN_ID,
            bob,
            bidValue,
            nonce,
            collateral
        );
        skip(1 hours);
        uint256 bobBalanceBefore = erc20.balanceOf(bob);
        hoax(bob);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            bidValue,
            nonce
        );
        uint256 bobBalance = erc20.balanceOf(bob);
        assertEq(
            bobBalance,
            bobBalanceBefore + collateral,
            "bob's balance"
        );
        assertBid(
            1,
            bob,
            bytes20(0), // commitment was cleared
            0, // collateral was zeroed
            0
        );
    }

    function testEndAuctionEarly() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 3 * oneERC20Token;
        commitBid(
            TOKEN_ID,
            bob,
            oneERC20Token + 1,
            bytes32(uint256(123)),
            collateral
        );
        commitBid(
            TOKEN_ID,
            alice,
            oneERC20Token + 2,
            bytes32(uint256(234)),
            collateral
        );
        skip(1 hours);
        hoax(bob);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            oneERC20Token + 1,
            bytes32(uint256(123))
        );
        hoax(alice);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            oneERC20Token + 2,
            bytes32(uint256(234))
        );
        uint256 carolBalanceBefore = erc20.balanceOf(carol);
        auction.endAuction(address(erc721), TOKEN_ID);
        assertEq(
            erc20.balanceOf(carol),
            carolBalanceBefore + (oneERC20Token + 1),
            "carol's balance"
        );
        assertEq(
            erc721.ownerOf(1),
            alice,
            "owner of tokenId 1"
        );
        assertBid(
            1,
            alice,
            bytes20(0), // commitment was cleared
            0, // collateral was zeroed
            0
        );
    }

    function testCannotEndAuctionEarlyIfNotAllBidsRevealed() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 3 * oneERC20Token;
        commitBid(
            TOKEN_ID,
            bob,
            oneERC20Token + 1,
            bytes32(uint256(123)),
            collateral
        );
        commitBid(
            TOKEN_ID,
            alice,
            oneERC20Token + 2,
            bytes32(uint256(234)),
            collateral
        );
        skip(1 hours);
        hoax(alice);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            oneERC20Token + 2,
            bytes32(uint256(234))
        );
        vm.expectRevert("RevealPeriodOngoingError");
        auction.endAuction(address(erc721), TOKEN_ID);
    }

    function testCannotEndAuctionBeforeEndOfBidding() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 3 * oneERC20Token;
        commitBid(
            TOKEN_ID,
            bob,
            oneERC20Token + 1,
            bytes32(uint256(123)),
            collateral
        );
        commitBid(
            TOKEN_ID,
            alice,
            oneERC20Token + 2,
            bytes32(uint256(234)),
            collateral
        );
        vm.expectRevert("BidPeriodOngoingError");
        auction.endAuction(address(erc721), TOKEN_ID);
    }

    function testEndAuctionWithNoWinner() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        skip(2 hours);
        auction.endAuction(address(erc721), TOKEN_ID);
        assertEq(
            erc721.ownerOf(1),
            carol,
            "owner of tokenId 1"
        );
    }

    function testEndAuctionAfterRevealPeriod() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 3 * oneERC20Token;
        commitBid(
            TOKEN_ID,
            bob,
            oneERC20Token + 1,
            bytes32(uint256(123)),
            collateral
        );
        bytes20 aliceCommitment = commitBid(
            TOKEN_ID,
            alice,
            oneERC20Token + 2,
            bytes32(uint256(234)),
            collateral
        );
        skip(1 hours);
        hoax(bob);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            oneERC20Token + 1,
            bytes32(uint256(123))
        );
        skip(1 hours);
        uint256 carolBalanceBefore = erc20.balanceOf(carol);
        auction.endAuction(address(erc721), TOKEN_ID);
        assertEq(
            erc20.balanceOf(carol),
            carolBalanceBefore + oneERC20Token,
            "carol's balance"
        );
        assertEq(
            erc721.ownerOf(1),
            bob,
            "owner of tokenId 1"
        );
        assertBid(
            1,
            bob,
            bytes20(0), // commitment was cleared
            0, // collateral was zeroed
            1 // alice's bid was not revealed
        );
        assertBid(
            1,
            alice,
            aliceCommitment, // commitment was not cleared
            collateral, // collateral was not zeroed
            1 // alice's bid was not revealed
        );
    }

    function testCanWithdrawCollateralIfNotWinner() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 3 * oneERC20Token;
        commitBid(
            TOKEN_ID,
            bob,
            oneERC20Token + 1,
            bytes32(uint256(123)),
            collateral
        );
        commitBid(
            TOKEN_ID,
            alice,
            oneERC20Token + 2,
            bytes32(uint256(234)),
            collateral
        );
        skip(1 hours);
        hoax(bob);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            oneERC20Token + 1,
            bytes32(uint256(123))
        );
        hoax(alice);
        auction.revealBid(
            address(erc721),
            TOKEN_ID,
            oneERC20Token + 2,
            bytes32(uint256(234))
        );
        uint256 bobBalanceBefore = erc20.balanceOf(bob);
        hoax(bob);
        auction.withdrawCollateral(
            address(erc721),
            TOKEN_ID,
            1
        );
        uint256 bobBalance = erc20.balanceOf(bob);
        assertEq(
            bobBalance,
            bobBalanceBefore + collateral,
            "bob's balance"
        );
        assertBid(
            1,
            bob,
            bytes20(0), // commitment was cleared
            0, // collateral was zeroed
            0
        );
    }

    function testCannotWithdrawCollateralWithoutRevealingBid() external {
        createAuction(TOKEN_ID);
        skip(1 hours + 30 minutes);
        uint256 collateral = 3 * oneERC20Token;
        commitBid(
            TOKEN_ID,
            bob,
            oneERC20Token + 1,
            bytes32(uint256(123)),
            collateral
        );
        commitBid(
            TOKEN_ID,
            alice,
            oneERC20Token + 2,
            bytes32(uint256(234)),
            collateral
        );
        skip(1 hours);
        hoax(bob);
        vm.expectRevert("Unrevealed Bid Error");
        auction.withdrawCollateral(
            address(erc721),
            TOKEN_ID,
            1
        );
    }
 
    function assertAuctionsEqual(
        TokenizedVickeryAuction.Auction memory actualAuction,
        TokenizedVickeryAuction.Auction memory expectedAuction
    ) private {
        assertEq(actualAuction.seller, expectedAuction.seller);
        assertEq(actualAuction.startTime, expectedAuction.startTime);
        assertEq(
            actualAuction.endOfBiddingPeriod,
            expectedAuction.endOfBiddingPeriod
        );
        assertEq(
            actualAuction.endOfRevealPeriod,
            expectedAuction.endOfRevealPeriod
        );
        assertEq(
            actualAuction.numUnrevealedBids,
            expectedAuction.numUnrevealedBids
        );
        assertEq(actualAuction.highestBid, expectedAuction.highestBid);
        assertEq(
            actualAuction.secondHighestBid,
            expectedAuction.secondHighestBid
        );
        assertEq(actualAuction.highestBidder, expectedAuction.highestBidder);
        assertEq(actualAuction.index, expectedAuction.index);
    }
    
    function commitBid(
        uint256 tokenid,
        address from,
        uint96 bidValue,
        bytes32 nonce,
        uint256 tokens
    )
        private
        returns (bytes20 commitment)
    {
        commitment = bytes20(keccak256(abi.encode(
            nonce, 
            bidValue,
            address(erc721),
            tokenid,
            1 // auction index
        )));
        hoax(from);
        auction.commitBid(
            address(erc721),
            tokenid,
            commitment,
            tokens
        );
    }

    function assertBid(
        uint64 auctionIndex,
        address bidder,
        bytes20 commitment,
        uint256 collateral,
        uint64 numUnrevealedBids
    ) private {
        (bytes20 storedCommitment, uint96 storedCollateral) = auction.bids(
            address(erc721),
            TOKEN_ID,
            auctionIndex,
            bidder
        );
        assertEq(storedCommitment, commitment, "commitment");
        assertEq(storedCollateral, collateral, "collateral");
        assertEq(
            auction.getAuction(address(erc721), TOKEN_ID).numUnrevealedBids,
            numUnrevealedBids,
            "numUnrevealedBids"
        );
    }
}
