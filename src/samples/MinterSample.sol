// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPOAS} from "../interfaces/IPOAS.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title MinterSample
 * @dev Sample implementation of a minting contract for POAS tokens with:
 * - Whitelist functionality
 * - Mint cap limitations
 * - Adjustable mint rates
 * - Upgradeable ownership pattern
 */
contract MinterSample is OwnableUpgradeable {
    /// @dev Interface instance for interacting with the POAS token contract.
    IPOAS public poas;

    /// @dev Maximum allowable amount of tokens that can be minted through this contract
    uint256 public mintCap;

    /// @dev Maximum allowable amount of tokens that can be minted through this contract
    uint256 public mintedAmount;

    /// @dev Mint rate in basis points (1 = 0.01%, 100 = 1%, 10000 = 100%)
    ///      Default 100 (1:1 ratio between deposited OAS and minted POAS)
    uint16 public mintRate = 100;

    /// @dev List of whitelisted addresses allowed to mint
    address[] public whitelist;

    /// @dev Mapping for quick whitelist status verification
    mapping(address => bool) public whitelistMap;

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
     * @dev Modifier to ensure the minting amount does not exceed the mint cap.
     * Reverts if the mint cap is exceeded.
     * Update minted amount after the function execution
     */
    modifier withinMintCap() {
        uint256 mintAmount = _mintAmount(msg.value);
        require(mintAmount <= mintCap, "Mint cap exceeded");
        _;
        mintedAmount += mintAmount;
    }

    /**
     * @dev Initializes the contract by setting the POAS token address
     * @param poasAddress The address of the deployed POAS token contract
     * @notice This function can only be called once due to the initializer modifier
     */
    function initialize(
        address owner,
        address poasAddress,
        uint256 mintCap_
    ) public virtual initializer {
        _transferOwnership(owner);
        poas = IPOAS(poasAddress);
        mintCap = mintCap_;
    }

    /**
     * @dev Mints POAS tokens for the caller
     * @param depositAmount The amount of OAS to deposit (in wei)
     * @notice The caller must send exactly the OAS amount that matches the token amount
     * @notice Contract must have OPERATOR_ROLE to execute this function
     */
    function mint(
        uint256 depositAmount
    ) public payable virtual hasOperatorRole withinMintCap {
        _mint(msg.sender, depositAmount);
    }

    /**
     * @dev Mints POAS tokens for a specified account
     * @param account The address that will receive the minted tokens
     * @param depositAmount The amount of OAS to deposit (in wei)
     * @notice The caller must send exactly the OAS amount that matches the token amount
     * @notice Contract must have OPERATOR_ROLE to execute this function
     */
    function mint(
        address account,
        uint256 depositAmount
    ) public payable virtual hasOperatorRole withinMintCap {
        _mint(account, depositAmount);
    }

    /**
     * @dev Mints POAS tokens for multiple accounts in a single transaction
     * @param accounts Array of addresses that will receive the minted tokens
     * @param depositAmounts Array of token amounts to mint for each corresponding address
     * @notice The caller must send exactly the OAS amount that matches the sum of all amounts
     * @notice Contract must have OPERATOR_ROLE to execute this function
     */
    function bulkMint(
        address[] calldata accounts,
        uint256[] calldata depositAmounts
    ) public payable virtual hasOperatorRole withinMintCap {
        require(
            accounts.length == depositAmounts.length,
            "Arrays length mismatch"
        );

        uint256 sum = 0;
        for (uint256 i = 0; i < accounts.length; ++i) {
            require(accounts[i] != address(0), "Empty address");
            require(whitelistMap[accounts[i]] == true, "Not whitelisted");
            require(depositAmounts[i] > 0, "Empty amount");

            sum += depositAmounts[i];
            poas.mint(accounts[i], _mintAmount(depositAmounts[i]));
        }

        require(sum == msg.value, "Sum of amounts mismatch value");

        _deposit();
    }

    /**
     * @dev Adds multiple addresses to the whitelist
     * @param accounts Array of addresses to be added to the whitelist
     */
    function addWhitelist(address[] calldata accounts) public onlyOwner {
        require(accounts.length > 0, "Empty array");
        for (uint256 i = 0; i < accounts.length; ++i) {
            require(accounts[i] != address(0), "Empty address");
            require(whitelistMap[accounts[i]] == false, "Already whitelisted");

            whitelist.push(accounts[i]);
            whitelistMap[accounts[i]] = true;
        }
    }

    /**
     * @dev Removes multiple addresses from the whitelist
     * @param accounts Array of addresses to be removed from the whitelist
     */
    function removeWhitelist(address[] calldata accounts) public onlyOwner {
        require(accounts.length > 0, "Empty array");
        for (uint256 i = 0; i < accounts.length; ++i) {
            require(accounts[i] != address(0), "Empty address");
            require(whitelistMap[accounts[i]] == true, "Not whitelisted");

            for (uint256 j = 0; j < whitelist.length; ++j) {
                if (whitelist[j] == accounts[i]) {
                    whitelist[j] = whitelist[whitelist.length - 1];
                    whitelist.pop();
                    break;
                }
            }

            delete whitelistMap[accounts[i]];
        }
    }

    /**
     * @dev Updates the mint cap
     * @param mintCap_ The new mint cap value
     */
    function updateMintCap(uint256 mintCap_) public onlyOwner {
        require(mintCap_ > mintedAmount, "Cap must be greater than minted");
        mintCap = mintCap_;
    }

    /**
     * @dev Updates the mint rate
     * @param mintRate_ The new mint rate value in basis points (1 = 0.01%, 100 = 1%, 10000 = 100%)
     */
    function updateMintRate(uint16 mintRate_) public onlyOwner {
        require(mintRate_ > 0, "Rate must be greater than 0");
        require(mintRate_ < 10000, "Rate must be less than 10000");

        mintRate = mintRate_;
    }

    /**
     * @dev Internal function to calculate the mint amount based on the deposit amount
     * @param amount The amount of OAS to deposit (in wei)
     * @return The calculated mint amount based on the mint rate
     */
    function _mintAmount(
        uint256 amount
    ) internal view virtual returns (uint256) {
        return (amount * mintRate) / 100;
    }

    /**
     * @dev Internal function to mint tokens for a single account
     * @param account The address that will receive the minted tokens
     * @param depositAmount The amount of OAS to deposit (in wei)
     * @notice Converts single address and amount into arrays for validation
     * @notice Deposits collateral and calls the POAS mint function
     */
    function _mint(address account, uint256 depositAmount) internal virtual {
        require(account != address(0), "Empty address");
        require(whitelistMap[account] == true, "Not whitelisted");
        require(depositAmount == msg.value, "Amount mismatch");

        poas.mint(account, _mintAmount(depositAmount));
        _deposit();
    }

    /**
     * @dev Deposits the OAS collateral to the POAS contract
     * @notice Forwards all the OAS value sent in the transaction
     */
    function _deposit() internal virtual {
        poas.depositCollateral{value: msg.value}();
    }
}
