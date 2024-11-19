// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IHitmakrDSRCPurchaseIndexer
 * @author Hitmakr Protocol
 * @notice Interface for the DSRC Purchase Indexer contract that tracks and manages purchase records
 * @dev This interface defines the core functionality for indexing and querying DSRC purchases
 */
interface IHitmakrDSRCPurchaseIndexer {
    /**
     * @notice Structure representing a single DSRC purchase
     * @dev Optimized for storage efficiency using packed storage
     * @param dsrcAddress The contract address of the purchased DSRC
     * @param dsrcId The unique identifier of the DSRC
     * @param timestamp The purchase timestamp (uint40 allows dates until year 2104)
     * @param price The purchase price (uint216 allows for large amounts)
     */
    struct Purchase {
        address dsrcAddress;
        string dsrcId;
        uint40 timestamp;
        uint216 price;
    }

    /**
     * @notice Structure containing aggregated statistics for a user's purchases
     * @dev Uses packed storage for gas efficiency
     * @param totalPurchases Total number of DSRCs purchased by the user
     * @param firstPurchaseTime Timestamp of user's first purchase
     * @param lastPurchaseTime Timestamp of user's most recent purchase
     * @param totalAmountSpent Total amount spent on DSRC purchases
     */
    struct UserStats {
        uint32 totalPurchases;
        uint40 firstPurchaseTime;
        uint40 lastPurchaseTime;
        uint144 totalAmountSpent;
    }

    /**
     * @dev Custom errors for the interface
     */
    /// @notice Thrown when attempting to interact with an invalid DSRC contract
    error InvalidDSRC();
    /// @notice Thrown when attempting to index an already indexed purchase
    error AlreadyIndexed();
    /// @notice Thrown when caller lacks necessary permissions
    error Unauthorized();
    /// @notice Thrown when a zero address is provided where it's not allowed
    error ZeroAddress();
    /// @notice Thrown when attempting to set factory address that's already set
    error FactoryAlreadySet();

    /**
     * @notice Emitted when a new purchase is indexed
     * @param buyer Address of the DSRC buyer
     * @param dsrcAddress Address of the purchased DSRC contract
     * @param dsrcId Unique identifier of the DSRC
     * @param timestamp Time of purchase
     * @param price Purchase price
     */
    event PurchaseIndexed(
        address indexed buyer,
        address indexed dsrcAddress,
        string dsrcId,
        uint40 timestamp,
        uint216 price
    );

    /**
     * @notice Initializes the factory address for the indexer
     * @dev Can only be set once
     * @param _factory Address of the DSRC factory contract
     */
    function initializeFactory(address _factory) external;

    /**
     * @notice Registers a new DSRC contract in the indexer
     * @param dsrc Address of the DSRC contract to register
     */
    function registerDSRC(address dsrc) external;

    /**
     * @notice Indexes a new DSRC purchase
     * @param buyer Address of the buyer
     * @param dsrcId Unique identifier of the purchased DSRC
     * @param price Purchase price
     */
    function indexPurchase(
        address buyer,
        string calldata dsrcId,
        uint256 price
    ) external;

    /**
     * @notice Retrieves purchase statistics for a specific user
     * @param user Address of the user
     * @return totalPurchases Number of DSRCs purchased
     * @return totalAmountSpent Total amount spent on purchases
     * @return firstPurchaseTime Timestamp of first purchase
     * @return lastPurchaseTime Timestamp of most recent purchase
     */
    function getUserStats(address user) external view returns (
        uint256 totalPurchases,
        uint256 totalAmountSpent,
        uint256 firstPurchaseTime,
        uint256 lastPurchaseTime
    );

    /**
     * @notice Retrieves paginated purchase history for a user
     * @param user Address of the user
     * @param offset Starting index for pagination
     * @param limit Maximum number of records to return
     * @return purchases Array of Purchase structs
     * @return total Total number of purchases for the user
     * @return stats User's purchase statistics
     */
    function getUserPurchases(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (
        Purchase[] memory purchases,
        uint256 total,
        UserStats memory stats
    );

    /**
     * @notice Checks if a user has purchased a specific DSRC
     * @param user Address of the user
     * @param dsrc Address of the DSRC contract
     * @return bool True if the user has purchased the DSRC
     */
    function checkUserPurchase(address user, address dsrc) external view returns (bool);

    /**
     * @notice Validates if an address is a legitimate DSRC contract
     * @param dsrc Address to validate
     * @return bool True if the address is a valid DSRC contract
     */
    function isValidDSRCContract(address dsrc) external view returns (bool);
    
    /**
     * @notice Retrieves global purchase statistics
     * @return totalPurchases Total number of DSRC purchases across all users
     * @return totalActiveBuyers Total number of unique buyers
     */
    function getGlobalStats() external view returns (uint256 totalPurchases, uint256 totalActiveBuyers);

    /**
     * @notice Checks if a user is an active buyer (has made at least one purchase)
     * @param user Address of the user to check
     * @return bool True if the user is an active buyer
     */
    function isUserActiveBuyer(address user) external view returns (bool);

    /**
     * @notice Returns the address of the control center contract
     * @return address Control center contract address
     */
    function controlCenter() external view returns (address);

    /**
     * @notice Returns the address of the DSRC factory contract
     * @return address Factory contract address
     */
    function factory() external view returns (address);

    /**
     * @notice Returns the total number of DSRC purchases globally
     * @return uint64 Total number of purchases
     */
    function totalPurchasesGlobal() external view returns (uint64);

    /**
     * @notice Returns the total number of active buyers
     * @return uint64 Number of active buyers
     */
    function activeBuyersCount() external view returns (uint64);

    /**
     * @notice Checks if a given address is a valid DSRC contract
     * @param dsrc Address to check
     * @return bool True if the address is a valid DSRC
     */
    function isValidDSRC(address dsrc) external view returns (bool);
}