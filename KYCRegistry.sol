// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts@5.0.2/access/Ownable.sol";

/// @title KYC registry
/// @notice Meridian's list of wallets that passed KYC/AML onboarding.
///         Every project checks this list before letting a wallet buy or receive tokens.
contract KYCRegistry is Ownable {
    mapping(address => bool) public isApproved;

    event WalletApproved(address indexed wallet);
    event WalletRevoked(address indexed wallet);

    /// The wallet that deploys this contract becomes the Meridian admin.
    constructor() Ownable(msg.sender) {}

    function approveWallet(address wallet) external onlyOwner {
        isApproved[wallet] = true;
        emit WalletApproved(wallet);
    }

    function revokeWallet(address wallet) external onlyOwner {
        isApproved[wallet] = false;
        emit WalletRevoked(wallet);
    }
}
