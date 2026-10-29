// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.0.2/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts@5.0.2/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts@5.0.2/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts@5.0.2/utils/math/Math.sol";

interface IKYCRegistry {
    function isApproved(address wallet) external view returns (bool);
}

/// @title Revenue rights token for one research project
/// @notice Lifecycle: Offering -> (closeOffering) -> Funded or Failed.
///         - Offering: KYC-approved investors buy tokens; their mSGD is held here (escrow).
///         - Funded:   the raise met the minimum, so the money went to the university.
///                     The university records revenue, holders claim, approved wallets can trade.
///         - Failed:   the raise missed the minimum, so every investor can refund().
///         Every revenue payment is split by a fixed 100,000 tokens. The share belonging
///         to unsold tokens is never paid in, so it stays with the university.
contract RevenueRightsToken is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Phase {
        Offering,
        Funded,
        Failed
    }

    uint256 public constant TOTAL_TOKENS = 100_000;
    uint256 public constant MIN_PURCHASE = 50; // 50 tokens x S$10 = S$500
    uint256 private constant PRECISION = 1e18; // extra precision for the per-token running total

    IERC20 public immutable msgd;
    IKYCRegistry public immutable kyc;
    address public immutable university;
    uint256 public immutable price; // mSGD cents per token
    uint256 public immutable minRaise; // mSGD cents
    uint256 public immutable investorShareBps; // basis points: 3000 = 30%
    uint256 public immutable deadline; // unix timestamp

    Phase public phase;

    /// Running total of mSGD cents earned per token since the start, times PRECISION.
    uint256 public accPerToken;
    uint256 public totalRevenueRecorded; // gross revenue the university reported, in cents
    uint256 public totalPaidToInvestors; // cents paid into this contract for holders

    /// Payouts already worked out for a wallet but not yet claimed.
    mapping(address => uint256) public credited;
    /// Each wallet's bookmark of accPerToken at its last settlement.
    mapping(address => uint256) public paidPerToken;

    event Bought(address indexed investor, uint256 tokens, uint256 cost);
    event OfferingClosed(Phase result, uint256 raised);
    event Refunded(address indexed investor, uint256 tokens, uint256 amount);
    event RevenueRecorded(uint256 grossRevenue, uint256 investorPool, uint256 paidIn, string note);
    event Claimed(address indexed investor, uint256 amount);

    /// @param priceSGD       price per token in whole dollars, e.g. 10
    /// @param minRaiseSGD    minimum raise in whole dollars, e.g. 500000
    /// @param shareBps       holders' share of revenue in basis points, e.g. 3000 for 30%
    /// @param offeringDays   how long the offering stays open, e.g. 30
    constructor(
        string memory projectName,
        string memory symbol,
        address msgdAddress,
        address kycAddress,
        address universityWallet,
        uint256 priceSGD,
        uint256 minRaiseSGD,
        uint256 shareBps,
        uint256 offeringDays
    ) ERC20(projectName, symbol) Ownable(msg.sender) {
        require(shareBps <= 10_000, "Share cannot exceed 100%");
        require(minRaiseSGD <= TOTAL_TOKENS * priceSGD, "Minimum is above the full raise");
        msgd = IERC20(msgdAddress);
        kyc = IKYCRegistry(kycAddress);
        university = universityWallet;
        price = priceSGD * 100;
        minRaise = minRaiseSGD * 100;
        investorShareBps = shareBps;
        deadline = block.timestamp + offeringDays * 1 days;
    }

    /// Tokens are whole units: you can't own half a token.
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    /// Tokens only exist once bought, so total supply = tokens sold.
    function amountRaised() public view returns (uint256) {
        return totalSupply() * price;
    }

    // ---------------------------------------------------------------- offering

    /// Buy tokens. Approve this contract to spend your mSGD first.
    function buy(uint256 tokens) external nonReentrant {
        require(phase == Phase.Offering, "Offering is closed");
        require(block.timestamp <= deadline, "Offering period has ended");
        require(kyc.isApproved(msg.sender), "Wallet is not KYC-approved");
        require(tokens >= MIN_PURCHASE, "Minimum purchase is 50 tokens");
        require(totalSupply() + tokens <= TOTAL_TOKENS, "Not enough tokens left");

        uint256 cost = tokens * price;
        msgd.safeTransferFrom(msg.sender, address(this), cost);
        _mint(msg.sender, tokens);
        emit Bought(msg.sender, tokens, cost);
    }

    /// Ends the offering. The admin can close early (useful for demos);
    /// after the deadline anyone can close it.
    function closeOffering() external nonReentrant {
        require(phase == Phase.Offering, "Offering already closed");
        require(msg.sender == owner() || block.timestamp > deadline, "Only the admin can close before the deadline");

        uint256 raised = amountRaised();
        if (raised >= minRaise) {
            phase = Phase.Funded;
            msgd.safeTransfer(university, raised);
        } else {
            phase = Phase.Failed;
        }
        emit OfferingClosed(phase, raised);
    }

    /// If the minimum wasn't met, investors get all their money back.
    function refund() external nonReentrant {
        require(phase == Phase.Failed, "Refunds are only open if the raise failed");
        uint256 tokens = balanceOf(msg.sender);
        require(tokens > 0, "Nothing to refund");

        uint256 amount = tokens * price;
        _burn(msg.sender, tokens);
        msgd.safeTransfer(msg.sender, amount);
        emit Refunded(msg.sender, tokens, amount);
    }

    // ---------------------------------------------------------------- revenue

    /// The university reports revenue it received off-chain and pays in the holders' share.
    /// Approve this contract to spend your mSGD first (see owedFor()).
    /// @param grossAmount total revenue received, in mSGD cents
    /// @param note        a short label, e.g. "Licence fee from SolarCo"
    function recordRevenue(uint256 grossAmount, string calldata note) external nonReentrant {
        require(msg.sender == university, "Only the university can record revenue");
        require(phase == Phase.Funded, "Project is not funded");
        require(grossAmount > 0, "Revenue must be above zero");

        (uint256 investorPool, uint256 increment, uint256 owed) = _split(grossAmount);
        accPerToken += increment;
        totalRevenueRecorded += grossAmount;
        totalPaidToInvestors += owed;

        msgd.safeTransferFrom(msg.sender, address(this), owed);
        emit RevenueRecorded(grossAmount, investorPool, owed, note);
    }

    /// How much the university must pay in for a given gross revenue (for the website).
    function owedFor(uint256 grossAmount) external view returns (uint256) {
        (,, uint256 owed) = _split(grossAmount);
        return owed;
    }

    /// Payout waiting for a wallet.
    function claimable(address account) public view returns (uint256) {
        return credited[account] + balanceOf(account) * (accPerToken - paidPerToken[account]) / PRECISION;
    }

    function claim() external nonReentrant {
        _settle(msg.sender);
        uint256 amount = credited[msg.sender];
        require(amount > 0, "Nothing to claim");

        credited[msg.sender] = 0;
        msgd.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }

    // ---------------------------------------------------------------- internals

    /// investorPool = gross x share. Each token earns investorPool / 100,000.
    /// The university only pays in the share of tokens that were actually sold,
    /// rounded up so the contract can always cover every claim.
    function _split(uint256 grossAmount)
        internal
        view
        returns (uint256 investorPool, uint256 increment, uint256 owed)
    {
        investorPool = grossAmount * investorShareBps / 10_000;
        increment = investorPool * PRECISION / TOTAL_TOKENS;
        owed = Math.mulDiv(increment, totalSupply(), PRECISION, Math.Rounding.Ceil);
    }

    /// Locks in what a wallet has earned so far, before its balance changes.
    function _settle(address account) internal {
        credited[account] = claimable(account);
        paidPerToken[account] = accPerToken;
    }

    /// Runs on every mint, burn and transfer.
    function _update(address from, address to, uint256 value) internal override {
        bool isTransfer = from != address(0) && to != address(0);
        if (isTransfer) {
            require(phase == Phase.Funded, "Trading opens once the project is funded");
            require(kyc.isApproved(from), "Sender is not KYC-approved");
            require(kyc.isApproved(to), "Receiver is not KYC-approved");
        }
        if (from != address(0)) _settle(from);
        if (to != address(0)) _settle(to);
        super._update(from, to, value);
    }
}
