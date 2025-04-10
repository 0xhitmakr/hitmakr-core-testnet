// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/core/HitmakrCollection.sol";
import "../src/core/HitmakrDSRC.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock USDC token for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {
        _mint(msg.sender, 1000000 * 10 ** 6); // Mint 1M USDC
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

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

// Mock Control Center
contract MockControlCenter {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    mapping(address => bool) public hasRole;

    constructor() {
        hasRole[msg.sender] = true;
    }

    function setRole(address user, bool status) external {
        hasRole[user] = status;
    }
}

contract DeployScript is Script {
    function run() external {
        // Use the private key from Anvil's first account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock contracts
        MockUSDC usdc = new MockUSDC();
        console.log("USDC deployed at:", address(usdc));

        MockControlCenter controlCenter = new MockControlCenter();
        console.log("Control Center deployed at:", address(controlCenter));

        MockVerification verification = new MockVerification(
            address(controlCenter)
        );
        console.log(
            "Verification contract deployed at:",
            address(verification)
        );

        // Set deployer as verified
        verification.setVerificationStatus(deployer, true);

        // Deploy HitmakrCollection
        HitmakrCollection collection = new HitmakrCollection(
            address(verification),
            address(controlCenter)
        );
        console.log("Collection contract deployed at:", address(collection));

        vm.stopBroadcast();

        console.log("\nDeployment Summary:");
        console.log("------------------");
        console.log("USDC:", address(usdc));
        console.log("Control Center:", address(controlCenter));
        console.log("Verification:", address(verification));
        console.log("Collection:", address(collection));
        console.log("Deployer:", deployer);
    }
}
