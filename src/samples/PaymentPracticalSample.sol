// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {IPOAS} from "../interfaces/IPOAS.sol";

/**
 * @title PaymentPracticalSample
 * @dev This contract facilitates payments using both POAS tokens and native currency.
 *      It integrates with an external contract and manages payment records.
 */
contract PaymentPracticalSample is OwnableUpgradeable {
    /// @dev Interface instance for interacting with the POAS token contract.
    IPOAS public poas;

    /// @dev Address of the external contract to be called after payments.
    address public exContract;

    /// @dev Mapping to track payments made by each address.
    mapping(address => uint256) public payments;

    /// @dev Price required for making a payment.
    uint256 private _price;

    /// @dev Emitted when a payment is received.
    event PaymentReceived(address indexed from, uint256 amount);

    /// @dev Emitted when funds are withdrawn from the contract.
    event Withdrawn(address indexed to, uint256 amount);

    /**
     * @dev Modifier to ensure the contract has the RECIPIENT_ROLE in the POAS contract.
     */
    modifier hasRecipientRole() {
        require(
            poas.hasRole(poas.RECIPIENT_ROLE(), address(this)),
            "Contract needs RECIPIENT_ROLE"
        );
        _;
    }

    /**
     * @dev Fallback function to receive Ether.
     */
    receive() external payable {}

    /**
     * @dev Initializes the contract with the POAS contract address, payment price, and external contract address.
     * @param poasAddress Address of the POAS token contract.
     * @param price_ Initial price for payments.
     * @param exContract_ Address of the external contract to be called after payments.
     */
    function initialize(
        address poasAddress,
        uint256 price_,
        address exContract_
    ) public virtual initializer {
        __Ownable_init();

        poas = IPOAS(poasAddress);
        _price = price_;
        if (exContract_ != address(0)) {
            exContract = exContract_;
        }
    }

    /**
     * @dev Returns the current price for payments.
     * @return The current price.
     */
    function price() public view virtual returns (uint256) {
        return _price;
    }

    /**
     * @dev Sets a new price for payments. Can only be called by the contract owner.
     * @param price_ New price to be set.
     */
    function setPrice(uint256 price_) public virtual onlyOwner {
        _price = price_;
    }

    /**
     * @dev Sets a new external contract address. Can only be called by the contract owner.
     * @param exContract_ New external contract address.
     */
    function setExContract(address exContract_) public virtual onlyOwner {
        exContract = exContract_;
    }

    /**
     * @dev Allows a user with the RECIPIENT_ROLE to make a payment using POAS tokens.
     *      Transfers the specified price from the sender to this contract.
     */
    function pay() external hasRecipientRole {
        _pay("");
    }

    /**
     * @dev Accept calldata from the user and pass it to the external contract.
     * @param data Additional data to be passed along with the payment.
     */
    function pay(bytes calldata data) external hasRecipientRole {
        _pay(data);
    }

    /**
     * @dev Allows a user to make a payment using native currency (Ether).
     *      Requires the sent amount to match the specified price.
     */
    function payByNative() external payable {
        _payByNative("");
    }

    /**
     * @dev Accept calldata from the user and pass it to the external contract.
     * @param data Additional data to be passed along with the payment.
     */
    function payByNative(bytes calldata data) external payable {
        _payByNative(data);
    }

    /**
     * @dev Withdraws a specified amount of Ether from the contract to a recipient address.
     *      Can only be called by the contract owner.
     * @param recipient Address to receive the withdrawn funds.
     * @param amount Amount of Ether to withdraw.
     */
    function withdraw(address recipient, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
        emit Withdrawn(recipient, amount);
    }

    function _pay(bytes memory data) internal virtual {
        address from = msg.sender;
        uint256 price_ = price();
        _validateAllowance(from, price_);

        poas.transferFrom(from, address(this), price_);

        _afterPayment(from, price_, data);
    }

    function _payByNative(bytes memory data) internal virtual {
        address from = msg.sender;
        uint256 price_ = price();
        _validatePayment(msg.value, price_);

        _afterPayment(from, price_, data);
    }

    /**
     * @dev Validates that the sender has approved sufficient POAS tokens for transfer.
     * @param from Address of the sender.
     * @param price_ Amount required for the payment.
     */
    function _validateAllowance(address from, uint256 price_) internal view {
        uint256 allowance = poas.allowance(from, address(this));
        if (allowance < price_) {
            revert(
                string.concat(
                    "Allowance not enough. Current allowance: ",
                    StringsUpgradeable.toString(allowance),
                    ", required: ",
                    StringsUpgradeable.toString(price_)
                )
            );
        }
    }

    /**
     * @dev Validates that the sent Ether amount matches the required price.
     * @param amount Amount of Ether sent.
     * @param price_ Expected payment amount.
     */
    function _validatePayment(uint256 amount, uint256 price_) internal pure {
        if (amount != price_) {
            revert(
                string.concat(
                    "Invalid payment amount. Expected: ",
                    StringsUpgradeable.toString(price_),
                    ", received: ",
                    StringsUpgradeable.toString(amount)
                )
            );
        }
    }

    /**
     * @dev Creates the calldata for the external contract call after payment.
     *      Can be overridden to customize the calldata format.
     * @param buyer Address of the buyer making the payment.
     * @param price_ Amount paid by the buyer.
     * @param data_ Additional data to be passed to the external contract.
     * @return Calldata to be sent to the external contract.
     */
    function _createCalldata(
        address buyer,
        uint256 price_,
        bytes memory data_
    ) internal virtual returns (bytes memory) {
        bytes4 selector = bytes4(keccak256("onPaied(address,uint256,bytes)"));
        bytes memory encodedArgs = abi.encode(buyer, price_, data_);
        return abi.encodePacked(selector, encodedArgs);
    }

    /**
     * @dev Executes a call to the external contract if an external contract address is set.
     *      Reverts if the external call fails.
     * @param buyer Address of the buyer making the payment.
     * @param price_ Amount paid by the buyer.
     * @param data_ Additional data to be passed to the external contract.
     */
    function _exCallIfNeed(
        address buyer,
        uint256 price_,
        bytes memory data_
    ) internal virtual {
        if (exContract != address(0)) {
            bytes memory data = _createCalldata(buyer, price_, data_);
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory reason) = exContract.call(data);
            if (!success) {
                if (reason.length > 0) {
                    // If the call failed and a reason was returned, revert with the reason
                    // solhint-disable-next-line no-inline-assembly
                    assembly {
                        let size := mload(reason)
                        revert(add(32, reason), size)
                    }
                } else {
                    // If the call failed and no reason was returned, revert with a default message
                    revert("Failed external call, no reason");
                }
            }
        }
    }

    /**
     * @dev Handles post-payment logic, including recording the payment
     *      and calling the external contract if configured.
     * @param buyer Address of the buyer making the payment.
     * @param price_ Amount paid by the buyer.
     * @param data_ Additional data to be passed to the external contract.
     */
    function _afterPayment(
        address buyer,
        uint256 price_,
        bytes memory data_
    ) internal virtual {
        // Record the payment made by the buyer
        payments[buyer] += price_;

        // Call the external contract with buyer and price info if needed
        _exCallIfNeed(buyer, price_, data_);

        // Emit event for successful payment
        emit PaymentReceived(buyer, price_);
    }
}
