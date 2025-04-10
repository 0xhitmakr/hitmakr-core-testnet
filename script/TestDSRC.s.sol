// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "../src/core/HitmakrDSRC.sol";
import "../src/core/HitmakrDSRCFactory.sol";
import "../src/core/indexers/HitmakrDSRCPurchaseIndexer.sol";
import "../src/core/HitmakrCollection.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/utils/DSRCSignatureUtils.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

// Mock USDC token for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock Control Center
contract MockControlCenter is AccessControl {
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    // Add mapping for verification status
    mapping(address => bool) public verificationStatus;
    mapping(address => bool) public isValidDSRC;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VERIFIER_ROLE, admin);
        _grantRole(CREATOR_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        
        // Set creator as verified by default
        verificationStatus[admin] = true;
    }

    function HITMAKR_CONTROL_CENTER() external view returns (address) {
        return address(this);
    }
    
    function setVerificationStatus(address user, bool status) external {
        verificationStatus[user] = status;
    }
    
    function setValidDSRC(address dsrc, bool valid) external {
        isValidDSRC[dsrc] = valid;
    }

    function hasCreatorRole(address account) external view returns (bool) {
        return hasRole(CREATOR_ROLE, account);
    }

    function grantCreatorRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(CREATOR_ROLE, account);
    }
}

// Mock Creative ID
contract MockCreativeID {
    mapping(address => string) private creativeIds;
    mapping(address => bool) private exists;

    function getCreativeID(address creator) external view returns (string memory, uint256, bool) {
        return (creativeIds[creator], bytes(creativeIds[creator]).length, exists[creator]);
    }

    function setCreativeID(address creator, string memory id) external {
        creativeIds[creator] = id;
        exists[creator] = true;
    }
}

contract TestDSRCScript is Script {    
    function run() external {
        // Use the first account as deployer/creator
        uint256 creatorPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address creator = vm.addr(creatorPrivateKey);
        
        // Use the second account as buyer
        uint256 buyerPrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        address buyer = vm.addr(buyerPrivateKey);

        vm.startBroadcast(creatorPrivateKey);

        // Deploy Mock USDC
        MockUSDC usdc = new MockUSDC();
        console.log("Mock USDC deployed at:", address(usdc));

        // Deploy Mock Control Center
        MockControlCenter controlCenter = new MockControlCenter(creator);
        console.log("Mock Control Center deployed at:", address(controlCenter));

        // Deploy Mock Creative ID
        MockCreativeID creativeID = new MockCreativeID();
        console.log("Mock Creative ID deployed at:", address(creativeID));
        creativeID.setCreativeID(creator, "CREATOR_ID_1");

        // Deploy Purchase Indexer
        HitmakrDSRCPurchaseIndexer indexer = new HitmakrDSRCPurchaseIndexer(creator);
        console.log("Purchase Indexer deployed at:", address(indexer));

        // Deploy Factory and set it in the indexer
        HitmakrDSRCFactory factory = new HitmakrDSRCFactory(
            address(controlCenter),
            address(creativeID),
            address(usdc),
            address(indexer)
        );
        console.log("Factory deployed at:", address(factory));
        indexer.updateFactory(address(factory));
        console.log("Factory set in indexer");

        // Setup recipients and percentages
        address[] memory recipients = new address[](1);
        recipients[0] = creator;

        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 10000; // 100%

        // Setup DSRC parameters
        DSRCSignatureUtils.DSRCParams memory params = DSRCSignatureUtils.DSRCParams({
            tokenURI: "https://example.com/metadata/",
            price: 1e8, // 1 USDC for Collectors edition
            recipients: recipients,
            percentages: percentages,
            nonce: 0,
            deadline: block.timestamp + 15 minutes,
            selectedChain: "SKL"
        });

        // Create signature
        bytes32 domainSeparator = DSRCSignatureUtils.getDomainSeparator(
            "HitmakrDSRCFactory",
            "1.0.0",
            address(factory)
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                DSRCSignatureUtils.hashDSRCParams(params)
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Deploy DSRC (using admin role)
        vm.recordLogs();
        factory.createDSRC(
            params,
            500 * 10**6, // 500 USDC for Licensing edition
            signature
        );

        // Get DSRC address from event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        address dsrcAddress;
        for (uint i = 0; i < entries.length; i++) {
            // The DSRCCreated event has the following signature:
            // event DSRCCreated(string dsrcId, address dsrcAddress, address creator, string selectedChain)
            if (entries[i].topics[0] == keccak256("DSRCCreated(string,address,address,string)")) {
                (string memory dsrcId, address _dsrcAddress, address creator, string memory selectedChain) = abi.decode(entries[i].data, (string, address, address, string));
                dsrcAddress = _dsrcAddress;
                break;
            }
        }
        require(dsrcAddress != address(0), "DSRC address not found in events");
        HitmakrDSRC dsrc = HitmakrDSRC(dsrcAddress);
        console.log("DSRC deployed at:", address(dsrc));
        
        // Mark the DSRC as valid in the control center
        controlCenter.setValidDSRC(dsrcAddress, true);
        console.log("DSRC marked as valid in control center");

        // Deploy HitmakrCollection
        HitmakrCollection collection = new HitmakrCollection(address(controlCenter), address(factory));
        console.log("Collection contract deployed at:", address(collection));

        // Create a new collection
        collection.createCollection(
            "My First Album",
            "This is my first album on Hitmakr",
            HitmakrCollection.CollectionType.Album,
            "ipfs://QmAlbumCoverHash"
        );
        console.log("Collection created");

        // Add DSRC to collection
        collection.addDSRCToCollection(0, dsrcAddress);
        console.log("DSRC added to collection");

        // Create Licensing edition is not needed anymore since it's created in the factory
        // dsrc.createEdition(HitmakrDSRC.Edition.Licensing, 500 * 10**6); // 500 USDC
        // console.log("Licensing edition created");

        // Mint USDC tokens for buyer
        usdc.mint(buyer, 1000 * 10**6); // Mint 1000 USDC
        console.log("Minted 1000 USDC for buyer");

        vm.stopBroadcast();

        // Switch to buyer account
        vm.startBroadcast(buyerPrivateKey);

        // Check USDC balance
        uint256 balance = usdc.balanceOf(buyer);
        console.log("\nBuyer USDC balance:", balance / 10**6, "USDC");

        // Approve USDC spending for Collectors edition
        usdc.approve(address(dsrc), 100 * 10**6);
        console.log("USDC approved for Collectors edition");

        // Purchase Collectors edition
        dsrc.purchase(HitmakrDSRC.Edition.Collectors);
        console.log("Collectors edition purchased");

        // Check purchase details
        console.log("\nPurchase Details:");
        console.log("------------------");
        console.log("Buyer:", buyer);
        console.log("Has purchased:", dsrc.hasPurchased(buyer));
        console.log("Token ID:", dsrc.totalSupply_());
        console.log("Token owner:", dsrc.ownerOf(1));

        // Get earnings info
        (
            uint256 purchaseEarnings,
            uint256 royaltyEarnings,
            uint256 pendingAmount,
            uint256 totalEarnings
        ) = dsrc.getEarningsInfo();

        console.log("\nEarnings Info:");
        console.log("------------------");
        console.log("Purchase earnings:", purchaseEarnings / 10**6, "USDC");
        console.log("Royalty earnings:", royaltyEarnings / 10**6, "USDC");
        console.log("Pending amount:", pendingAmount / 10**6, "USDC");
        console.log("Total earnings:", totalEarnings / 10**6, "USDC");

        // Get edition details
        (uint256 price, bool isEnabled, bool isCreated) = dsrc.getEditionConfig(HitmakrDSRC.Edition.Collectors);
        console.log("\nCollectors Edition Details:");
        console.log("------------------");
        console.log("Price:", price / 10**6, "USDC");
        console.log("Enabled:", isEnabled);
        console.log("Created:", isCreated);

        vm.stopBroadcast();

        // Switch back to creator to distribute earnings
        vm.startBroadcast(creatorPrivateKey);

        // Distribute earnings (0 = distribute purchase earnings)
        dsrc.distributeRoyalties(0);
        console.log("\nEarnings distributed");

        // Get updated earnings info
        (
            purchaseEarnings,
            royaltyEarnings,
            pendingAmount,
            totalEarnings
        ) = dsrc.getEarningsInfo();

        console.log("\nUpdated Earnings Info:");
        console.log("------------------");
        console.log("Purchase earnings:", purchaseEarnings / 10**6, "USDC");
        console.log("Royalty earnings:", royaltyEarnings / 10**6, "USDC");
        console.log("Pending amount:", pendingAmount / 10**6, "USDC");
        console.log("Total earnings:", totalEarnings / 10**6, "USDC");

        // Check creator's USDC balance
        balance = usdc.balanceOf(creator);
        console.log("\nCreator USDC balance:", balance / 10**6, "USDC");

        vm.stopBroadcast();
    }
} 