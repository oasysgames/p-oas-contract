// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {POAS} from "../src/POAS.sol";
import {IPOAS} from "../src/interfaces/IPOAS.sol";

contract POASTest is Test {
    using stdJson for string;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RECIPIENT_ROLE = keccak256("RECIPIENT_ROLE");

    TransparentUpgradeableProxy public poasProxy;
    POAS public poasImplementation;
    POAS public poas;

    address public deployer;
    address public admin;
    address public operator;
    address public recipient1;
    address public recipient2;
    address public holder;

    address[] public recipientAddrs;
    string[] public recipientNames;
    string[] public recipientDescs;

    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
    event Paid(address indexed from, address indexed recipient, uint256 amount);
    event CollateralDeposited(uint256 amount);
    event CollateralWithdrawn(address indexed to, uint256 amount);
    event RecipientAdded(address indexed recipient, string name, string desc);
    event RecipientRemoved(address indexed recipient, string name);
    error POASError(string message);
    error POASMintError(string message);
    error POASBurnError(string message);
    error POASWithdrawCollateralError(string message);
    error POASPaymentError(string message);
    error POASAddRecipientError(string message);
    error POASRemoveRecipientError(string message);

    function setUp() public {
        // Deployment and initial setup
        deployer = makeAddr("deployer");
        admin = makeAddr("admin");
        operator = makeAddr("operator");
        recipient1 = makeAddr("recipient1");
        recipient2 = makeAddr("recipient2");
        holder = makeAddr("holder");

        recipientAddrs.push(recipient1);
        recipientAddrs.push(recipient2);
        recipientNames.push("Recipient 1");
        recipientNames.push("Recipient 2");
        recipientDescs.push("First recipient");
        recipientDescs.push("Second recipient");

        // Provide OAS to operator for collateral
        vm.deal(operator, 1 ether);

        {
            vm.startPrank(deployer);

            // Deploy POAS implementation contract
            poasImplementation = new POAS();

            // Deploy TransparentUpgradeableProxy
            poasProxy = new TransparentUpgradeableProxy(
                address(poasImplementation),
                deployer, // Owner of the Proxy itself
                abi.encodeWithSelector(
                    POAS.initialize.selector,
                    admin // Owner of POAS
                )
            );

            vm.stopPrank();
        }

        // Each test case calls POAS through the proxy
        poas = POAS(address(poasProxy));

        // Grant OPERATOR_ROLE to operator
        vm.prank(admin);
        poas.grantRole(OPERATOR_ROLE, operator);
    }

    /**
     * @dev Test that the implementation contract cannot be initialized
     */
    function test_preventInitializeImplementation() public {
        vm.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        vm.prank(admin);
        poasImplementation.initialize(admin);
    }

    /**
     * @dev Test that the contract cannot be re-initialized
     */
    function test_preventReInitialize() public {
        vm.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        vm.prank(admin);
        poas.initialize(admin);
    }

    /**
     * @dev Test that zero address cannot be specified as the initial admin
     */
    function test_preventZeroAddressInitialAdmin() public {
        vm.startPrank(deployer);

        vm.expectRevert(
            abi.encodeWithSelector(POASError.selector, "admin address is zero")
        );
        new TransparentUpgradeableProxy(
            address(poasImplementation),
            deployer,
            abi.encodeWithSelector(POAS.initialize.selector, address(0))
        );

        vm.stopPrank();
    }

    /**
     * @dev Test basic ERC20 attributes
     */
    function test_BasicERC20Attrs() public view {
        assertEq(poas.name(), "pOAS");
        assertEq(poas.symbol(), "POAS");
        assertEq(poas.decimals(), 18);
    }

    /**
     * @dev Test role state after initialization
     */
    function test_InitialRoles() public view {
        // Check role admin settings
        assertEq(poas.getRoleAdmin(ADMIN_ROLE), ADMIN_ROLE);
        assertEq(poas.getRoleAdmin(OPERATOR_ROLE), ADMIN_ROLE);
        assertEq(poas.getRoleAdmin(RECIPIENT_ROLE), ADMIN_ROLE);

        // Check if admin has ADMIN_ROLE
        assertEq(poas.hasRole(ADMIN_ROLE, admin), true);

        // Check that admin doesn't have unnecessary roles
        assertEq(poas.hasRole(OPERATOR_ROLE, admin), false);
        assertEq(poas.hasRole(RECIPIENT_ROLE, admin), false);
    }

    /**
     * @dev Test token minting
     */
    function test_mint() public {
        vm.expectEmit();
        emit Minted(holder, 1);

        vm.prank(operator);
        poas.mint(holder, 1);

        assertEq(poas.balanceOf(holder), 1);
        assertEq(poas.totalSupply(), 1);
        assertEq(poas.totalMinted(), 1);

        // Accounts without OPERATOR_ROLE cannot mint tokens
        vm.expectRevert(_makeRoleError(holder, OPERATOR_ROLE));
        vm.prank(holder);
        poas.mint(holder, 1);

        // Cannot mint zero amount
        vm.expectRevert(
            abi.encodeWithSelector(POASMintError.selector, "ammount is zero")
        );
        vm.prank(operator);
        poas.mint(holder, 0);
    }

    /**
     * @dev Test bulk token minting
     */
    function test_bulkMint() public {
        address[] memory accounts = new address[](2);
        accounts[0] = makeAddr("account0");
        accounts[1] = makeAddr("account1");

        uint256[] memory values = new uint256[](2);
        values[0] = 1;
        values[1] = 2;

        vm.expectEmit();
        emit Minted(accounts[0], 1);
        vm.expectEmit();
        emit Minted(accounts[1], 2);

        vm.prank(operator);
        poas.bulkMint(accounts, values);

        assertEq(poas.balanceOf(accounts[0]), 1);
        assertEq(poas.balanceOf(accounts[1]), 2);
        assertEq(poas.totalSupply(), 3);
        assertEq(poas.totalMinted(), 3);

        // Accounts without OPERATOR_ROLE cannot mint tokens
        vm.expectRevert(_makeRoleError(holder, OPERATOR_ROLE));
        vm.prank(holder);
        poas.bulkMint(accounts, values);

        // Error when account array and value array lengths don't match
        vm.expectRevert(
            abi.encodeWithSelector(
                POASMintError.selector,
                "array length mismatch"
            )
        );
        vm.prank(operator);
        poas.bulkMint(accounts, new uint256[](1));
    }

    /**
     * @dev Test token burning
     */
    function test_burn() public {
        vm.prank(operator);
        poas.mint(holder, 2);
        assertEq(poas.totalMinted(), 2);

        vm.expectEmit();
        emit Burned(holder, 1);

        vm.prank(holder);
        poas.burn(1);

        assertEq(poas.balanceOf(holder), 1);
        assertEq(poas.totalSupply(), 1);
        assertEq(poas.totalMinted(), 2); // Should not decrease
        assertEq(poas.totalBurned(), 1);

        // Cannot burn zero amount
        vm.expectRevert(
            abi.encodeWithSelector(POASBurnError.selector, "ammount is zero")
        );
        vm.prank(holder);
        poas.burn(0);
    }

    /**
     * @dev Test collateral deposit
     */
    function test_depositCollateral() public {
        vm.expectEmit();
        emit CollateralDeposited(1);

        vm.prank(operator);
        poas.depositCollateral{value: 1}();
        assertEq(address(poas).balance, 1);

        // Accounts without OPERATOR_ROLE cannot deposit collateral
        vm.deal(holder, 1);
        vm.prank(holder);
        vm.expectRevert(_makeRoleError(holder, OPERATOR_ROLE));
        poas.depositCollateral{value: 1}();
    }

    /**
     * @dev Test collateral withdrawal
     */
    function test_withdrawCollateral() public {
        vm.prank(operator);
        poas.depositCollateral{value: 2}();

        // Withdraw to an address different from operator
        address recipient = makeAddr("recipient");

        vm.expectEmit();
        emit CollateralWithdrawn(recipient, 1);

        vm.prank(operator);
        poas.withdrawCollateral(recipient, 1);
        assertEq(recipient.balance, 1);
        assertEq(address(poas).balance, 1);

        // Accounts without OPERATOR_ROLE cannot withdraw collateral
        vm.prank(holder);
        vm.expectRevert(_makeRoleError(holder, OPERATOR_ROLE));
        poas.withdrawCollateral(recipient, 1);

        // Insufficient collateral error
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                POASWithdrawCollateralError.selector,
                "insufficient collateral"
            )
        );
        poas.withdrawCollateral(recipient, 2);

        // Transfer failure error
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                POASWithdrawCollateralError.selector,
                "transfer failed"
            )
        );
        poas.withdrawCollateral(address(this), 1); // Should fail because this contract has no receive function
    }

    /**
     * @dev Test collateral ratio calculation
     */
    function test_getCollateralRatio() public {
        vm.prank(operator);
        poas.mint(holder, 10000);

        // 110% (over-collateralized)
        vm.deal(address(poas), 11000);
        assertEq(poas.getCollateralRatio(), 1_100_000_000 gwei); // = 1.1 ether

        // 100%
        vm.deal(address(poas), 10000);
        assertEq(poas.getCollateralRatio(), 1_000_000_000 gwei); // = 1 ether

        // 50%
        vm.deal(address(poas), 5000);
        assertEq(poas.getCollateralRatio(), 500_000_000 gwei); // = 0.5 ether

        // 12.34%
        vm.deal(address(poas), 1234);
        assertEq(poas.getCollateralRatio(), 123_400_000 gwei); // = 0.1234 ether

        // 1.23%
        vm.deal(address(poas), 123);
        assertEq(poas.getCollateralRatio(), 12_300_000 gwei); // = 0.0123 ether

        // 0.12%
        vm.deal(address(poas), 12);
        assertEq(poas.getCollateralRatio(), 1_200_000 gwei); // = 0.0012 ether

        // 0.1%
        vm.deal(address(poas), 1);
        assertEq(poas.getCollateralRatio(), 100_000 gwei); // = 0.0001 ether

        // 0%
        vm.deal(address(poas), 0);
        assertEq(poas.getCollateralRatio(), 0);
    }

    /**
     * @dev Test adding Recipients
     */
    function test_addRecipients() public {
        vm.expectEmit();
        emit RecipientAdded(recipient1, "Recipient 1", "First recipient");
        vm.expectEmit();
        emit RecipientAdded(recipient2, "Recipient 2", "Second recipient");

        vm.prank(admin);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);

        assertEq(poas.getRecipientCount(), 2);
        assertEq(poas.hasRole(RECIPIENT_ROLE, recipient1), true);
        assertEq(poas.hasRole(RECIPIENT_ROLE, recipient2), true);

        // Accounts without ADMIN_ROLE cannot add Recipients
        vm.expectRevert(_makeRoleError(operator, ADMIN_ROLE));
        vm.prank(operator);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);

        vm.startPrank(admin);

        // Array lengths must match
        vm.expectRevert(
            abi.encodeWithSelector(
                POASAddRecipientError.selector,
                "array length mismatch"
            )
        );
        poas.addRecipients(new address[](0), recipientNames, recipientDescs);

        vm.expectRevert(
            abi.encodeWithSelector(
                POASAddRecipientError.selector,
                "array length mismatch"
            )
        );
        poas.addRecipients(recipientAddrs, new string[](0), recipientDescs);

        vm.expectRevert(
            abi.encodeWithSelector(
                POASAddRecipientError.selector,
                "array length mismatch"
            )
        );
        poas.addRecipients(recipientAddrs, recipientNames, new string[](0));

        // Recipient cannot be zero address
        vm.expectRevert(
            abi.encodeWithSelector(
                POASAddRecipientError.selector,
                "recipient address is zero"
            )
        );
        poas.addRecipients(new address[](2), recipientNames, recipientDescs);

        // Name cannot be empty
        vm.expectRevert(
            abi.encodeWithSelector(
                POASAddRecipientError.selector,
                "name is empty"
            )
        );
        poas.addRecipients(recipientAddrs, new string[](2), recipientDescs);

        // Description cannot be empty
        vm.expectRevert(
            abi.encodeWithSelector(
                POASAddRecipientError.selector,
                "description is empty"
            )
        );
        poas.addRecipients(recipientAddrs, recipientNames, new string[](2));

        // Cannot add the same Recipient twice
        vm.expectRevert(
            abi.encodeWithSelector(
                POASAddRecipientError.selector,
                "already exists"
            )
        );
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);

        vm.stopPrank();
    }

    /**
     * @dev Test removing Recipients
     */
    function test_removeRecipients() public {
        address[] memory recipientsToRemove = new address[](1);
        recipientsToRemove[0] = recipient1;

        vm.prank(admin);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);

        vm.expectEmit();
        emit RecipientRemoved(recipient1, "Recipient 1");

        vm.prank(admin);
        poas.removeRecipients(recipientsToRemove);

        assertEq(poas.getRecipientCount(), 1);
        assertEq(poas.hasRole(RECIPIENT_ROLE, recipient1), false);
        assertEq(poas.hasRole(RECIPIENT_ROLE, recipient2), true);

        // Accounts without ADMIN_ROLE cannot remove Recipients
        vm.expectRevert(_makeRoleError(operator, ADMIN_ROLE));
        vm.prank(operator);
        poas.removeRecipients(recipientsToRemove);

        vm.startPrank(admin);

        // Recipient cannot be zero address
        vm.expectRevert(
            abi.encodeWithSelector(
                POASRemoveRecipientError.selector,
                "recipient address is zero"
            )
        );
        poas.removeRecipients(new address[](1));

        // Cannot remove a Recipient that doesn't have the role
        vm.expectRevert(
            abi.encodeWithSelector(
                POASRemoveRecipientError.selector,
                "recipient not found"
            )
        );
        poas.removeRecipients(recipientsToRemove);

        vm.stopPrank();
    }

    /**
     * @dev Test that direct addition of Recipients using grantRole is prohibited
     */
    function test_grantRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                POASAddRecipientError.selector,
                "use addRecipients instead"
            )
        );
        vm.prank(admin);
        poas.grantRole(RECIPIENT_ROLE, recipient1);

        // Verify that the implementation calls `super.grantRole` and not `super._grantRole`
        // which would bypass the onlyRole access control
        vm.expectRevert(_makeRoleError(holder, ADMIN_ROLE));
        vm.prank(holder);
        poas.grantRole(OPERATOR_ROLE, holder);
    }

    /**
     * @dev Test Recipient retrieval
     */
    function test_getRecipient() public {
        vm.prank(admin);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);

        (string memory name, string memory desc) = poas.getRecipient(
            recipient1
        );
        assertEq(name, "Recipient 1");
        assertEq(desc, "First recipient");

        // Non-existent Recipient
        vm.expectRevert(
            abi.encodeWithSelector(POASError.selector, "recipient not found")
        );
        poas.getRecipient(makeAddr("nonexistent"));
    }

    /**
     * @dev Test Recipient JSON retrieval
     */
    function test_getRecipientJSON() public {
        vm.prank(admin);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);

        string memory json = poas.getRecipientJSON(recipient1);
        assertEq(json.readAddress("$.address"), recipient1);
        assertEq(json.readString("$.name"), "Recipient 1");
        assertEq(json.readString("$.description"), "First recipient");

        // Non-existent Recipient
        vm.expectRevert(
            abi.encodeWithSelector(POASError.selector, "recipient not found")
        );
        poas.getRecipientJSON(makeAddr("nonexistent"));
    }

    /**
     * @dev Test retrieving the list of Recipients
     */
    function test_getRecipients() public {
        vm.startPrank(admin);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);

        // Add 50 additional Recipients
        (
            address[] memory additionalRecipientAddrs,
            string[] memory additionalRecipientNames
        ) = _makeRecipients(50);
        poas.addRecipients(
            additionalRecipientAddrs,
            additionalRecipientNames,
            additionalRecipientNames
        );

        uint256 nextCursor;
        uint256 size;
        address[] memory fetchedRecipients;
        string[] memory fetchedNames;
        string[] memory fetchedDescriptions;

        // If size is larger than the number of registered recipients, all are retrieved at once
        size = 100;
        (
            fetchedRecipients,
            fetchedNames,
            fetchedDescriptions,
            nextCursor
        ) = poas.getRecipients(nextCursor, size);
        assertEq(fetchedRecipients.length, 52);
        assertEq(fetchedRecipients[0], recipient1);
        assertEq(fetchedRecipients[51], additionalRecipientAddrs[49]);
        assertEq(fetchedNames.length, 52);
        assertEq(fetchedNames[0], "Recipient 1");
        assertEq(fetchedNames[51], "Additional Recipient 49");
        assertEq(fetchedDescriptions.length, 52);
        assertEq(fetchedDescriptions[0], "First recipient");
        assertEq(fetchedDescriptions[51], "Additional Recipient 49");
        assertEq(nextCursor, 52);

        // Pagination (first page)
        nextCursor = 0;
        size = 25;
        (
            fetchedRecipients,
            fetchedNames,
            fetchedDescriptions,
            nextCursor
        ) = poas.getRecipients(nextCursor, size);
        assertEq(fetchedRecipients.length, size);
        assertEq(fetchedRecipients[0], recipient1);
        assertEq(fetchedRecipients[24], additionalRecipientAddrs[22]);
        assertEq(fetchedNames.length, size);
        assertEq(fetchedNames[0], "Recipient 1");
        assertEq(fetchedNames[24], "Additional Recipient 22");
        assertEq(fetchedDescriptions.length, size);
        assertEq(fetchedDescriptions[0], "First recipient");
        assertEq(fetchedDescriptions[24], "Additional Recipient 22");
        assertEq(nextCursor, 25);

        // Pagination (second page)
        (
            fetchedRecipients,
            fetchedNames,
            fetchedDescriptions,
            nextCursor
        ) = poas.getRecipients(nextCursor, size);
        assertEq(fetchedRecipients.length, size);
        assertEq(fetchedRecipients[0], additionalRecipientAddrs[23]);
        assertEq(fetchedRecipients[24], additionalRecipientAddrs[47]);
        assertEq(fetchedNames.length, size);
        assertEq(fetchedNames[0], "Additional Recipient 23");
        assertEq(fetchedNames[24], "Additional Recipient 47");
        assertEq(fetchedDescriptions.length, size);
        assertEq(fetchedDescriptions[0], "Additional Recipient 23");
        assertEq(fetchedDescriptions[24], "Additional Recipient 47");
        assertEq(nextCursor, 50);

        // Pagination (third page)
        (
            fetchedRecipients,
            fetchedNames,
            fetchedDescriptions,
            nextCursor
        ) = poas.getRecipients(nextCursor, size);
        assertEq(fetchedRecipients.length, 2);
        assertEq(fetchedRecipients[0], additionalRecipientAddrs[48]);
        assertEq(fetchedRecipients[1], additionalRecipientAddrs[49]);
        assertEq(fetchedNames.length, 2);
        assertEq(fetchedNames[0], "Additional Recipient 48");
        assertEq(fetchedNames[1], "Additional Recipient 49");
        assertEq(fetchedDescriptions.length, 2);
        assertEq(fetchedDescriptions[0], "Additional Recipient 48");
        assertEq(fetchedDescriptions[1], "Additional Recipient 49");
        assertEq(nextCursor, 52);

        // After retrieving all entries, empty arrays are returned
        (
            fetchedRecipients,
            fetchedNames,
            fetchedDescriptions,
            nextCursor
        ) = poas.getRecipients(nextCursor, size);
        assertEq(fetchedRecipients.length, 0);
        assertEq(fetchedNames.length, 0);
        assertEq(fetchedDescriptions.length, 0);
        assertEq(nextCursor, 52);

        // If cursor is out of range, empty arrays are returned
        (fetchedRecipients, , , nextCursor) = poas.getRecipients(
            nextCursor + 100,
            size
        );
        assertEq(fetchedRecipients.length, 0);
        assertEq(nextCursor, 52);

        // Check that removing Recipients doesn't leave gaps
        address[] memory recipientsToRemove = new address[](1);
        recipientsToRemove[0] = additionalRecipientAddrs[0];
        poas.removeRecipients(recipientsToRemove);

        (fetchedRecipients, , , ) = poas.getRecipients(0, 100);
        assertEq(fetchedRecipients.length, 51);
        assertEq(fetchedRecipients[0], recipient1);
        assertEq(fetchedRecipients[1], recipient2);
        assertEq(fetchedRecipients[2], additionalRecipientAddrs[49]);
        assertEq(fetchedRecipients[3], additionalRecipientAddrs[1]);
        assertEq(fetchedRecipients[50], additionalRecipientAddrs[48]);

        vm.stopPrank();
    }

    /**
     * @dev Test retrieving the list of Recipients in JSON format
     */
    function test_getRecipientsJSON() public {
        vm.startPrank(admin);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);

        // Add 50 additional Recipients
        (
            address[] memory additionalRecipientAddrs,
            string[] memory additionalRecipientNames
        ) = _makeRecipients(50);
        poas.addRecipients(
            additionalRecipientAddrs,
            additionalRecipientNames,
            additionalRecipientNames
        );

        (string memory json, uint256 nextCursor) = poas.getRecipientsJSON(
            0,
            100
        );
        assertEq(json.readAddress("$.[0].address"), recipient1);
        assertEq(
            json.readAddress("$.[51].address"),
            additionalRecipientAddrs[49]
        );
        assertEq(json.readString("$.[0].name"), "Recipient 1");
        assertEq(json.readString("$.[51].name"), "Additional Recipient 49");
        assertEq(json.readString("$.[0].description"), "First recipient");
        assertEq(
            json.readString("$.[51].description"),
            "Additional Recipient 49"
        );
        assertEq(nextCursor, 52);

        vm.stopPrank();
    }

    /**
     * @dev Test payment processing
     */
    function test_transferFrom() public {
        // Add Recipients
        vm.prank(admin);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);

        // Add collateral
        vm.prank(operator);
        poas.depositCollateral{value: 100}();

        // Mint tokens
        vm.prank(operator);
        poas.mint(holder, 100);

        // Address that will perform payment
        address payOperator = makeAddr("payOperator");

        // Approve payOperator
        vm.prank(holder);
        poas.approve(payOperator, type(uint256).max);

        // Execute payment
        vm.expectEmit();
        emit Paid(holder, recipient1, 50);

        vm.prank(payOperator);
        poas.transferFrom(holder, recipient1, 50);

        // Token balance of the payer is burned
        assertEq(poas.balanceOf(holder), 50);
        assertEq(poas.totalSupply(), 50);
        assertEq(poas.totalBurned(), 50);

        // The recipient doesn't receive tokens
        assertEq(poas.balanceOf(recipient1), 0);

        // The recipient receives OAS
        assertEq(address(poas).balance, 50);
        assertEq(recipient1.balance, 50);

        // Token owner cannot pay directly
        vm.expectRevert(
            abi.encodeWithSelector(
                POASPaymentError.selector,
                "cannot pay from self"
            )
        );
        vm.prank(holder);
        poas.transferFrom(holder, recipient1, 100);

        // Non-existent recipient
        vm.expectRevert(
            abi.encodeWithSelector(
                POASPaymentError.selector,
                "recipient not found"
            )
        );
        vm.prank(payOperator);
        poas.transferFrom(holder, makeAddr("nonexistent"), 1);

        // Zero amount
        vm.expectRevert(
            abi.encodeWithSelector(POASPaymentError.selector, "ammount is zero")
        );
        vm.prank(payOperator);
        poas.transferFrom(holder, recipient1, 0);

        // Insufficient collateral
        vm.expectRevert(
            abi.encodeWithSelector(
                POASPaymentError.selector,
                "insufficient collateral"
            )
        );
        vm.prank(payOperator);
        poas.transferFrom(holder, recipient1, 51);

        // Caller is not payOperator (not approved)
        vm.expectRevert(bytes("ERC20: insufficient allowance"));
        vm.prank(admin);
        poas.transferFrom(holder, recipient1, 1);

        // Recipient contract doesn't implement receive function
        address[] memory additionalRecipientAddrs = new address[](1);
        string[] memory additionalRecipientNames = new string[](1);
        additionalRecipientAddrs[0] = address(this);
        additionalRecipientNames[0] = "this";
        vm.prank(admin);
        poas.addRecipients(
            additionalRecipientAddrs,
            additionalRecipientNames,
            additionalRecipientNames
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                POASPaymentError.selector,
                "transfer failed to recipient"
            )
        );
        vm.prank(payOperator);
        poas.transferFrom(holder, additionalRecipientAddrs[0], 1);
    }

    /**
     * @dev Test that the transfer function is disabled
     */
    function test_transfer() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                POASPaymentError.selector,
                "cannot pay with transfer"
            )
        );
        vm.prank(holder);
        poas.transfer(recipient1, 1);
    }

    /**
     * @dev Test contract upgradeability
     */
    function test_UpgradeImplementation() public {
        ITransparentUpgradeableProxy ipoasProxy = ITransparentUpgradeableProxy(
            address(poasProxy)
        );

        vm.prank(operator);
        poas.mint(holder, 100);

        // Upgrade implementation
        {
            vm.startPrank(deployer);

            POAS newImplementation = new POAS();

            ipoasProxy.upgradeTo(address(newImplementation));
            assertEq(ipoasProxy.implementation(), address(newImplementation));

            vm.stopPrank();
        }

        // Verify that the upgraded contract still references the same storage
        poas = POAS(address(poasProxy));
        assertEq(poas.totalSupply(), 100);
    }

    function _makeRoleError(
        address account,
        bytes32 role
    ) internal pure returns (bytes memory err) {
        err = bytes(
            string.concat(
                "AccessControl: account ",
                vm.toLowercase(vm.toString(account)),
                " is missing role ",
                vm.toString(role)
            )
        );
    }

    function _makeRecipients(
        uint256 _num
    ) internal returns (address[] memory addrs, string[] memory names) {
        addrs = new address[](_num);
        names = new string[](_num);
        for (uint256 i = 0; i < _num; i++) {
            names[i] = string.concat("Additional Recipient ", vm.toString(i));
            addrs[i] = makeAddr(names[i]);
        }
    }
}
