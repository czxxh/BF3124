// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/ERC20.sol";
/// @title Mock tokenised SGD deposit (test money only)
/// @notice Stands in for the partner bank's tokenised deposits from the press release.
///         Anyone can mint test funds with faucet(). Never use this on a real network.


/// S$1,000,000 per call, written in cents because this token has 2 decimals.
    /// Generous on purpose: one test wallet can stand in for many investors.
contract MockSGD is ERC20{
    uint256 public constant FAUCET_AMOUNT = 1_000_000*100;
    constructor() ERC20("Mock Tokenised SGD Deposti", "mSGD"){}
    function decimals() public pure override returns (uint8){
    /// Like the Singapore dollar, 1 mSGD = 100 cents.
        return 2;
    }

    /// gives the caller $1,000,000 of test money.
    function faucet() external {
        _mint(msg.sender, FAUCET_AMOUNT);
    }

}