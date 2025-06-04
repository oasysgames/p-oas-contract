// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {POAS} from "../src/POAS.sol";
import {PaymentPracticalSample} from "../src/samples/PaymentPracticalSample.sol";
import {IPOAS} from "../src/interfaces/IPOAS.sol";

contract ExContract {
    mapping(address => uint256) public payments;
    bool public flgErr;
    bool public flgCustomErr;
    bytes public data;

    error ExContractError(address buyer, uint256 price, string message);

    function onPaid(
        address buyer,
        uint256 price,
        bytes calldata data_
    ) external {
        if (flgCustomErr) {
            revert ExContractError(buyer, price, "ExContract: custom error");
        }
        if (flgErr) {
            revert("ExContract: error");
        }
        payments[buyer] += price;
        data = data_;
    }

    function onFlgErr() external {
        flgErr = true;
    }

    function onFlgCustomErr() external {
        flgCustomErr = true;
    }
}

contract PaymentPracticalSampleTest is Test {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RECIPIENT_ROLE = keccak256("RECIPIENT_ROLE");

    TransparentUpgradeableProxy public poasProxy;
    POAS public poasImplementation;
    POAS public poas;

    TransparentUpgradeableProxy public paymentProxy;
    PaymentPracticalSample public payment;
    ExContract public exContract;

    address public deployer;
    address public poasAdmin;
    address public poasOperator;

    address public buyer1;
    address public buyer2;

    address[] public recipientAddrs;
    string[] public recipientNames;
    string[] public recipientDescs;

    uint256 public price = 1 ether;

    event PaymentReceived(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    error ExContractError(address buyer, uint256 price, string message);

    function setUp() public {
        // Deployment and initial setup
        deployer = makeAddr("deployer");
        poasAdmin = makeAddr("poasAdmin");
        poasOperator = makeAddr("poasOperator");
        buyer1 = makeAddr("buyer1");
        buyer2 = makeAddr("buyer2");

        // Deploy cntracts
        {
            vm.startPrank(deployer);

            exContract = new ExContract();

            poasImplementation = new POAS();
            poasProxy = new TransparentUpgradeableProxy(
                address(poasImplementation),
                deployer, // Owner of the Proxy itself
                abi.encodeWithSelector(POAS.initialize.selector, poasAdmin)
            );

            payment = new PaymentPracticalSample();
            payment.initialize(address(poasProxy), price, address(exContract));
            paymentProxy = new TransparentUpgradeableProxy(
                address(payment),
                deployer, // Owner of the Proxy itself
                abi.encodeWithSelector(
                    PaymentPracticalSample.initialize.selector,
                    poasProxy,
                    price,
                    exContract
                )
            );

            vm.stopPrank();
        }

        poas = POAS(address(poasProxy));

        vm.prank(poasAdmin);
        poas.grantRole(OPERATOR_ROLE, poasOperator);

        vm.prank(poasOperator);
        poas.mint(buyer1, price);

        vm.deal(poasOperator, price);
        vm.deal(buyer2, price);

        vm.prank(poasOperator);
        poas.depositCollateral{value: price}();

        recipientAddrs.push(address(payment));
        recipientNames.push("name");
        recipientDescs.push("description");
    }

    function test_pay() public {
        vm.prank(poasOperator);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);

        vm.prank(buyer1);
        poas.approve(address(payment), price);

        poas.allowance(buyer1, address(payment));
        assertEq(poas.allowance(buyer1, address(payment)), price);

        vm.expectEmit();
        emit PaymentReceived(buyer1, price);

        vm.prank(buyer1);
        payment.pay();

        assertEq(payment.payments(buyer1), price);
        assertEq(exContract.payments(buyer1), price);
        assertEq(address(payment).balance, price);
    }

    function test_pay_withCalldata() public {
        vm.prank(poasOperator);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);

        vm.prank(buyer1);
        poas.approve(address(payment), price);

        poas.allowance(buyer1, address(payment));
        assertEq(poas.allowance(buyer1, address(payment)), price);

        vm.expectEmit();
        emit PaymentReceived(buyer1, price);

        bytes memory _data = "test data";
        vm.prank(buyer1);
        payment.pay(_data);

        assertEq(payment.payments(buyer1), price);
        assertEq(exContract.payments(buyer1), price);
        assertEq(exContract.data().length, _data.length);
        assertEq(address(payment).balance, price);
    }

    function test_pay_reverts() public {
        // Case: No mayment role
        vm.expectRevert("Contract needs RECIPIENT_ROLE");
        vm.prank(buyer1);
        payment.pay();

        // Case: Not enough allowance
        vm.prank(poasOperator);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);
        vm.expectRevert(
            "Allowance not enough. Current allowance: 0, required: 1000000000000000000"
        );
        vm.prank(buyer1);
        payment.pay();

        // Case: ExContract error
        exContract.onFlgErr();
        vm.prank(buyer1);
        poas.approve(address(payment), price);
        vm.expectRevert("ExContract: error");
        vm.prank(buyer1);
        payment.pay();

        // Case: ExContract custom error
        exContract.onFlgCustomErr();
        vm.expectRevert(
            abi.encodeWithSelector(
                ExContractError.selector,
                buyer1,
                price,
                "ExContract: custom error"
            )
        );
        vm.prank(buyer1);
        payment.pay();
    }

    function test_payByNative() public {
        vm.expectEmit();
        emit PaymentReceived(buyer2, price);

        vm.prank(buyer2);
        payment.payByNative{value: price}();

        assertEq(payment.payments(buyer2), price);
        assertEq(exContract.payments(buyer2), price);
        assertEq(address(payment).balance, price);
    }

    function test_payByNative_withCalldata() public {
        vm.expectEmit();
        emit PaymentReceived(buyer2, price);

        bytes memory _data = "test data";
        vm.prank(buyer2);
        payment.payByNative{value: price}(_data);

        assertEq(payment.payments(buyer2), price);
        assertEq(exContract.payments(buyer2), price);
        assertEq(exContract.data().length, _data.length);
        assertEq(address(payment).balance, price);
    }

    function test_payByNative_reverts() public {
        // Case: Invalid payment amount
        vm.expectRevert(
            "Invalid payment amount. Expected: 1000000000000000000, received: 1000000000"
        );
        vm.prank(buyer2);
        payment.payByNative{value: 1 gwei}();
    }

    function test_withdraw() public {
        vm.prank(poasOperator);
        poas.addRecipients(recipientAddrs, recipientNames, recipientDescs);
        vm.prank(buyer1);
        poas.approve(address(payment), price);
        vm.prank(buyer1);
        payment.pay();
        vm.prank(buyer2);
        payment.payByNative{value: price}();

        vm.expectEmit();
        emit Withdrawn(deployer, price * 2);

        vm.prank(deployer);
        payment.withdraw(deployer, price * 2);

        assertEq(address(deployer).balance, price * 2);
    }

    function test_withdraw_reverts() public {
        vm.prank(buyer2);
        payment.payByNative{value: price}();

        // Case: Not owner
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(buyer1);
        payment.withdraw(buyer1, price);

        // Case: Insufficient balance
        vm.expectRevert("Insufficient balance");
        vm.prank(deployer);
        payment.withdraw(deployer, price * 2);
    }

    function test_setPrice() public {
        vm.prank(deployer);
        payment.setPrice(2 ether);
        assertEq(payment.price(), 2 ether);
    }

    function test_setPrice_reverts() public {
        // Case: Not owner
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(buyer1);
        payment.setPrice(2 ether);
    }

    function test_setExContract() public {
        vm.prank(deployer);
        payment.setExContract(address(0));
        assertEq(payment.exContract(), address(0));
    }

    function test_setExContract_reverts() public {
        // Case: Not owner
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(buyer1);
        payment.setExContract(address(0));
    }

    function test_UpgradeImplementation() public {
        ITransparentUpgradeableProxy ipaymentProxy = ITransparentUpgradeableProxy(
                address(paymentProxy)
            );

        PaymentPracticalSample _payment = PaymentPracticalSample(
            payable(address(paymentProxy))
        );

        address[] memory _recipientAddrs = new address[](1);
        _recipientAddrs[0] = address(paymentProxy);
        vm.prank(poasOperator);
        poas.addRecipients(_recipientAddrs, recipientNames, recipientDescs);
        vm.prank(buyer2);
        _payment.payByNative{value: price}();

        // Upgrade implementation
        {
            vm.startPrank(deployer);

            PaymentPracticalSample newImplementation = new PaymentPracticalSample();

            ipaymentProxy.upgradeTo(address(newImplementation));
            assertEq(
                ipaymentProxy.implementation(),
                address(newImplementation)
            );

            vm.stopPrank();
        }

        vm.prank(buyer1);
        poas.approve(address(paymentProxy), price);
        vm.prank(buyer1);
        _payment.pay();

        assertEq(_payment.payments(buyer1), price);
        assertEq(exContract.payments(buyer1), price);
        assertEq(_payment.payments(buyer2), price);
        assertEq(exContract.payments(buyer2), price);
        assertEq(address(paymentProxy).balance, price * 2);
    }
}
