// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralisedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/helperConfig.s.sol";

contract DSCEngineTest is Test {
    ///errors///
    error DSCEngine_AmountMustBeMoreThanZero();

    DSCEngine public dscEngine;
    DecentralisedStableCoin public dsc;
    DeployDSC public deployDSC;
    HelperConfig public config;
    address ethUsdPriceFeed;
    address weth;

    address USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ER20_BALANCE = 10 ether;

    function setUp() public {
        deployDSC = new DeployDSC();
        (dsc, dscEngine, config) = deployDSC.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
    }

    function testDSCEngine() public {
        assertEq(dsc.owner(), address(dscEngine));
    }

    function testGetUsdValue() public {
        uint256 ethPrice = 2000;
        uint256 ethAmount = 10e18;
        uint256 excpectedUsdValue = ethPrice * ethAmount; //2e22
        uint256 actualUsdValue = dscEngine.getTokensPriceInUSD(weth, ethAmount);
        assertEq(actualUsdValue, excpectedUsdValue);
    }

    function testDepositCollateralZeroShouldRevert() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine_AmountMustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
