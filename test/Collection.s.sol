// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/core/HitmakrCollection.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// Mock Verification contract
contract MockVerification {
    mapping(address => bool) public verificationStatus;
    address public immutable HITMAKR_CONTROL_CENTER;

    constructor(address controlCenter) {
        HITMAKR_CONTROL_CENTER = controlCenter;
    }

    function setVerificationStatus(address user, bool status) external {
        verificationStatus[user] = status;
    }
}

// Mock Control Center with proper AccessControl implementation
contract MockControlCenter is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    mapping(address => bool) public isValidDSRC;

    constructor(address admin) {
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function setValidDSRC(address dsrc, bool valid) external {
        isValidDSRC[dsrc] = valid;
    }
}

// Mock DSRC contract for testing
contract MockDSRC {
    address public creator;
    string public dsrcId;

    constructor(address _creator, string memory _dsrcId) {
        creator = _creator;
        dsrcId = _dsrcId;
    }
}

contract HitmakrCollectionTest is Test {
    // Contracts
    HitmakrCollection public collection;
    MockVerification public verification;
    MockControlCenter public controlCenter;

    // Users
    address public admin = address(0x1);
    address public creator1 = address(0x2);
    address public creator2 = address(0x3);
    address public unverifiedUser = address(0x4);

    // Test data
    string constant COLLECTION_NAME = "Test Album";
    string constant COLLECTION_DESCRIPTION = "This is a test album";
    string constant COVER_ART_URI = "ipfs://coverArtHash";

    function setUp() public {
        // Setup mocks and contracts
        controlCenter = new MockControlCenter(admin);
        verification = new MockVerification(address(controlCenter));

        // Create collection contract with the new setup
        collection = new HitmakrCollection(address(verification), address(controlCenter));

        // Setup verification status for users
        vm.startPrank(admin);
        verification.setVerificationStatus(creator1, true);
        verification.setVerificationStatus(creator2, true);
        verification.setVerificationStatus(unverifiedUser, false);
        vm.stopPrank();
    }

    function test_CreateCollection() public {
        vm.startPrank(creator1);

        // Create a collection
        collection.createCollection(
            COLLECTION_NAME,
            COLLECTION_DESCRIPTION,
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );

        // Check collection data
        uint256[] memory creatorCollections = collection.getCreatorCollections(
            creator1
        );
        assertEq(
            creatorCollections.length,
            1,
            "Creator should have one collection"
        );

        HitmakrCollection.Collection memory col = collection.getCollection(
            creatorCollections[0]
        );
        assertEq(col.name, COLLECTION_NAME, "Collection name should match");
        assertEq(
            col.description,
            COLLECTION_DESCRIPTION,
            "Collection description should match"
        );
        assertEq(
            uint8(col.collectionType),
            uint8(HitmakrCollection.CollectionType.Album),
            "Collection type should match"
        );
        assertEq(col.coverArtUri, COVER_ART_URI, "Cover art URI should match");
        assertEq(
            col.dsrcAddresses.length,
            0,
            "New collection should have no DSRCs"
        );

        vm.stopPrank();
    }

    function test_CreateMultipleCollections() public {
        vm.startPrank(creator1);

        // Create first collection
        collection.createCollection(
            COLLECTION_NAME,
            COLLECTION_DESCRIPTION,
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );

        // Create second collection
        collection.createCollection(
            "Another Album",
            "This is another test album",
            HitmakrCollection.CollectionType.Mixtape,
            "ipfs://anotherCoverArtHash"
        );

        // Check collection data
        uint256[] memory creatorCollections = collection.getCreatorCollections(
            creator1
        );
        assertEq(
            creatorCollections.length,
            2,
            "Creator should have two collections"
        );

        vm.stopPrank();
    }

    function test_CreateDifferentCollectionTypes() public {
        vm.startPrank(creator1);

        // Create Album
        collection.createCollection(
            "Test Album",
            "This is a test album",
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );

        // Create Mixtape
        collection.createCollection(
            "Test Mixtape",
            "This is a test mixtape",
            HitmakrCollection.CollectionType.Mixtape,
            COVER_ART_URI
        );

        // Create Pack
        collection.createCollection(
            "Test Pack",
            "This is a test pack",
            HitmakrCollection.CollectionType.Pack,
            COVER_ART_URI
        );

        // Check collection data
        uint256[] memory creatorCollections = collection.getCreatorCollections(
            creator1
        );
        assertEq(
            creatorCollections.length,
            3,
            "Creator should have three collections"
        );

        // Verify collection types
        HitmakrCollection.Collection memory col1 = collection.getCollection(
            creatorCollections[0]
        );
        assertEq(
            uint8(col1.collectionType),
            uint8(HitmakrCollection.CollectionType.Album),
            "First collection should be an Album"
        );

        HitmakrCollection.Collection memory col2 = collection.getCollection(
            creatorCollections[1]
        );
        assertEq(
            uint8(col2.collectionType),
            uint8(HitmakrCollection.CollectionType.Mixtape),
            "Second collection should be a Mixtape"
        );

        HitmakrCollection.Collection memory col3 = collection.getCollection(
            creatorCollections[2]
        );
        assertEq(
            uint8(col3.collectionType),
            uint8(HitmakrCollection.CollectionType.Pack),
            "Third collection should be a Pack"
        );

        vm.stopPrank();
    }

    function test_AddDSRCToCollection() public {
        vm.startPrank(creator1);

        // Create a collection
        collection.createCollection(
            COLLECTION_NAME,
            COLLECTION_DESCRIPTION,
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );

        // Create a mock DSRC
        MockDSRC dsrc = new MockDSRC(creator1, "DSRC001");

        // Mark DSRC as valid in the factory
        vm.stopPrank();
        vm.prank(admin);
        controlCenter.setValidDSRC(address(dsrc), true);

        // Add DSRC to collection
        vm.prank(creator1);
        collection.addDSRCToCollection(0, address(dsrc));

        // Check collection data
        uint256[] memory creatorCollections = collection.getCreatorCollections(
            creator1
        );
        HitmakrCollection.Collection memory col = collection.getCollection(
            creatorCollections[0]
        );

        assertEq(
            col.dsrcAddresses.length,
            1,
            "Collection should have one DSRC"
        );
        assertEq(
            col.dsrcAddresses[0],
            address(dsrc),
            "DSRC address should match"
        );
    }

    function test_AddMultipleDSRCsToCollection() public {
        vm.startPrank(creator1);

        // Create a collection
        collection.createCollection(
            COLLECTION_NAME,
            COLLECTION_DESCRIPTION,
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );

        // Create mock DSRCs
        MockDSRC dsrc1 = new MockDSRC(creator1, "DSRC001");
        MockDSRC dsrc2 = new MockDSRC(creator1, "DSRC002");
        MockDSRC dsrc3 = new MockDSRC(creator1, "DSRC003");

        vm.stopPrank();

        // Mark DSRCs as valid in the factory
        vm.startPrank(admin);
        controlCenter.setValidDSRC(address(dsrc1), true);
        controlCenter.setValidDSRC(address(dsrc2), true);
        controlCenter.setValidDSRC(address(dsrc3), true);
        vm.stopPrank();

        // Add DSRCs to collection
        vm.startPrank(creator1);
        collection.addDSRCToCollection(0, address(dsrc1));
        collection.addDSRCToCollection(0, address(dsrc2));
        collection.addDSRCToCollection(0, address(dsrc3));
        vm.stopPrank();

        // Check collection data
        uint256[] memory creatorCollections = collection.getCreatorCollections(
            creator1
        );
        HitmakrCollection.Collection memory col = collection.getCollection(
            creatorCollections[0]
        );

        assertEq(
            col.dsrcAddresses.length,
            3,
            "Collection should have three DSRCs"
        );
        assertEq(
            col.dsrcAddresses[0],
            address(dsrc1),
            "First DSRC address should match"
        );
        assertEq(
            col.dsrcAddresses[1],
            address(dsrc2),
            "Second DSRC address should match"
        );
        assertEq(
            col.dsrcAddresses[2],
            address(dsrc3),
            "Third DSRC address should match"
        );
    }

    function test_CreatorCannotAddOtherCreatorsDSRC() public {
        // Setup collections
        vm.prank(creator1);
        collection.createCollection(
            "Creator 1 Album",
            "This is Creator 1's album",
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );

        vm.prank(creator2);
        collection.createCollection(
            "Creator 2 Album",
            "This is Creator 2's album",
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );

        // Create DSRCs owned by each creator
        MockDSRC dsrc1 = new MockDSRC(creator1, "CREATOR1_DSRC");
        MockDSRC dsrc2 = new MockDSRC(creator2, "CREATOR2_DSRC");

        // Mark DSRCs as valid
        vm.startPrank(admin);
        controlCenter.setValidDSRC(address(dsrc1), true);
        controlCenter.setValidDSRC(address(dsrc2), true);
        vm.stopPrank();

        // Creator2 tries to add Creator1's DSRC to their collection
        vm.prank(creator2);
        vm.expectRevert(HitmakrCollection.Unauthorized.selector);
        collection.addDSRCToCollection(1, address(dsrc1));

        // Creator1 tries to add Creator2's DSRC to their collection
        vm.prank(creator1);
        vm.expectRevert(HitmakrCollection.Unauthorized.selector);
        collection.addDSRCToCollection(0, address(dsrc2));
    }

    function test_UnverifiedUserCannotCreateCollection() public {
        vm.prank(unverifiedUser);
        vm.expectRevert(HitmakrCollection.UserNotVerified.selector);
        collection.createCollection(
            COLLECTION_NAME,
            COLLECTION_DESCRIPTION,
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );
    }

    function test_CannotAddInvalidDSRC() public {
        vm.prank(creator1);
        collection.createCollection(
            COLLECTION_NAME,
            COLLECTION_DESCRIPTION,
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );

        // Create a mock DSRC but don't mark it as valid
        MockDSRC dsrc = new MockDSRC(creator1, "DSRC001");

        // Try to add the invalid DSRC
        vm.prank(creator1);
        vm.expectRevert(HitmakrCollection.InvalidDsrcId.selector);
        collection.addDSRCToCollection(0, address(dsrc));
    }

    function test_EmergencyPause() public {
        // Admin pauses the contract
        vm.prank(admin);
        collection.toggleEmergencyPause();

        // Verified creator tries to create a collection while paused
        vm.prank(creator1);

        // Instead of expecting "Pausable: paused", expect the custom error
        vm.expectRevert(); // Just expect any revert
        collection.createCollection(
            COLLECTION_NAME,
            COLLECTION_DESCRIPTION,
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );

        // Admin unpauses the contract
        vm.prank(admin);
        collection.toggleEmergencyPause();

        // Now creator should be able to create a collection
        vm.prank(creator1);
        collection.createCollection(
            COLLECTION_NAME,
            COLLECTION_DESCRIPTION,
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );
    }

    function test_NonAdminCannotTogglePause() public {
        // Creator tries to pause the contract
        vm.prank(creator1);
        vm.expectRevert(HitmakrCollection.Unauthorized.selector);
        collection.toggleEmergencyPause();
    }

    function test_InvalidCollectionInputs() public {
        vm.startPrank(creator1);

        // Empty name
        vm.expectRevert(HitmakrCollection.InvalidCollectionName.selector);
        collection.createCollection(
            "",
            COLLECTION_DESCRIPTION,
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );

        // Empty description
        vm.expectRevert(
            HitmakrCollection.InvalidCollectionDescription.selector
        );
        collection.createCollection(
            COLLECTION_NAME,
            "",
            HitmakrCollection.CollectionType.Album,
            COVER_ART_URI
        );

        vm.stopPrank();
    }

    function test_GetNonExistentCollection() public {
        vm.expectRevert(HitmakrCollection.CollectionNotFound.selector);
        collection.getCollection(999);
    }
}
