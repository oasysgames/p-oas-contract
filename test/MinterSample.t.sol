// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {POAS} from "../src/POAS.sol";
import {MinterSample} from "../src/samples/MinterSample.sol";
import {IPOAS} from "../src/interfaces/IPOAS.sol";

contract Payment {
    uint256 public price;
    MinterSample public minter;
    IPOAS public poas;
    uint256 public backRate = 20;

    constructor(uint256 _price, address _minter, address _poas) {
        price = _price;
        minter = MinterSample(_minter);
        poas = IPOAS(_poas);
    }

    receive() external payable {}

    function pay(uint256 poasAmount) external payable {
        require(
            price == poasAmount + msg.value,
            "Sum of amounts mismatch value"
        );
        poas.transferFrom(msg.sender, address(this), poasAmount);
        uint256 backAmount = (msg.value * backRate) / 100;
        minter.mint{value: backAmount}(msg.sender, backAmount);
    }
}

contract MinterSampleTest is Test {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RECIPIENT_ROLE = keccak256("RECIPIENT_ROLE");

    TransparentUpgradeableProxy public poasProxy;
    POAS public poasImplementation;
    POAS public poas;

    TransparentUpgradeableProxy public minterProxy;
    MinterSample public minterImplementation;

    Payment public payment;

    address public deployer;
    address public poasAdmin;
    address public poasOperator;

    address public owner;
    address public buyer1;
    address public buyer2;
    address public buyer3;
    address[] public whitelist;
    uint256[] public whitelistCaps;

    address[] public recipientAddrs;
    string[] public recipientNames;
    string[] public recipientDescs;

    uint256 public minCap = 3 ether;
    uint256 public amount = 0.5 ether;
    uint256 public price = 1 ether;

    event MinterReceived(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    error ExContractError(address buyer, uint256 price, string message);

    function setUp() public {
        // Deployment and initial setup
        deployer = makeAddr("deployer");
        poasAdmin = makeAddr("poasAdmin");
        owner = makeAddr("owner");
        buyer1 = makeAddr("buyer1");
        buyer2 = makeAddr("buyer2");
        buyer3 = makeAddr("buyer3");

        // Deploy cntracts
        {
            vm.startPrank(deployer);

            poasImplementation = new POAS();
            poasProxy = new TransparentUpgradeableProxy(
                address(poasImplementation),
                deployer, // Owner of the Proxy itself
                abi.encodeWithSelector(POAS.initialize.selector, poasAdmin)
            );

            minterImplementation = new MinterSample();
            // minter.initialize(address(poasProxy));
            minterProxy = new TransparentUpgradeableProxy(
                address(minterImplementation),
                deployer, // Owner of the Proxy itself
                abi.encodeWithSelector(
                    MinterSample.initialize.selector,
                    owner,
                    poasProxy,
                    minCap,
                    false // disableWhitelistCheck
                )
            );

            payment = new Payment(
                price,
                address(minterProxy),
                address(poasProxy)
            );

            vm.stopPrank();
        }

        poas = POAS(address(poasProxy));

        vm.prank(poasAdmin);
        poas.grantRole(OPERATOR_ROLE, poasOperator);

        vm.deal(poasOperator, 10 ether);
        vm.deal(buyer1, amount * 10);
        vm.deal(buyer2, amount * 10);
        vm.deal(buyer3, amount * 10);

        recipientAddrs.push(address(payment));
        recipientNames.push("name");
        recipientDescs.push("description");
        vm.prank(poasOperator);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);

        whitelist.push(buyer1);
        whitelist.push(buyer2);
        whitelist.push(address(payment));
        whitelistCaps.push(minCap);
        whitelistCaps.push(minCap);
        whitelistCaps.push(minCap);
    }

    function test_cacheback() public {
        uint256 buyerInitalPOAS = 1 ether;
        vm.prank(poasOperator);
        poas.mint(buyer1, buyerInitalPOAS);
        vm.prank(poasAdmin);
        poas.grantRole(OPERATOR_ROLE, address(minterProxy));
        vm.prank(owner);
        MinterSample(payable(address(minterProxy))).addWhitelist(
            whitelist,
            whitelistCaps
        );

        uint256 poasAmount = price - amount;
        uint256 collateralAmount = poasAmount;
        vm.prank(poasOperator);
        poas.depositCollateral{value: collateralAmount}();
        vm.startPrank(buyer1);
        poas.approve(address(payment), poasAmount);
        vm.startPrank(buyer1);
        payment.pay{value: amount}(poasAmount);

        uint256 backAmount = (amount * 20) / 100;
        assertEq(poas.balanceOf(address(payment)), 0);
        assertEq(address(payment).balance, amount - backAmount + poasAmount);
        assertEq(
            poas.balanceOf(buyer1),
            buyerInitalPOAS - poasAmount + backAmount
        );
        assertEq(address(poas).balance, backAmount);
    }

    function test_mint() public {
        MinterSample minter = MinterSample(payable(address(minterProxy)));
        vm.prank(poasAdmin);
        poas.grantRole(OPERATOR_ROLE, address(minterProxy));
        vm.prank(owner);
        minter.addWhitelist(whitelist, whitelistCaps);

        vm.prank(buyer1);
        minter.mint{value: amount}(amount);

        assertEq(poas.balanceOf(buyer1), amount);
        assertEq(address(poas).balance, amount);

        vm.prank(buyer2);
        minter.mint{value: amount}(buyer1, amount);

        assertEq(poas.balanceOf(buyer1), amount * 2);
        assertEq(address(poas).balance, amount * 2);
    }

    function test_mint_reverts() public {
        MinterSample minter = MinterSample(payable(address(minterProxy)));

        // Case: No operator role
        vm.expectRevert("Contract needs OPERATOR_ROLE");
        vm.prank(buyer1);
        minter.mint{value: amount}(amount);

        // Case: not whitelisted
        vm.prank(poasAdmin);
        poas.grantRole(OPERATOR_ROLE, address(minterProxy));
        vm.expectRevert("Not whitelisted or no allowance");
        vm.prank(buyer1);
        minter.mint{value: amount}(amount);

        // Case: Invalid amount
        vm.prank(owner);
        minter.addWhitelist(whitelist, whitelistCaps);
        vm.expectRevert("Amount mismatch");
        vm.prank(buyer1);
        minter.mint(amount);

        // Case: Empty address
        vm.expectRevert("Empty address");
        vm.prank(buyer1);
        minter.mint{value: amount}(address(0), amount);

        // Case: over max cap
        vm.expectRevert("Total mint cap exceeded");
        vm.prank(buyer1);
        minter.mint{value: minCap + 1}(minCap + 1);
    }

    function test_mintCap() public {
        MinterSample minter = MinterSample(payable(address(minterProxy)));
        address[] memory _whitelist = new address[](1);
        _whitelist[0] = buyer1;
        uint256[] memory _whitelistCaps = new uint256[](1);
        uint256 halfCap = minCap / 2;
        _whitelistCaps[0] = halfCap;
        vm.prank(poasAdmin);
        poas.grantRole(OPERATOR_ROLE, address(minterProxy));
        vm.prank(owner);
        minter.addWhitelist(_whitelist, _whitelistCaps);

        vm.prank(buyer1);
        minter.mint{value: halfCap - 1}(halfCap - 1);

        assertEq(minter.mintedAmount(), halfCap - 1);

        vm.expectRevert("Mint cap exceeded");
        vm.prank(buyer1);
        minter.mint{value: amount}(amount);
    }

    function test_mint_disableWhitelistCheck() public {
        MinterSample minter = MinterSample(payable(address(minterProxy)));
        vm.prank(poasAdmin);
        poas.grantRole(OPERATOR_ROLE, address(minterProxy));

        // fail to mint. before disabling whitelist check
        vm.expectRevert("Not whitelisted or no allowance");
        vm.prank(buyer3);
        minter.mint{value: amount}(amount);

        // succeed to mint after disabling whitelist check
        vm.prank(owner);
        minter.updateDisableWhitelistCheck(true);
        vm.prank(buyer3);
        minter.mint{value: amount}(amount);
        assertEq(poas.balanceOf(buyer3), amount);

        // fail to mint again. after disabling whitelist check
        vm.prank(owner);
        minter.addWhitelist(whitelist, whitelistCaps); // <- buyer3 is not whitelisted
        vm.prank(owner);
        minter.updateDisableWhitelistCheck(false);
        vm.expectRevert("Not whitelisted or no allowance");
        vm.prank(buyer3);
        minter.mint{value: amount}(buyer2, amount);

        // succeed to mint. after adding buyer3 to whitelist
        address[] memory buyer3Array = new address[](1);
        buyer3Array[0] = buyer3;
        uint256[] memory buyer3Cap = new uint256[](1);
        buyer3Cap[0] = minCap;
        vm.prank(owner);
        minter.addWhitelist(buyer3Array, buyer3Cap);
        vm.prank(buyer3);
        minter.mint{value: amount}(buyer2, amount);
        assertEq(poas.balanceOf(buyer2), amount);
        assertEq(address(poas).balance, amount * 2);
    }

    function test_bulkMint() public {
        MinterSample minter = MinterSample(payable(address(minterProxy)));
        vm.prank(poasAdmin);
        poas.grantRole(OPERATOR_ROLE, address(minterProxy));
        vm.prank(owner);
        minter.addWhitelist(whitelist, whitelistCaps);

        address[] memory accounts = new address[](2);
        accounts[0] = buyer1;
        accounts[1] = buyer2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount * 2;
        vm.prank(buyer1);
        minter.bulkMint{value: amount * 3}(accounts, amounts);

        assertEq(poas.balanceOf(buyer1), amount);
        assertEq(poas.balanceOf(buyer2), amount * 2);
        assertEq(address(poas).balance, amount * 3);
    }

    function test_bulkMint_revert() public {
        MinterSample minter = MinterSample(payable(address(minterProxy)));
        vm.prank(poasAdmin);
        poas.grantRole(OPERATOR_ROLE, address(minterProxy));
        vm.prank(owner);
        minter.addWhitelist(whitelist, whitelistCaps);

        // Case: length mismatch
        address[] memory accounts = new address[](1);
        accounts[0] = buyer1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount * 2;
        vm.expectRevert("Arrays length mismatch");
        vm.prank(buyer1);
        minter.bulkMint{value: amount * 3}(accounts, amounts);

        // Case: sum of amounts mismatch
        address[] memory accounts2 = new address[](2);
        accounts2[0] = buyer1;
        accounts2[1] = buyer2;
        vm.expectRevert("Sum of amounts mismatch value");
        vm.prank(buyer1);
        minter.bulkMint{value: amount * 2}(accounts2, amounts);
    }

    function test_mintrate() public {
        MinterSample minter = MinterSample(payable(address(minterProxy)));
        vm.prank(poasAdmin);
        poas.grantRole(OPERATOR_ROLE, address(minterProxy));
        uint16 newMinRate = 250;

        // Case: fail to set by invalid owner
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(buyer1);
        minter.updateMintRate(newMinRate);

        // Case: succeed to set by owner
        vm.prank(owner);
        minter.updateMintRate(newMinRate);
        assertEq(minter.mintRate(), newMinRate);

        vm.prank(owner);
        minter.addWhitelist(whitelist, whitelistCaps);

        vm.prank(buyer1);
        minter.mint{value: amount}(amount);

        assertEq(poas.balanceOf(buyer1), (amount * newMinRate) / 100);
        assertEq(address(poas).balance, amount);
    }

    function test_whitelist() public {
        MinterSample minter = MinterSample(payable(address(minterProxy)));

        // Case: fail to add by invalid owner
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(buyer1);
        minter.addWhitelist(whitelist, whitelistCaps);

        // Case: succeed to adding by owner
        vm.prank(owner);
        minter.addWhitelist(whitelist, whitelistCaps);
        assertEq(minter.whitelist(0), buyer1);
        assertEq(minter.whitelist(1), buyer2);
        assertEq(minter.whitelistWithAllowanceMap(buyer1), minCap);
        assertEq(minter.whitelistWithAllowanceMap(buyer2), minCap);

        // Case: add again to increase allowance
        vm.prank(owner);
        minter.addWhitelist(whitelist, whitelistCaps);
        assertEq(minter.whitelistWithAllowanceMap(buyer1), minCap * 2);
        assertEq(minter.whitelistWithAllowanceMap(buyer2), minCap * 2);

        // Case: failed to remove by invalid owner
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(buyer1);
        minter.removeWhitelist(whitelist);

        // Case: succeed to removing by owner
        vm.prank(owner);
        minter.removeWhitelist(whitelist);
        assertEq(minter.whitelistWithAllowanceMap(buyer1), 0);
        assertEq(minter.whitelistWithAllowanceMap(buyer2), 0);
        vm.expectRevert();
        minter.whitelist(0);

        // Case: Not whitelisted
        vm.expectRevert("Not whitelisted or no allowance");
        vm.prank(owner);
        minter.removeWhitelist(whitelist);
    }

    function test_UpgradeImplementation() public {
        MinterSample minter = MinterSample(payable(address(minterProxy)));

        // Upgrade implementation
        {
            vm.startPrank(deployer);

            ITransparentUpgradeableProxy iminterProxy = ITransparentUpgradeableProxy(
                    address(minterProxy)
                );

            MinterSample newImplementation = new MinterSample();

            iminterProxy.upgradeTo(address(newImplementation));
            assertEq(iminterProxy.implementation(), address(newImplementation));

            vm.stopPrank();
        }

        // Make sure the the proxy storage is still intact by trying initialization
        vm.expectRevert("Initializable: contract is already initialized");
        minter.initialize(owner, address(poas), minCap, false);
    }
}
