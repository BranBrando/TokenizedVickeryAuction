// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;
import {TokenizedVickeryAuction} from "../src/TokenizedVickeryAuction.sol";
import {TokenizedVickeryAuctionV2} from "../src/TokenizedVickeryAuctionV2.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BasicTransparentUpgradeProxyTest is Test {
    TokenizedVickeryAuction auctionV1;
    TokenizedVickeryAuctionV2 auctionV2;

	TransparentUpgradeableProxy proxyInstance;
    ProxyAdmin proxyAdmin;
    function setUp() public {
        auctionV1 = new TokenizedVickeryAuction();
        auctionV2 = new TokenizedVickeryAuctionV2();
    }

    function testCanUpgradeV1toV2() external {
        proxyAdmin = new ProxyAdmin(msg.sender);
        proxyInstance = new TransparentUpgradeableProxy(address(auctionV1), msg.sender, "");
        address proxyAddress = address(proxyInstance);
        uint256 proxy1Num = TokenizedVickeryAuction(proxyAddress).testNumber();
        hoax(msg.sender);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(proxyAddress), address(auctionV2), "");
        uint256 proxy2Num = TokenizedVickeryAuction(proxyAddress).testNumber();
        assertNotEq(proxy1Num, proxy2Num, "Proxy output number should not be the same");
    }

}
