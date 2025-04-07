// SPDX-License-Identifier: MIT
pragma solidity =0.5.16;

import "../src/UniswapV2Factory.sol";
import "forge-std/Script.sol";

contract DeployUniswapV2 is Script {
    function setUp() public {}

    function run() public {
        // Read private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the Factory contract
        address feeToSetter = vm.addr(deployerPrivateKey); // Set the feeToSetter to the deployer address
        UniswapV2Factory factory = new UniswapV2Factory(feeToSetter);

        // Log the address where the factory was deployed
        console.log("UniswapV2Factory deployed at:", address(factory));

        vm.stopBroadcast();
    }
}
