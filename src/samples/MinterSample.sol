// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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

    /// @dev Tracks the total amount of tokens minted through this contract
    uint256 public mintedAmount;

    /// @dev Mint rate expressed as a percentage where 100 means 100%
    /// @dev Allow free minting by setting rate to 0
    uint16 public mintRate;

    /// @dev Default mint rate expressed as a percentage where 100 means 100%
    uint16 public constant DEFAULT_MINTRATE = 100;

    /// @dev A flag to disable whitelist checks
    bool public disableWhitelistCheck;

    /// @dev List of whitelisted addresses allowed to mint
    address[] public whitelist;

    /// @dev Mapping for each whitelisted address to its remaining mint allowance
    mapping(address => uint256) public whitelistWithAllowanceMap;

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
     * @dev MRestricts function access to only whitelisted addresses,
     * unless whitelist checking is explicitly disabled.
     */
    modifier onlyWhitelisted() {
        require(
            disableWhitelistCheck || whitelistWithAllowanceMap[msg.sender] > 0,
            "Not whitelisted or no allowance"
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
        require(
            mintedAmount + mintAmount <= mintCap,
            "Total mint cap exceeded"
        );
        if (!disableWhitelistCheck) {
            require(
                whitelistWithAllowanceMap[msg.sender] >= mintAmount,
                "Mint cap exceeded"
            );
        }
        _;
        mintedAmount += mintAmount;
        if (!disableWhitelistCheck) {
            whitelistWithAllowanceMap[msg.sender] -= mintAmount;
        }
    }

    function OPERATOR_ROLE() external pure returns (bytes32) {
        return keccak256("OPERATOR_ROLE");
    }

    function hasRole(
        bytes32 /* role */,
        address /* account */
    ) external pure returns (bool) {
        return true;
    }

    /**
     * @dev Initializes the contract by setting the POAS token address
     * @param poasAddress The address of the deployed POAS token contract
     * @param mintCap_ The maximum amount of tokens that can be minted through this contract
     * @param disableWhitelistCheck_ A flag to disable whitelist checks
     * @notice This function can only be called once due to the initializer modifier
     */
    function initialize(
        address owner,
        address poasAddress,
        uint256 mintCap_,
        bool disableWhitelistCheck_
    ) public virtual initializer {
        _transferOwnership(owner);
        poas = IPOAS(poasAddress);
        mintCap = mintCap_;
        // To support proxy, we set mint rate here, avoid directly in code
        //  uint16 public mintRate; <- this will return 0 in proxy
        mintRate = DEFAULT_MINTRATE;
        disableWhitelistCheck = disableWhitelistCheck_;
        // Add the owner to the whitelist by default with full allowance
        whitelistWithAllowanceMap[owner] = mintCap_;
    }

    /**
     * @dev Mints POAS tokens for the caller
     * @param depositAmount The amount of OAS to deposit (in wei)
     * @notice The caller must send exactly the OAS amount that matches the token amount
     * @notice Contract must have OPERATOR_ROLE to execute this function
     */
    function mint(
        uint256 depositAmount
    ) public payable virtual hasOperatorRole onlyWhitelisted withinMintCap {
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
    ) public payable virtual hasOperatorRole onlyWhitelisted withinMintCap {
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
    ) public payable virtual hasOperatorRole onlyWhitelisted withinMintCap {
        require(
            accounts.length == depositAmounts.length,
            "Arrays length mismatch"
        );

        uint256 sum = 0;
        for (uint256 i = 0; i < accounts.length; ++i) {
            require(accounts[i] != address(0), "Empty address");
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
    function addWhitelist(
        address[] calldata accounts,
        uint256[] calldata caps
    ) public onlyOwner {
        require(accounts.length > 0, "Empty array");
        require(accounts.length == caps.length, "Arrays length mismatch");
        for (uint256 i = 0; i < accounts.length; ++i) {
            require(accounts[i] != address(0), "Empty address");

            if (whitelistWithAllowanceMap[accounts[i]] == 0) {
                whitelist.push(accounts[i]);
            }

            whitelistWithAllowanceMap[accounts[i]] += caps[i];
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
            require(
                whitelistWithAllowanceMap[accounts[i]] != 0,
                "Not whitelisted or no allowance"
            );

            for (uint256 j = 0; j < whitelist.length; ++j) {
                if (whitelist[j] == accounts[i]) {
                    whitelist[j] = whitelist[whitelist.length - 1];
                    whitelist.pop();
                    break;
                }
            }

            delete whitelistWithAllowanceMap[accounts[i]];
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
     * @param mintRate_ The new mint rate value expressed as a percentage where 100 = 100%
     */
    function updateMintRate(uint16 mintRate_) public onlyOwner {
        // Allow free minting by setting rate to 0
        // require(mintRate_ > 0, "Rate must be greater than 0");
        require(mintRate_ < 10000, "Rate must be less than 10000");

        mintRate = mintRate_;
    }

    /**
     * @dev Updates the disable whitelist check flag
     * @param disableWhitelistCheck_ The new value for the disable whitelist check flag
     */
    function updateDisableWhitelistCheck(
        bool disableWhitelistCheck_
    ) public onlyOwner {
        disableWhitelistCheck = disableWhitelistCheck_;
    }

    /**
     * @dev Internal function to calculate the mint amount based on the deposit amount
     * @param amount The amount of OAS to deposit (in wei)
     * @return The calculated mint amount based on the mint rate
     */
    function _mintAmount(uint256 amount) public view virtual returns (uint256) {
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
        if (mintRate == 0) {
            uint256 mintAmount = depositAmount;
            require(
                mintedAmount + mintAmount <= mintCap,
                "Total mint cap exceeded"
            );
            if (!disableWhitelistCheck) {
                require(
                    whitelistWithAllowanceMap[msg.sender] >= mintAmount,
                    "Mint cap exceeded"
                );
            }
            poas.mint(account, mintAmount);
            mintedAmount += mintAmount;
            if (!disableWhitelistCheck) {
                whitelistWithAllowanceMap[msg.sender] -= mintAmount;
            }
            return;
        }

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
