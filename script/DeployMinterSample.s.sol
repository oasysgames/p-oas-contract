// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MinterSample} from "../src/samples/MinterSample.sol";

/// @notice Deployment script for the MinterSample contract.
contract DeployMinterSample is Script {
    function run() public {
        vm.startBroadcast();

        address deployer = msg.sender;
        bool useProxyAdmin = vm.envBool("USE_PROXY_ADMIN");
        address proxyOwner = vm.envAddress("PROXY_OWNER");
        address pOAS = vm.envAddress("POAS_ADDRESS");
        address minterOwner = vm.envAddress("MINTER_OWNER");
        uint256 mintCap = vm.envUint("MINT_CAP");
        bool disableWhitelistCheck = vm.envBool("DISABLE_WHITELIST_CHECK");

        console.log("Deployer(Owner of MinterSample): %s", deployer);
        console.log("Proxy Owner: %s", proxyOwner);
        console.log("Use ProxyAdmin: %s", useProxyAdmin);
        console.log("POAS Address: %s", pOAS);
        console.log("Minter Owner: %s", minterOwner);
        console.log("Mint Cap: %s", mintCap);
        console.log("Disable Whitelist Check: %s", disableWhitelistCheck);

        if (!useProxyAdmin && proxyOwner == deployer) {
            revert("ProxyAdmin is not used, so Proxy Owner must be different from MinterSample Admin");
        }

        address implementation = address(new MinterSample());
        console.log("Deployed MinterSample Implementation: %s", address(implementation));

        if (useProxyAdmin) {
            ProxyAdmin pa = new ProxyAdmin();
            if (proxyOwner != deployer) {
                pa.transferOwnership(proxyOwner);
            }
            proxyOwner = address(pa);
            console.log("Deployed ProxyAdmin: %s", proxyOwner);
        }

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            implementation,
            proxyOwner,
            abi.encodeWithSelector(MinterSample.initialize.selector, minterOwner, pOAS, mintCap, disableWhitelistCheck)
        );
        console.log("Deployed MinterSample Proxy:", address(proxy));

        vm.stopBroadcast();
    }
}
