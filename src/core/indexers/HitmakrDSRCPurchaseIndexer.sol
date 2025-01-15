// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../interfaces/core/IHitmakrDSRCFactory.sol";

/**
* @title HitmakrDSRCPurchaseIndexer
* @author Hitmakr Protocol
* @notice This contract indexes and tracks DSRC purchases and user statistics.
* @dev This contract integrates with the DSRC factory to validate purchases and maintains purchase history and statistics.
*/
contract HitmakrDSRCPurchaseIndexer {
   /**
    * @notice Represents a single DSRC purchase
    * @dev Structure optimized for gas efficiency with uint64 timestamp
    * @param dsrcAddress The address of the purchased DSRC contract
    * @param dsrcId A unique identifier for the DSRC within its contract
    * @param timestamp The timestamp of the purchase
    * @param price The price paid for the DSRC
    */
   struct Purchase {
       address dsrcAddress;
       string dsrcId;
       uint64 timestamp;
       uint256 price;
   }

   /**
    * @notice Stores statistics about a user's DSRC purchases
    * @dev Structure optimized for gas efficiency with uint64 timestamps
    * @param totalPurchases The total number of DSRCs purchased by the user
    * @param totalAmountSpent The total amount spent on DSRC purchases by the user
    * @param firstPurchaseTime The timestamp of the user's first DSRC purchase
    * @param lastPurchaseTime The timestamp of the user's most recent DSRC purchase
    */
   struct UserStats {
       uint256 totalPurchases;
       uint256 totalAmountSpent;
       uint64 firstPurchaseTime;
       uint64 lastPurchaseTime;
   }

   /// @notice The address of the DSRC factory contract used for validation
   address public factory;
   /// @dev Interface for interacting with the DSRC factory contract
   IHitmakrDSRCFactory private factoryContract;
   /// @notice The address of the contract administrator
   address public admin;
   
   /// @notice Maps user addresses to their purchase history array
   mapping(address => Purchase[]) public userPurchases;
   /// @notice Tracks whether a user has purchased a specific DSRC
   mapping(address => mapping(address => bool)) public hasPurchased;
   /// @notice Maps user addresses to their aggregated purchase statistics
   mapping(address => UserStats) public userStats;
   /// @notice The total number of DSRC purchases across all users
   uint256 public totalPurchasesGlobal;
   /// @notice The total number of users who have made at least one purchase
   uint256 public activeBuyersCount;
   /// @notice Tracks whether a user is considered an active buyer
   mapping(address => bool) public isActiveBuyer;
   
   /**
    * @notice Emitted when a DSRC purchase is successfully indexed
    * @param buyer The address of the user who purchased the DSRC
    * @param dsrcAddress The address of the purchased DSRC contract
    * @param dsrcId The unique identifier of the purchased DSRC
    * @param timestamp When the purchase was indexed
    * @param price The amount paid for the DSRC
    */
   event PurchaseIndexed(
       address indexed buyer,
       address indexed dsrcAddress,
       string dsrcId,
       uint64 timestamp,
       uint256 price
   );
   
   /**
    * @notice Emitted when the DSRC factory address is updated
    * @param oldFactory The previous factory address
    * @param newFactory The new factory address
    */
   event FactoryUpdated(address indexed oldFactory, address indexed newFactory);

   /**
    * @notice Emitted when the admin address is updated
    * @param oldAdmin The previous admin address
    * @param newAdmin The new admin address
    */
   event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

   /// @notice Thrown when a DSRC contract is not recognized by the factory
   error InvalidDSRC();
   /// @notice Thrown when attempting to index an already indexed purchase
   error AlreadyIndexed();
   /// @notice Thrown when a non-admin attempts a restricted action
   error Unauthorized();
   /// @notice Thrown when zero address is provided for critical parameters
   error ZeroAddress();

   /// @notice Restricts function access to the contract admin
   modifier onlyAdmin() {
       if(msg.sender != admin) revert Unauthorized();
       _;
   }

   /**
    * @notice Initializes the contract with an admin address
    * @param _admin The address to be set as the initial admin
    */
   constructor(address _admin) {
       if(_admin == address(0)) revert ZeroAddress();
       admin = _admin;
   }

   /**
    * @notice Updates the DSRC factory contract address
    * @param newFactory The address of the new factory contract
    */
   function updateFactory(address newFactory) external onlyAdmin {
       if(newFactory == address(0)) revert ZeroAddress();
       address oldFactory = factory;
       factory = newFactory;
       factoryContract = IHitmakrDSRCFactory(newFactory);
       emit FactoryUpdated(oldFactory, newFactory);
   }

   /**
    * @notice Updates the contract admin address
    * @param newAdmin The address of the new admin
    */
   function updateAdmin(address newAdmin) external onlyAdmin {
       if(newAdmin == address(0)) revert ZeroAddress();
       address oldAdmin = admin;
       admin = newAdmin;
       emit AdminUpdated(oldAdmin, newAdmin);
   }

   /**
    * @notice Records a new DSRC purchase
    * @param buyer The address of the purchaser
    * @param dsrcId The unique identifier of the purchased DSRC
    * @param price The amount paid for the DSRC
    */
   function indexPurchase(
       address buyer,
       string calldata dsrcId,
       uint256 price
   ) external {
       if (!isValidDSRC(msg.sender)) revert InvalidDSRC();
       if (hasPurchased[buyer][msg.sender]) revert AlreadyIndexed();

       uint64 timestamp = uint64(block.timestamp);

       Purchase memory purchase = Purchase({
           dsrcAddress: msg.sender,
           dsrcId: dsrcId,
           timestamp: timestamp,
           price: price
       });

       userPurchases[buyer].push(purchase);
       hasPurchased[buyer][msg.sender] = true;

       UserStats storage stats = userStats[buyer];
       stats.totalPurchases++;
       
       if (price > 0) {
           stats.totalAmountSpent += price;
       }
       
       if (stats.firstPurchaseTime == 0) {
           stats.firstPurchaseTime = timestamp;
           if (!isActiveBuyer[buyer]) {
               isActiveBuyer[buyer] = true;
               activeBuyersCount++;
           }
       }
       stats.lastPurchaseTime = timestamp;

       totalPurchasesGlobal++;

       emit PurchaseIndexed(
           buyer,
           msg.sender,
           dsrcId,
           timestamp,
           price
       );
   }

   /**
    * @notice Retrieves a paginated list of a user's purchases
    * @param user The address of the user
    * @param offset Starting index for pagination
    * @param limit Maximum number of purchases to return
    * @return purchases Array of Purchase structs
    * @return total Total number of user's purchases
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
    * @notice Checks if an address is a valid DSRC contract
    * @param dsrc The address to check
    * @return bool True if the address is a valid DSRC contract
    */
   function isValidDSRC(address dsrc) public view returns (bool) {
       if (factory == address(0)) return false;
       return factoryContract.isValidDSRC(dsrc);
   }
   
   /**
    * @notice Retrieves global purchase statistics
    * @return totalPurchases Total number of purchases across all users
    * @return totalActiveBuyers Total number of unique buyers
    */
   function getGlobalStats() external view returns (uint256 totalPurchases, uint256 totalActiveBuyers) {
       return (totalPurchasesGlobal, activeBuyersCount);
   }
}