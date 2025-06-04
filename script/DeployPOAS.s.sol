// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {POAS} from "../src/POAS.sol";

contract DeployPOAS is Script {
    function run() public {
        vm.startBroadcast();

        address deployer = msg.sender;

        // Whether to use the ProxyAdmin contract
        bool useProxyAdmin = vm.envBool("USE_PROXY_ADMIN");

        // Owner of the Proxy (or ProxyAdmin)
        address proxyOwner = vm.envAddress("PROXY_OWNER");

        // Initial POAS Admin
        address poasAdmin = vm.envAddress("POAS_ADMIN");
        console.log("Deployer: %s", deployer);
        console.log("Proxy Owner: %s", proxyOwner);
        console.log("Use ProxyAdmin: %s", useProxyAdmin);
        console.log("POAS Admin: %s", poasAdmin);

        // If ProxyAdmin is not used, the Proxy Owner and POAS owner must be different
        // Otherwise, all calls from the POAS admin would be intercepted by the Proxy's admin methods
        if (!useProxyAdmin && proxyOwner == deployer) {
            revert("ProxyAdmin is not used, so Proxy Owner must be different from POAS Admin");
        }

        // Deploy the POAS implementation contract
        address implementation = address(new POAS());
        console.log("Deployed POAS Implementation: %s", address(implementation));

        // Deploy the ProxyAdmin
        if (useProxyAdmin) {
            ProxyAdmin pa = new ProxyAdmin();
            // Ownership is initially set to deployer, so transfer it to proxyOwner if different
            if (proxyOwner != deployer) {
                pa.transferOwnership(proxyOwner);
            }

            proxyOwner = address(pa);
            console.log("Deployed ProxyAdmin: %s", proxyOwner);
        }

        // Deploy the TransparentUpgradeableProxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            implementation, proxyOwner, abi.encodeWithSelector(POAS.initialize.selector, poasAdmin)
        );
        console.log("Deployed POAS Proxy:", address(proxy));

        vm.stopBroadcast();
    }
}
