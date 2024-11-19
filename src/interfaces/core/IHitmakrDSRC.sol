// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC721} from "openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

/**
 * @title IHitmakrDSRC
 * @author Hitmakr Protocol
 * @notice Interface for the Decentralized Standard Recording Code (DSRC) contract
 */
interface IHitmakrDSRC is IERC721, IERC2981 {
    /**
     * @notice Represents how royalties are split among recipients
     */
    struct RoyaltySplit {
        address recipient;
        uint16 percentage;
    }

    /**
     * @notice Tracks various types of earnings
     */
    struct Earnings {
        uint96 purchase;
        uint96 royalty;
        uint64 pending;
    }

    /**
     * @notice Custom errors for the DSRC contract
     */
    error AlreadyPurchased();
    error TransferFailed();
    error Unauthorized();
    error TransferNotAllowed();
    error InvalidPercentages();
    error NoRoyaltiesToDistribute();
    error NotPrimaryChain();
    error InvalidChainParam();
    error ZeroAddress();

    /**
     * @notice Emitted when a DSRC is purchased
     * @param buyer Address of the purchaser
     * @param amount Purchase amount in payment tokens
     * @param selectedChain The blockchain where purchase occurred
     */
    event Purchased(address indexed buyer, uint256 amount, string selectedChain);
    
    /**
     * @notice Emitted when DSRC price is updated
     * @param newPrice Updated price in payment tokens
     */
    event PriceUpdated(uint256 newPrice);
    
    /**
     * @notice Emitted when royalties are received
     * @param amount Amount of royalties received
     */
    event RoyaltyReceived(uint256 amount);
    
    /**
     * @notice Emitted when royalties are distributed to a recipient
     * @param recipient Address receiving the royalty
     * @param amount Amount distributed
     * @param isPurchaseEarning Whether distribution is from purchase or royalty
     */
    event RoyaltyDistributed(
        address indexed recipient,
        uint256 amount,
        bool isPurchaseEarning
    );
    
    /**
     * @notice Emitted when all royalties are distributed
     * @param totalAmount Total amount distributed
     * @param isPurchaseEarning Whether distribution is from purchase or royalty
     */
    event RoyaltiesDistributed(uint256 totalAmount, bool isPurchaseEarning);

    /**
     * @notice Allows purchase of the DSRC
     */
    function purchase() external;

    /**
     * @notice Processes received royalties
     */
    function onRoyaltyReceived() external;

    /**
     * @notice Distributes pending earnings to recipients
     * @param distributeType 0 for purchase, 1 for royalty, 2 for larger amount
     */
    function distributeRoyalties(uint8 distributeType) external;

    /**
     * @notice Updates the DSRC price
     * @param newPrice New price in payment tokens
     */
    function updatePrice(uint256 newPrice) external;

    /**
     * @notice Returns detailed earnings information
     * @return purchaseEarnings Total earnings from primary sales
     * @return royaltyEarnings Total earnings from royalties
     * @return pendingAmount Amount pending distribution
     * @return totalEarnings Combined total of all earnings
     */
    function getEarningsInfo() external view returns (
        uint256 purchaseEarnings,
        uint256 royaltyEarnings,
        uint256 pendingAmount,
        uint256 totalEarnings
    );

    /**
     * @notice Gets the selected blockchain for this DSRC
     * @return The selected blockchain identifier
     */
    function getSelectedChain() external view returns (string memory);

    /**
     * @notice Gets the primary blockchain identifier
     * @return The primary blockchain identifier (SKL)
     */
    function getPrimaryChain() external pure returns (string memory);

    /**
     * @notice Gets the current royalty split configuration
     * @return Array of RoyaltySplit structs
     */
    function getRoyaltySplits() external view returns (RoyaltySplit[] memory);

    /**
     * @notice Gets DSRC identifier
     * @return The unique DSRC identifier
     */
    function dsrcId() external view returns (string memory);

    /**
     * @notice Gets DSRC creator address
     * @return The address of the DSRC creator
     */
    function creator() external view returns (address);

    /**
     * @notice Gets payment token address
     * @return The address of the ERC20 payment token
     */
    function paymentToken() external view returns (address);

    /**
     * @notice Gets current DSRC price
     * @return The current price in payment tokens
     */
    function price() external view returns (uint256);

    /**
     * @notice Gets earnings information
     * @return The Earnings struct containing all earnings data
     */
    function earnings() external view returns (Earnings memory);

    /**
     * @notice Checks if an address has purchased this DSRC
     * @param user Address to check
     * @return Whether the address has purchased
     */
    function hasPurchased(address user) external view returns (bool);
}