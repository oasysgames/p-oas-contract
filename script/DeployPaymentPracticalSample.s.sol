// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PaymentPracticalSample} from "../src/samples/PaymentPracticalSample.sol";

contract DeployPaymentPracticalSample is Script {
    function run() public {
        vm.startBroadcast();

        address deployer = msg.sender;

        // Whether to use the ProxyAdmin contract
        bool useProxyAdmin = vm.envBool("USE_PROXY_ADMIN");

        // Owner of the Proxy (or ProxyAdmin)
        address proxyOwner = vm.envAddress("PROXY_OWNER");

        // The address of the POAS contract
        address pOAS = vm.envAddress("POAS_ADDRESS");

        // The external contract address
        address exContract = vm.envAddress("EX_CONTRACT");

        // The inital price for payments
        uint256 price = vm.envUint("PAYMENT_PRICE");

        console.log("Deployer(Owner of PaymentPracticalSample): %s", deployer);
        console.log("Proxy Owner: %s", proxyOwner);
        console.log("Use ProxyAdmin: %s", useProxyAdmin);
        console.log("POAS Address: %s", pOAS);
        console.log("External Contract: %s", exContract);
        console.log("Price: %s", price);

        // If ProxyAdmin is not used, the Proxy Owner and PaymentPracticalSample owner must be different
        // Otherwise, all calls from the PaymentPracticalSample admin would be intercepted by the Proxy's admin methods
        if (!useProxyAdmin && proxyOwner == deployer) {
            revert("ProxyAdmin is not used, so Proxy Owner must be different from PaymentPracticalSample Admin");
        }

        // Deploy the PaymentPracticalSample implementation contract
        address implementation = address(new PaymentPracticalSample());
        console.log("Deployed PaymentPracticalSample Implementation: %s", address(implementation));

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
            implementation,
            proxyOwner,
            abi.encodeWithSelector(PaymentPracticalSample.initialize.selector, pOAS, price, exContract)
        );
        console.log("Deployed PaymentPracticalSample Proxy:", address(proxy));

        vm.stopBroadcast();
    }
}
