// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralisedStableCoin} from "src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";
/**
 * @title DSCEngine
 * @author dhanesh
 *
 * this is system will maintain a 1token == 1 doller PEG
 *
 * PROPERTIES:
 *  exogenous collateral
 *  doller pegged
 *  algoritmically stable
 *
 * similar to DAI - if only backed by WETH and WBTC , no governance , no fee
 *
 * DSC system should be over collaetalirised,   all collateral >= $backed value of all colletaral
 * @notice this contract is the core of DSC system. handles , depositing ,withdrawing collateral. mining ,reedemeing stabel coins,
 *
 */

contract DSCEngine {
    /////////// errors ////////////////

    error DSCEngine_AmountMustBeMoreThanZero();
    error DSCEngine_tokenAddressAreNotMatchingPriceFeeds();
    error DSCEngine_tokenNotAllowed();
    error DSCEngine_transactionFailed();
    error DSCEngine_lowHealthFactor();
    error DSCEngine_mintFailed();

    /////////// state variables /////////////////
    mapping(address token => address pricefeed) s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] s_collateralTokens;
    DecentralisedStableCoin private immutable i_dsc;
    uint256 constant THRESHOLD_PERCENTAGE = 50;

    /////////// events /////////////////
    event CollateralDeposited(address user, address token, uint256 amount);

    /////////// modifiers /////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine_AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier isTokenAllowed(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine_tokenNotAllowed();
        }
        _;
    }

    modifier hasSufficientCollateral(address tokenColleteralAddress, uint256 amountDSC) {
        require(s_collateralDeposited[msg.sender][tokenColleteralAddress] >= amountDSC, "Insufficient collateral");
        _;
    }

    modifier cantMintLessThanZero(uint256 amountDSC) {
        require(amountDSC > 0, "Cannot mint less than zero");
        _;
    }
    /////////// constructor /////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_tokenAddressAreNotMatchingPriceFeeds();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            console.log(i);
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    /////////// Functions /////////////////

    function depositCollateralAndMintDsc() external {}

    /**
     *  @param tokenColleteralAddress the address of the token to deposit as collateral
     *  @param amountCollateral the amount of collateral to deposit (  will be in wei by default ) ex: 100000 wei is deposited as collateral
     */
    function depositCollateral(address tokenColleteralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isTokenAllowed(tokenColleteralAddress)
    {
        s_collateralDeposited[msg.sender][tokenColleteralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenColleteralAddress, amountCollateral);

        (bool success) = IERC20(tokenColleteralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine_transactionFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}
    /**
     * checks :
     *
     *  if collateral is there
     *  check its value
     *  allow to mint less than it
     * we assume that we store amountDSC for DSC coin in 18Decimals (similar to wei in ether) 
     */

    function mintDsc(uint256 amountDSC)
        external
        hasSufficientCollateral(msg.sender, amountDSC)
        cantMintLessThanZero(amountDSC)
    {
        revertIfHealthFactorIsBroken(msg.sender);
        s_DSCMinted[msg.sender] += amountDSC;
        bool minted = i_dsc.mint(msg.sender, amountDSC);
        if (!minted) {
            revert DSCEngine_mintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealtheFactor() external view {}

    ////// Private Functions ////////

    /**
     * @param user address of the user
     * @dev calls the _healthFactor function to check health
     * should check the health factor and return if health factor is low
     */
    function revertIfHealthFactorIsBroken(address user) internal view {
        if (_healthFactor(user) < 1) {
            revert DSCEngine_lowHealthFactor();
        }
    }

    /**
     *
     * Returns how close to liquidation a user is
     */
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalDSCMinted, uint256 totalCollateralInUSD) = _getAccountInformation(user);
        uint256 collateralAdjestedForThreshold = totalCollateralInUSD * THRESHOLD_PERCENTAGE / 100;
        uint256 healthFactor = (collateralAdjestedForThreshold) / totalDSCMinted;
        console.log(healthFactor);
        return healthFactor;
    }

    /**
     *
     * @return totalDSCMinted  total DSC coins minted by the user
     * @return totalCollateralInUSD total value of the collateral deposited by  the user  in dollers
     */
    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        totalCollateralInUSD = getAccoutCollateralValueInUSD(user);
        return (totalDSCMinted, totalCollateralInUSD);
    }

    /**
     *
     * @param user address of the user
     * @return totalAmount total collateral value in usd
     */
    function getAccoutCollateralValueInUSD(address user) public view returns (uint256 totalAmount) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amountDsc = s_collateralDeposited[user][token];
            uint256 amountUSD = getTokensPriceInUSD(token, amountDsc);
            totalAmount += amountUSD;
        }
        return totalAmount;
    }

    /**
     * @dev Returns the price of a token in USD.
     * @param token The address of the token.
     * @return The price of the token in USD.
     */
    function getTokensPriceInUSD(address token, uint256 amountDSC) public view returns (uint256) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (
            /* uint80 roundID */
            ,
            int256 answer,
            /*uint startedAt*/
            ,
            /*uint timeStamp*/
            ,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        //answer will be like 1eth = 2000*1e8  8 decimals
        //convert 8 decimal into 18 by multiplying with 1e10 (2000 *1e18) we will remove this 18 decimal by end
        // amountDSC will also be in wei ex:  10 *1e18 wei  18 decimals (10 eth)
        //10*1e18 * 2000*1e18 = 20000*1e18*1e18 = 20000*1e36
        // remove the 18 decimal by dividing by 1e18 -->20000*1e18 (wei) {this means 20000 dollers for 10 eth-- 1 eth = 2000 dollers} 
        uint256 amount = (uint256(answer) * 1e10 * amountDSC)/1e18;
        //amount will be in wei
        return (amount);
    }
}
