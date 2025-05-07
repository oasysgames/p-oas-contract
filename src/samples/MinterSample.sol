// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPOAS} from "../interfaces/IPOAS.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title MinterSample
 * @dev A sample contract demonstrating how to mint POAS tokens
 * This contract serves as an operator for a POAS token contract, allowing
 * authorized entities to mint tokens after depositing the required collateral.
 * The contract is designed to be deployed behind a proxy for upgradeability.
 */
contract MinterSample is Initializable {
    /// @dev Interface instance for interacting with the POAS token contract.
    IPOAS public poas;

    /**
     * @dev Modifier to ensure the contract has the OPERATOR_ROLE in the POAS contract.
     * Reverts if this contract does not have the required role.
     */
    modifier hasOperatorRole() {
        require(
            poas.hasRole(poas.OPERATOR_ROLE(), address(this)),
            "Contract needs OPERATOR_ROLE"
        );
        _;
    }

    /**
     * @dev Initializes the contract by setting the POAS token address
     * @param poasAddress The address of the deployed POAS token contract
     * @notice This function can only be called once due to the initializer modifier
     */
    function initialize(address poasAddress) public virtual initializer {
        poas = IPOAS(poasAddress);
    }

    /**
     * @dev Mints POAS tokens for the caller
     * @param amount The amount of tokens to mint (in wei)
     * @notice The caller must send exactly the OAS amount that matches the token amount
     * @notice Contract must have OPERATOR_ROLE to execute this function
     */
    function mint(uint256 amount) public payable hasOperatorRole {
        _mint(msg.sender, amount);
    }

    /**
     * @dev Mints POAS tokens for a specified account
     * @param account The address that will receive the minted tokens
     * @param amount The amount of tokens to mint (in wei)
     * @notice The caller must send exactly the OAS amount that matches the token amount
     * @notice Contract must have OPERATOR_ROLE to execute this function
     */
    function mint(
        address account,
        uint256 amount
    ) public payable hasOperatorRole {
        _mint(account, amount);
    }

    /**
     * @dev Mints POAS tokens for multiple accounts in a single transaction
     * @param accounts Array of addresses that will receive the minted tokens
     * @param amounts Array of token amounts to mint for each corresponding address
     * @notice The caller must send exactly the OAS amount that matches the sum of all amounts
     * @notice Contract must have OPERATOR_ROLE to execute this function
     */
    function bulkMint(
        address[] calldata accounts,
        uint256[] calldata amounts
    ) public payable hasOperatorRole {
        _validate(accounts, amounts);

        _deposit();
        poas.bulkMint(accounts, amounts);
    }

    /**
     * @dev Validates the accounts and amounts arrays
     * @param accounts Array of addresses that will receive tokens
     * @param amounts Array of token amounts to mint
     * @notice Checks that:
     * - Both arrays have the same length
     * - No address is the zero address
     * - No amount is zero
     * - The sum of amounts equals the sent OAS value
     */
    function _validate(
        address[] memory accounts,
        uint256[] memory amounts
    ) internal virtual {
        require(accounts.length == amounts.length, "Arrays length mismatch");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != address(0), "Empty address");
            require(amounts[i] > 0, "Empty amount");
            totalAmount += amounts[i];
        }

        require(totalAmount == msg.value, "Sum of amounts mismatch value");
    }

    /**
     * @dev Internal function to mint tokens for a single account
     * @param account The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     * @notice Converts single address and amount into arrays for validation
     * @notice Deposits collateral and calls the POAS mint function
     */
    function _mint(address account, uint256 amount) internal virtual {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        _validate(accounts, amounts);

        _deposit();
        poas.mint(account, amount);
    }

    /**
     * @dev Deposits the OAS collateral to the POAS contract
     * @notice Forwards all the OAS value sent in the transaction
     */
    function _deposit() internal virtual {
        poas.depositCollateral{value: msg.value}();
    }
}
