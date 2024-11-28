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
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__HealthFactorOk();

        uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    /////////// state variables /////////////////
    mapping(address token => address pricefeed) s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] s_collateralTokens;
    DecentralisedStableCoin private immutable i_dsc;
    uint256 constant THRESHOLD_PERCENTAGE = 50;

    /////////// events /////////////////
    event CollateralDeposited(address user, address token, uint256 amount);
    event CollateralRedeemed(address user, address token, uint256 amount);

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

    /**
     * @dev Deposits collateral and mints DSC tokens.
     * @param tokenCollateralAddress The address of the collateral token.
     * @param amountCollateral The amount of collateral to deposit.
     * @param amountDSCMint The amount of DSC tokens to mint.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDSCMint);
    }

    /**
     *  @param tokenColleteralAddress the address of the token to deposit as collateral
     *  @param amountCollateral the amount of collateral to deposit (  will be in wei by default ) ex: 100000 wei is deposited as collateral
     */
    function depositCollateral(address tokenColleteralAddress, uint256 amountCollateral)
        public
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

    function redeemCollateralForDsc(address tokenColleteralAddress,uint256 amountCollateral) public {
        burnDsc(amountCollateral);
        redeemCollateral(tokenColleteralAddress,amountCollateral);
    }

    //health factor should be over 1 after colletral pulled 
    function redeemCollateral(address tokenColleteralAddress,uint256 amountCollateral) public moreThanZero(amountCollateral) {
        s_collateralDeposited[msg.sender][tokenColleteralAddress] -= amountCollateral;
        revertIfHealthFactorIsBroken(msg.sender);
        emit CollateralRedeemed(msg.sender, tokenColleteralAddress, amountCollateral);
        (bool success)=IERC20(tokenColleteralAddress).transfer(msg.sender, amountCollateral);
        if(!success){
            revert DSCEngine_transactionFailed();
        }

    }
    /**
     * checks :
     *
     *  if collateral is there
     *  check its value
     *  allow to mint less than it
     * we assume that we store amountDSC for DSC coin in 18Decimals (similar to wei in ether)
     */

    function mintDsc(uint256 amountDSC)
        public
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

    function burnDsc(uint256 amountDSC) public moreThanZero(amountDSC) {
         s_DSCMinted[msg.sender] -= amountDSC;
        (bool success) = i_dsc.transferFrom(msg.sender, address(this), amountDSC);
        i_dsc.burn(amountDSC);
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    )
        external
        isTokenAllowed(collateral)
        moreThanZero(debtToCover)
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // If covering 100 DSC, we need to $100 of collateral
        // uint256 tokenAmountFromDebtCovered = (collateral, debtToCover);
        // And give them a 1getTokenAmountFromUsd0% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        // uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // Burn DSC equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        // _redeemCollateral(collateral, tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        // _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

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
        uint256 amount = (uint256(answer) * 1e10 * amountDSC) / 1e18;
        //amount will be in wei
        return (amount);
    }

        function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }
}
