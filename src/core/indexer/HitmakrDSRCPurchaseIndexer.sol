// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../interfaces/core/IHitmakrDSRCFactory.sol";

/**
 * @title HitmakrDSRCPurchaseIndexer
 * @author Hitmakr Protocol
 * @notice This contract indexes and tracks DSRC (Decentralized Standard Recording Code) purchases, providing
 * a record of every purchase and aggregating user statistics.  It's designed to work with the HitmakrDSRC
 * contracts, ensuring that only purchases from valid DSRC contracts are indexed. This contract facilitates data
 * analysis and reporting on DSRC sales and user behavior.  It provides functions to index purchases, retrieve
 * user purchase history and statistics, check purchase status, and access global purchase data.
 */
contract HitmakrDSRCPurchaseIndexer {

    /**
     * @notice Represents a single DSRC purchase.
     * @member dsrcAddress The address of the purchased DSRC contract.
     * @member dsrcId A unique identifier for the DSRC within its contract.
     * @member timestamp The timestamp of the purchase.
     * @member price The price paid for the DSRC (can be 0 for free DSRCs).
     */
    struct Purchase {
        address dsrcAddress;
        string dsrcId;
        uint256 timestamp;
        uint256 price;
    }

    /**
     * @notice Stores statistics about a user's DSRC purchases.
     * @member totalPurchases The total number of DSRCs purchased by the user.
     * @member totalAmountSpent The total amount spent on DSRC purchases by the user (excluding free DSRCs).
     * @member firstPurchaseTime The timestamp of the user's first DSRC purchase.
     * @member lastPurchaseTime The timestamp of the user's most recent DSRC purchase.
     */
    struct UserStats {
        uint256 totalPurchases;
        uint256 totalAmountSpent;
        uint256 firstPurchaseTime;
        uint256 lastPurchaseTime;
    }

    /**
     * @notice The address of the DSRC factory contract.
     * @dev Used for validating DSRC contract addresses and ensuring that only purchases from valid DSRCs are indexed.
     */
    address public factory;

    /**
     * @dev Interface for interacting with the DSRC factory contract to verify DSRC validity.
     */
    IHitmakrDSRCFactory private factoryContract;

    /**
     * @notice The address of the contract administrator.
     * @dev Has permission to update the factory address and the admin address itself.
     */
    address public admin;
    
    /*
     * Mappings to store purchase data and user statistics.
     */

    /// @dev Mapping of user addresses to their purchase history (an array of `Purchase` structs).
    mapping(address => Purchase[]) private userPurchases;
    
    /// @dev Mapping to track whether a user has purchased a specific DSRC. Prevents duplicate purchase entries.
    mapping(address => mapping(address => bool)) private hasPurchased;

    /// @dev Mapping of user addresses to their purchase statistics (`UserStats` struct).
    mapping(address => UserStats) private userStats;
    
    /// @dev Mapping to track if a user is an active buyer (has purchased at least once).
    mapping(address => bool) private isActiveBuyer;


    /// @dev Total number of DSRC purchases across all users.
    uint256 public totalPurchasesGlobal;
    
    /// @dev Count of active buyers (users who have made at least one purchase).
    uint256 public activeBuyersCount;

    /*
     * Events emitted by the contract. These events provide a record of purchases, factory updates, and admin
     * changes. Indexed parameters allow for efficient filtering of events.
     */

    event PurchaseIndexed(
        address indexed buyer,
        address indexed dsrcAddress,
        string dsrcId,
        uint256 timestamp,
        uint256 price
    );
    
    event FactoryUpdated(address indexed oldFactory, address indexed newFactory);
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);


    /*
     * Custom errors for specific revert reasons, improving debugging and user experience.
     */
    error InvalidDSRC();
    error AlreadyIndexed();
    error Unauthorized();
    error ZeroAddress();

    /*
     * Modifier to restrict access to specific functions to only the contract administrator.
     */
    modifier onlyAdmin() {
        if(msg.sender != admin) revert Unauthorized();
        _;
    }

    /**
     * @notice Constructor initializes the contract and sets the initial administrator address.
     * @param _admin The address of the initial administrator. Cannot be the zero address.
     */
    constructor(address _admin) {
        if(_admin == address(0)) revert ZeroAddress();
        admin = _admin;
    }

    /**
     * @notice Updates the address of the DSRC factory contract.  This is a critical function as it
     * determines which DSRC contracts are considered valid for indexing purchases.
     * @param newFactory The address of the new DSRC factory contract. Cannot be the zero address.
     * @dev Emits a `FactoryUpdated` event.
     * Requirements: Only callable by the contract admin.
     */
    function updateFactory(address newFactory) external onlyAdmin {
        if(newFactory == address(0)) revert ZeroAddress();
        address oldFactory = factory;
        factory = newFactory;
        factoryContract = IHitmakrDSRCFactory(newFactory);
        emit FactoryUpdated(oldFactory, newFactory);
    }

    /**
     * @notice Updates the contract administrator address.
     * @param newAdmin The address of the new administrator. Cannot be the zero address.
     * @dev Emits an `AdminUpdated` event.
     * Requirements: Only callable by the current contract admin.
     */
    function updateAdmin(address newAdmin) external onlyAdmin {
        if(newAdmin == address(0)) revert ZeroAddress();
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminUpdated(oldAdmin, newAdmin);
    }

    /**
     * @notice Indexes a new DSRC purchase. This function should be called by a valid DSRC contract after a
     * successful purchase.  It records the purchase details and updates user statistics.
     * @param buyer The address of the user who purchased the DSRC.
     * @param dsrcId The ID of the purchased DSRC.
     * @param price The price paid for the DSRC (can be 0 for free DSRCs).
     * @dev Emits a `PurchaseIndexed` event. Updates relevant mappings to track purchase history and statistics.
     * Requirements:
     * - Can only be called by a valid DSRC contract (verified using the `factory` address).
     * - The purchase must not have already been indexed for this buyer and DSRC.
     */
    function indexPurchase(
        address buyer,
        string calldata dsrcId,
        uint256 price
    ) external {
        if (!isValidDSRC(msg.sender)) revert InvalidDSRC();
        if (hasPurchased[buyer][msg.sender]) revert AlreadyIndexed();

        Purchase memory purchase = Purchase({
            dsrcAddress: msg.sender,
            dsrcId: dsrcId,
            timestamp: block.timestamp,
            price: price  // Store the price even if it's 0
        });

        userPurchases[buyer].push(purchase);
        hasPurchased[buyer][msg.sender] = true;

        UserStats storage stats = userStats[buyer];
        stats.totalPurchases++;
        
        // Update totalAmountSpent only if price > 0 to avoid unnecessary state changes
        if (price > 0) {
            stats.totalAmountSpent += price;
        }
        
        // Update first purchase time regardless of price
        if (stats.firstPurchaseTime == 0) {
            stats.firstPurchaseTime = block.timestamp;
            if (!isActiveBuyer[buyer]) {
                isActiveBuyer[buyer] = true;
                activeBuyersCount++;
            }
        }

        stats.lastPurchaseTime = block.timestamp;
        totalPurchasesGlobal++;

        emit PurchaseIndexed(
            buyer,
            msg.sender,
            dsrcId,
            block.timestamp,
            price  // Emit the price even if it's 0
        );
    }

    /**
     * @notice Retrieves the purchase statistics for a given user.
     * @param user The address of the user whose statistics are being retrieved.
     * @return The `UserStats` struct containing the user's purchase statistics.
     */
    function getUserStats(address user) external view returns (UserStats memory) {
        return userStats[user];
    }

    /**
     * @notice Retrieves a paginated list of a user's DSRC purchases.  Pagination is used to handle potentially
     * large purchase histories efficiently.
     * @param user The address of the user whose purchases are being retrieved.
     * @param offset The starting index for pagination (0-indexed).
     * @param limit The maximum number of purchases to return in a single call.
     * @return purchases An array of `Purchase` structs representing the retrieved purchases.
     * @return total The total number of purchases made by the user.
     * @return stats The `UserStats` struct for the user.
     */
    function getUserPurchases(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (
        Purchase[] memory purchases,
        uint256 total,
        UserStats memory stats
    ) {
        uint256 totalUserPurchases = userStats[user].totalPurchases;
        if (offset >= totalUserPurchases) {
            return (new Purchase[](0), totalUserPurchases, userStats[user]);
        }

        uint256 remaining = totalUserPurchases - offset;
        uint256 count = remaining < limit ? remaining : limit;
        
        purchases = new Purchase[](count);
        for (uint256 i = 0; i < count; i++) {
            purchases[i] = userPurchases[user][offset + i];
        }

        return (purchases, totalUserPurchases, userStats[user]);
    }

    /**
     * @notice Checks if a user has already purchased a specific DSRC.  Useful for preventing duplicate
     * purchases or for displaying ownership status.
     * @param user The address of the user.
     * @param dsrc The address of the DSRC contract.
     * @return True if the user has purchased the specified DSRC, false otherwise.
     */
    function checkUserPurchase(address user, address dsrc) external view returns (bool) {
        return hasPurchased[user][dsrc];
    }

    /**
     * @notice Checks if a given address represents a valid, deployed DSRC contract.  This function is crucial for
     * security and ensures that only legitimate DSRCs can interact with the indexer.
     * @param dsrc The address to check.
     * @return True if the address is a valid DSRC, false otherwise.
     * @dev Uses the `factoryContract` to verify the DSRC's validity.
     */
    function isValidDSRC(address dsrc) public view returns (bool) {
        if (factory == address(0)) return false; // Handle the case where factory is not set yet.
        return factoryContract.isValidDSRC(dsrc);
    }
    
    /**
     * @notice Retrieves global DSRC purchase statistics. Provides an overview of total purchases and the number
     * of active buyers.
     * @return totalPurchases The total number of DSRC purchases indexed.
     * @return totalActiveBuyers The total number of unique users who have purchased at least one DSRC.
     */
    function getGlobalStats() external view returns (uint256 totalPurchases, uint256 totalActiveBuyers) {
        return (totalPurchasesGlobal, activeBuyersCount);
    }

    /**
     * @notice Checks if a user is considered an active buyer (has made at least one DSRC purchase).
     * @param user The address of the user to check.
     * @return True if the user is an active buyer, false otherwise.
     */
    function isUserActiveBuyer(address user) external view returns (bool) {
        return isActiveBuyer[user];
    }
}