// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/core/HitmakrCollection.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // SKALE testnet addresses
        address VERIFICATION_ADDRESS = 0xB41406Ef2b2D554855EfA42efC196F896Cf1BcF6;
        address CONTROL_CENTER_ADDRESS = 0xd842e9830567dC5a0c6Afe8719261Cef8d79F385;

        vm.startBroadcast(deployerPrivateKey);

        // Deploy HitmakrCollection using the existing contracts
        HitmakrCollection collection = new HitmakrCollection(
            VERIFICATION_ADDRESS,
            CONTROL_CENTER_ADDRESS
        );
        
        console.log("Collection contract deployed at:", address(collection));
        
        vm.stopBroadcast();

        console.log("\nDeployment Summary:");
        console.log("------------------");
        console.log("SKALE Testnet (Chain ID: 974399131)");
        console.log("Verification:", VERIFICATION_ADDRESS);
        console.log("Control Center:", CONTROL_CENTER_ADDRESS);
        console.log("Collection:", address(collection));
        console.log("Deployer:", deployer);
    }
}
