// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {ERC20,ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


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
contract DSCEngine{

    /////////// errors ////////////////

   error DecentralizedStableCoin_AmountMustBeMoreThanZero();

    /////////// modifiers ///////////////// 

    modifier moreThanZero (uint256 amount){
        if(amount<=0){
            revert DecentralizedStableCoin_AmountMustBeMoreThanZero();
        }
        _;
    }

    /////////// constructor ///////////////// 

    constructor(){
        
    }


    /////////// Functions ///////////////// 

    function depositCollateralAndMintDsc () external {}

    /**
     *  @param tokenColleteralAddress the address of the token to deposit as collateral
     *  @param amountCollateral the amount of collateral to deposit 
     */
    function depositCollateral(address tokenColleteralAddress, uint256 amountCollateral)  external  moreThanZero(amountCollateral) {

    }

    function redeemCollateralForDsc() external{}

    function redeemCollateral()  external{}

    function mintDsc () external {}

    function burnDsc () external{}

    function liquidate() external{}

    function getHealtheFactor () external view{}

}