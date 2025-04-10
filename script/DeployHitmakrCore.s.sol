// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/accesscontrol/ControlCenter.sol";
import "../src/core/HitmakrCreativeID.sol";
import "../src/core/HitmakrVerification.sol";
import "../src/core/HitmakrDSRCFactory.sol";
import "../src/core/HitmakrCollection.sol";
import "../src/core/HitmakrDSRC.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Mock USDC token for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {
        _mint(msg.sender, 1000000 * 10 ** 6); // Mint 1M USDC
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

// Mock Purchase Indexer for testing
contract MockPurchaseIndexer {
    constructor() {}
}

// Mock HitmakrProfiles for testing
contract MockHitmakrProfiles is ERC721 {
    mapping(address => bool) private hasProfile;
    mapping(address => string) private nameByAddress;
    
    constructor() ERC721("MockProfiles", "PROF") {}
    
    function _hasProfile(address user) external view returns (bool) {
        return hasProfile[user];
    }
    
    function _nameByAddress(address user) external view returns (string memory) {
        return nameByAddress[user];
    }
    
    function createProfile(address user, string memory name) external {
        hasProfile[user] = true;
        nameByAddress[user] = name;
    }
}

contract DeployHitmakrCore is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying Hitmakr Core contracts with deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy HitmakrControlCenter (Access Control)
        HitmakrControlCenter controlCenter = new HitmakrControlCenter();
        console.log("HitmakrControlCenter deployed at:", address(controlCenter));
        
        // 2. Deploy MockHitmakrProfiles
        MockHitmakrProfiles profiles = new MockHitmakrProfiles();
        console.log("MockHitmakrProfiles deployed at:", address(profiles));
        
        // Create profile for deployer
        profiles.createProfile(deployer, "DEPLOYER");
        
        // 3. Deploy HitmakrVerification
        HitmakrVerification verification = new HitmakrVerification(address(controlCenter), address(profiles));
        console.log("HitmakrVerification deployed at:", address(verification));
        
        // 4. Deploy HitmakrCreativeID - use verification contract, not control center
        HitmakrCreativeID creativeID = new HitmakrCreativeID(address(verification));
        console.log("HitmakrCreativeID deployed at:", address(creativeID));
        
        // 5. Deploy USDC (or use real USDC on mainnet)
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));
        
        // 6. Deploy MockPurchaseIndexer
        MockPurchaseIndexer purchaseIndexer = new MockPurchaseIndexer();
        console.log("MockPurchaseIndexer deployed at:", address(purchaseIndexer));
        
        // 7. Deploy HitmakrDSRCFactory
        HitmakrDSRCFactory dsrcFactory = new HitmakrDSRCFactory(
            address(controlCenter),
            address(creativeID),
            address(usdc),
            address(purchaseIndexer)
        );
        console.log("HitmakrDSRCFactory deployed at:", address(dsrcFactory));
        
        // 8. Deploy HitmakrCollection
        HitmakrCollection collection = new HitmakrCollection(
            address(verification),
            address(dsrcFactory)
        );
        console.log("HitmakrCollection deployed at:", address(collection));
        
        // 9. Setup roles in ControlCenter
        // Grant deployer ADMIN_ROLE
        controlCenter.grantRole(controlCenter.ADMIN_ROLE(), deployer);
        
        // Grant deployer VERIFIER_ROLE
        controlCenter.grantRole(controlCenter.VERIFIER_ROLE(), deployer);
        
        // 10. Setup test user as verified user
        verification.setVerification(deployer, true);
        
        // 11. Setup test user with a Creative ID (country code + registry code)
        creativeID.register("US", "TEST1");
        
        vm.stopBroadcast();
        
        console.log("\nDeployment Summary:");
        console.log("------------------");
        console.log("HitmakrControlCenter:", address(controlCenter));
        console.log("MockHitmakrProfiles:", address(profiles));
        console.log("HitmakrVerification:", address(verification));
        console.log("HitmakrCreativeID:", address(creativeID));
        console.log("USDC:", address(usdc));
        console.log("PurchaseIndexer:", address(purchaseIndexer));
        console.log("HitmakrDSRCFactory:", address(dsrcFactory));
        console.log("HitmakrCollection:", address(collection));
        console.log("Deployer:", deployer);
    }
} 