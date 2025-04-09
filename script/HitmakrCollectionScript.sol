// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "../src/core/HitmakrCollection.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

// Mock DSRC contract for the script
contract MockDSRC {
    address public creator;
    string public dsrcId;

    constructor(address _creator, string memory _dsrcId) {
        creator = _creator;
        dsrcId = _dsrcId;
    }
}

// Mock Control Center with AccessControl implementation
contract MockControlCenter is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    mapping(address => bool) public isValidDSRC;
    mapping(address => bool) public verificationStatus;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(VERIFIER_ROLE, admin);
        _grantRole(CREATOR_ROLE, admin);

        // Set admin as verified by default
        verificationStatus[admin] = true;
    }

    function setValidDSRC(address dsrc, bool valid) external {
        isValidDSRC[dsrc] = valid;
    }

    function HITMAKR_CONTROL_CENTER() external view returns (address) {
        return address(this);
    }

    function setVerificationStatus(address user, bool status) external {
        verificationStatus[user] = status;
    }
}

/**
 * @title HitmakrCollectionScript
 * @notice Integration script for demonstrating HitmakrCollection functionality
 * @dev This script simulates creating collections and managing DSRCs
 */
contract HitmakrCollectionScript is Script {
    function run() external {
        // Use first account as admin and creator
        uint256 adminPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address admin = vm.addr(adminPrivateKey);

        // Use second account as another creator
        uint256 creator2PrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        address creator2 = vm.addr(creator2PrivateKey);

        console.log("\n Starting HitmakrCollection Script");
        console.log("----------------------------------------");

        vm.startBroadcast(adminPrivateKey);

        // 1. Deploy Mock Control Center (which also acts as verification)
        MockControlCenter controlCenter = new MockControlCenter(admin);
        console.log(" Control Center deployed at:", address(controlCenter));

        // 2. Deploy HitmakrCollection with the control center
        HitmakrCollection collection = new HitmakrCollection(
            address(controlCenter)
        );
        console.log(" Collection contract deployed at:", address(collection));

        // 3. Create a collection as admin
        collection.createCollection(
            "Admin's Album",
            "This is an album created by the admin",
            HitmakrCollection.CollectionType.Album,
            "ipfs://QmAdminAlbumCoverHash"
        );
        console.log(" Admin's collection created");

        // 4. Create mock DSRCs owned by admin
        MockDSRC dsrc1 = new MockDSRC(admin, "ADMIN_DSRC_1");
        MockDSRC dsrc2 = new MockDSRC(admin, "ADMIN_DSRC_2");
        console.log(
            " Mock DSRCs created: %s and %s",
            address(dsrc1),
            address(dsrc2)
        );

        // 5. Mark DSRCs as valid in the control center
        controlCenter.setValidDSRC(address(dsrc1), true);
        controlCenter.setValidDSRC(address(dsrc2), true);
        console.log(" DSRCs marked as valid");

        // 6. Add DSRCs to the collection
        collection.addDSRCToCollection(0, address(dsrc1));
        collection.addDSRCToCollection(0, address(dsrc2));
        console.log(" DSRCs added to admin's collection");

        // 7. Show collection details after adding DSRCs
        uint256[] memory adminCollections = collection.getCreatorCollections(
            admin
        );
        HitmakrCollection.Collection memory col = collection.getCollection(
            adminCollections[0]
        );

        console.log("\n Admin's Collection Details:");
        console.log("----------------------------------------");
        console.log("Name:", col.name);
        console.log("Description:", col.description);
        console.log("Type:", uint(col.collectionType));
        console.log("Created at:", col.createdAt);
        console.log("Number of DSRCs:", col.dsrcAddresses.length);
        console.log("Cover Art URI:", col.coverArtUri);

        console.log("\nDSRC addresses:");
        for (uint i = 0; i < col.dsrcAddresses.length; i++) {
            console.log("  DSRC %d: %s", i + 1, col.dsrcAddresses[i]);
        }

        // 8. Set up another creator and verify them
        // Use the constant from the contract
        controlCenter.grantRole(controlCenter.CREATOR_ROLE(), creator2);
        controlCenter.setVerificationStatus(creator2, true);
        console.log("\n Creator role granted and verified:", creator2);
        console.log("\n Creator role granted to:", creator2);

        vm.stopBroadcast();

        // 9. Create collection as second creator
        vm.startBroadcast(creator2PrivateKey);

        collection.createCollection(
            "Creator 2's Mixtape",
            "This is a mixtape created by creator 2",
            HitmakrCollection.CollectionType.Mixtape,
            "ipfs://QmCreator2MixtapeCoverHash"
        );
        console.log(" Creator 2's collection created");

        // 10. Create DSRC for the second creator
        MockDSRC creator2Dsrc = new MockDSRC(creator2, "CREATOR2_DSRC");
        console.log(" Creator 2's DSRC created at:", address(creator2Dsrc));

        vm.stopBroadcast();

        // 11. Mark creator2's DSRC as valid (requires admin)
        vm.startBroadcast(adminPrivateKey);
        controlCenter.setValidDSRC(address(creator2Dsrc), true);
        console.log(" Creator 2's DSRC marked as valid");
        vm.stopBroadcast();

        // 12. Add creator2's DSRC to their collection
        vm.startBroadcast(creator2PrivateKey);
        collection.addDSRCToCollection(1, address(creator2Dsrc));
        console.log(" DSRC added to Creator 2's collection");

        // 13. Show creator2's collection details
        uint256[] memory creator2Collections = collection.getCreatorCollections(
            creator2
        );
        HitmakrCollection.Collection memory col2 = collection.getCollection(
            creator2Collections[0]
        );

        console.log("\n Creator 2's Collection Details:");
        console.log("----------------------------------------");
        console.log("Name:", col2.name);
        console.log("Description:", col2.description);
        console.log("Type:", uint(col2.collectionType));
        console.log("Created at:", col2.createdAt);
        console.log("Number of DSRCs:", col2.dsrcAddresses.length);
        console.log("Cover Art URI:", col2.coverArtUri);

        console.log("\nDSRC addresses:");
        for (uint i = 0; i < col2.dsrcAddresses.length; i++) {
            console.log("  DSRC %d: %s", i + 1, col2.dsrcAddresses[i]);
        }

        vm.stopBroadcast();

        // 14. Demonstrate emergency pause (admin only)
        vm.startBroadcast(adminPrivateKey);

        console.log("\n Testing emergency pause functionality:");
        console.log("----------------------------------------");
        collection.toggleEmergencyPause();
        console.log(" Collection contract paused");

        collection.toggleEmergencyPause();
        console.log(" Collection contract unpaused");

        vm.stopBroadcast();

        // 15. Demonstrate that creators cannot add other creators' DSRCs
        console.log("\n Testing creator permissions:");
        console.log("----------------------------------------");

        vm.startBroadcast(creator2PrivateKey);

        console.log(
            "Creator2 tries to add Admin's DSRC to their collection..."
        );
        try collection.addDSRCToCollection(1, address(dsrc1)) {
            console.log(" ERROR: Creator2 was able to add Admin's DSRC!");
        } catch {
            console.log(
                "Expected: Transaction reverted - creator cannot add other's DSRC"
            );
        }

        vm.stopBroadcast();

        vm.startBroadcast(adminPrivateKey);

        console.log(
            "\nAdmin tries to add Creator2's DSRC to their collection..."
        );
        try collection.addDSRCToCollection(0, address(creator2Dsrc)) {
            console.log(" ERROR: Admin was able to add Creator2's DSRC!");
        } catch {
            console.log(
                " Expected: Transaction reverted - creator cannot add other's DSRC"
            );
        }

        vm.stopBroadcast();

        console.log("\n Script execution completed successfully");
    }
}
