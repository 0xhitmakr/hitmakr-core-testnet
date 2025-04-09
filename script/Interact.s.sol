// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/core/HitmakrCollection.sol";
import "../src/core/HitmakrDSRC.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/core/IHitmakrVerification.sol";

// Mock Verification interface for interaction
interface IMockVerification {
    function setVerificationStatus(address user, bool status) external;
}

contract InteractScript is Script {
    // Contract addresses from deployment
    address constant COLLECTION = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;
    address constant VERIFICATION = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    address constant USDC = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address constant CONTROL_CENTER = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;

    function run() external {
        // Use the second Anvil account as a creator
        uint256 creatorPrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        address creator = vm.addr(creatorPrivateKey);
        
        vm.startBroadcast(creatorPrivateKey);

        // Get contract instances
        HitmakrCollection collection = HitmakrCollection(COLLECTION);
        IHitmakrVerification verification = IHitmakrVerification(VERIFICATION);

        // Verify the creator (using the mock verification interface)
        IMockVerification(VERIFICATION).setVerificationStatus(creator, true);
        console.log("Creator verified:", creator);

        // Create a collection
        collection.createCollection(
            "My First Album",
            "This is my first album on Hitmakr",
            HitmakrCollection.CollectionType.Album,
            "ipfs://coverArtHash"
        );
        console.log("Collection created");

        // Get collection details
        uint256[] memory creatorCollections = collection.getCreatorCollections(creator);
        console.log("Creator has", creatorCollections.length, "collections");

        if (creatorCollections.length > 0) {
            HitmakrCollection.Collection memory col = collection.getCollection(creatorCollections[0]);
            console.log("\nCollection Details:");
            console.log("------------------");
            console.log("Name:", col.name);
            console.log("Description:", col.description);
            console.log("Type:", uint(col.collectionType));
            console.log("Created at:", col.createdAt);
            console.log("Number of DSRCs:", col.dsrcAddresses.length);
            console.log("Cover Art URI:", col.coverArtUri);
        }

        vm.stopBroadcast();
    }
} 