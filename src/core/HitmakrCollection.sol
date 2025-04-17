// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/core/IHitmakrVerification.sol";
import "../interfaces/accesscontrol/IControlCenter.sol";
import "../interfaces/core/IHitmakrDSRCFactory.sol";
import "../interfaces/core/IHitmakrDSRC.sol";

/**
 * @title HitmakrCollection
 * @author Hitmakr Protocol
 * @notice Manages music collections (Albums/Mixtapes/Packs) for verified Hitmakr creators
 * @dev This contract allows verified creators to create and manage their music collections
 */
contract HitmakrCollection is ReentrancyGuard, Pausable {
    /// @notice Custom errors for gas optimization
    error UserNotVerified();
    error InvalidCollectionType();
    error InvalidCollectionName();
    error InvalidCollectionDescription();
    error ZeroAddress();
    error Unauthorized();
    error CollectionNotFound();
    error InvalidDsrcId();

    /// @notice Enum to define different types of collections
    enum CollectionType {
        Album,
        Mixtape,
        Pack
    }

    /// @notice Structure to store information about a Collection
    struct Collection {
        string name;
        string description;
        CollectionType collectionType;
        uint40 createdAt;
        bool exists;
        address[] dsrcAddresses; // Changed from string[] trackIds to address[] dsrcAddresses
        string coverArtUri; // IPFS URI for the cover art
    }

    /// @notice The HitmakrVerification contract used for checking user verification status
    IHitmakrVerification public immutable verificationContract;

    /// @notice The HitmakrDSRCFactory contract used for validating DSRCs
    IHitmakrDSRCFactory public immutable dsrcFactory;

    /// @notice Mapping from creator address to their collection IDs
    mapping(address => uint256[]) public creatorCollections;
    
    /// @notice Mapping from collection ID to Collection details
    mapping(uint256 => Collection) public collections;
    
    /// @notice Total number of collections created
    uint256 public totalCollections;

    /// @notice Events
    event CollectionCreated(
        uint256 indexed collectionId,
        address indexed creator,
        string name,
        CollectionType collectionType,
        uint40 timestamp
    );
    event DSRCAdded(uint256 indexed collectionId, address dsrcAddress); // Changed from TrackAdded
    event DSRCRemoved(uint256 indexed collectionId, address dsrcAddress); // Changed from TrackRemoved
    event CollectionUpdated(uint256 indexed collectionId);
    event EmergencyAction(bool paused);

    /// @notice Modifier that restricts access to only admin users
    modifier onlyAdmin() {
        IHitmakrControlCenter controlCenter = IHitmakrControlCenter(verificationContract.HITMAKR_CONTROL_CENTER());
        if (!AccessControl(address(controlCenter)).hasRole(controlCenter.ADMIN_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Constructor initializes the contract with the verification contract address
     * @param _verificationContract The address of the HitmakrVerification contract
     * @param _dsrcFactory The address of the HitmakrDSRCFactory contract
     */
    constructor(address _verificationContract, address _dsrcFactory) {
        if (_verificationContract == address(0) || _dsrcFactory == address(0)) revert ZeroAddress();
        verificationContract = IHitmakrVerification(_verificationContract);
        dsrcFactory = IHitmakrDSRCFactory(_dsrcFactory);
    }

    /**
     * @notice Creates a new collection for a verified creator
     * @param name The name of the collection
     * @param description The description of the collection
     * @param collectionType The type of collection (Album/Mixtape/Pack)
     * @param coverArtUri IPFS URI for the cover art
     * @return collectionId The ID of the created collection
     */
    function createCollection(
        string calldata name,
        string calldata description,
        CollectionType collectionType,
        string calldata coverArtUri
    ) 
        external
        whenNotPaused
        nonReentrant 
        returns (uint256 collectionId)
    {
        if (!verificationContract.verificationStatus(msg.sender)) revert UserNotVerified();
        if (bytes(name).length == 0) revert InvalidCollectionName();
        if (bytes(description).length == 0) revert InvalidCollectionDescription();
        
        collectionId = totalCollections;
        uint40 timestamp = uint40(block.timestamp);

        collections[collectionId] = Collection({
            name: name,
            description: description,
            collectionType: collectionType,
            createdAt: timestamp,
            exists: true,
            dsrcAddresses: new address[](0),
            coverArtUri: coverArtUri
        });

        creatorCollections[msg.sender].push(collectionId);
        
        unchecked {
            ++totalCollections;
        }

        emit CollectionCreated(
            collectionId,
            msg.sender,
            name,
            collectionType,
            timestamp
        );
        
        return collectionId;
    }

    /**
     * @notice Adds a DSRC to an existing collection
     * @param collectionId The ID of the collection
     * @param dsrcAddress The address of the DSRC to add
     */
    function addDSRCToCollection(uint256 collectionId, address dsrcAddress) 
        external 
        whenNotPaused
        nonReentrant 
    {
        if (!collections[collectionId].exists) revert CollectionNotFound();
        if (!verificationContract.verificationStatus(msg.sender)) revert UserNotVerified();
        if (!dsrcFactory.isValidDSRC(dsrcAddress)) revert InvalidDsrcId();
        
        // Check if the DSRC belongs to the caller
        IHitmakrDSRC dsrc = IHitmakrDSRC(dsrcAddress);
        if (dsrc.creator() != msg.sender) revert Unauthorized();
        
        collections[collectionId].dsrcAddresses.push(dsrcAddress);
        emit DSRCAdded(collectionId, dsrcAddress);
    }

    /**
     * @notice Gets all collections for a creator
     * @param creator The address of the creator
     * @return collectionIds Array of collection IDs owned by the creator
     */
    function getCreatorCollections(address creator) 
        external 
        view 
        returns (uint256[] memory collectionIds) 
    {
        return creatorCollections[creator];
    }

    /**
     * @notice Gets details of a specific collection
     * @param collectionId The ID of the collection
     * @return Collection details
     */
    function getCollection(uint256 collectionId) 
        external 
        view 
        returns (Collection memory) 
    {
        if (!collections[collectionId].exists) revert CollectionNotFound();
        return collections[collectionId];
    }

    /**
     * @notice Toggles the emergency pause state of the contract
     */
    function toggleEmergencyPause() external onlyAdmin nonReentrant {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
        emit EmergencyAction(paused());
    }
} 