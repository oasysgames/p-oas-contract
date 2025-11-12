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
 * - Support free minting
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
    /// @dev between 0 and 10000
    /// @dev 0 means free mint
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
        uint256 mintAmount = calculateMintAmount(msg.value);
        _capCheck(mintAmount);
        _;
        _updateCap(mintAmount);
    }

    modifier nonFreeMint() {
        require(!isFreeMint(), "restricted to non-free mint");
        _;
    }

    modifier onlyFreeMint() {
        require(isFreeMint(), "restricted to free mint");
        _;
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
    }

    /**
     * @dev Mints POAS tokens for the caller
     * @param depositAmount The amount of OAS to deposit (in wei)
     * @notice The caller must send exactly the OAS amount that matches the token amount
     * @notice Contract must have OPERATOR_ROLE to execute this function
     * @notice Restricted to non-free mint
     */
    function mint(
        uint256 depositAmount
    )
        public
        payable
        virtual
        hasOperatorRole
        onlyWhitelisted
        nonFreeMint
        withinMintCap
    {
        _mint(msg.sender, depositAmount);
    }

    /**
     * @dev Mints POAS tokens for a specified account
     * @param account The address that will receive the minted tokens
     * @param depositAmount The amount of OAS to deposit (in wei)
     * @notice The caller must send exactly the OAS amount that matches the token amount
     * @notice Contract must have OPERATOR_ROLE to execute this function
     * @notice Restricted to non-free mint
     */
    function mint(
        address account,
        uint256 depositAmount
    )
        public
        payable
        virtual
        hasOperatorRole
        onlyWhitelisted
        nonFreeMint
        withinMintCap
    {
        _mint(account, depositAmount);
    }

    /**
     * @dev Free mints POAS tokens for the caller
     * @param mintAmount The amount of tokens to mint
     * @notice The caller must send exactly the OAS amount that matches the token amount
     * @notice Contract must have OPERATOR_ROLE to execute this function
     * @notice Restricted to free mint
     */
    function freeMint(
        uint256 mintAmount
    ) public virtual hasOperatorRole onlyWhitelisted onlyFreeMint {
        _freeMint(msg.sender, mintAmount);
    }

    /**
     * @dev Free mints POAS tokens for a specified account
     * @param account The address that will receive the minted tokens
     * @param mintAmount The amount of tokens to mint
     * @notice The caller must send exactly the OAS amount that matches the token amount
     * @notice Contract must have OPERATOR_ROLE to execute this function
     * @notice Restricted to free mint
     */
    function freeMint(
        address account,
        uint256 mintAmount
    ) public virtual hasOperatorRole onlyWhitelisted onlyFreeMint {
        _freeMint(account, mintAmount);
    }

    /**
     * @dev Mints POAS tokens for multiple accounts in a single transaction
     * @param accounts Array of addresses that will receive the minted tokens
     * @param depositAmounts Array of token amounts to mint for each corresponding address
     * @notice The caller must send exactly the OAS amount that matches the sum of all amounts
     * @notice Contract must have OPERATOR_ROLE to execute this function
     * @notice Restricted to non-free mint
     */
    function bulkMint(
        address[] calldata accounts,
        uint256[] calldata depositAmounts
    )
        public
        payable
        virtual
        hasOperatorRole
        onlyWhitelisted
        nonFreeMint
        withinMintCap
    {
        require(
            accounts.length == depositAmounts.length,
            "Arrays length mismatch"
        );

        uint256 sum = 0;
        for (uint256 i = 0; i < accounts.length; ++i) {
            require(accounts[i] != address(0), "Empty address");
            require(depositAmounts[i] > 0, "Empty amount");

            sum += depositAmounts[i];
            poas.mint(accounts[i], calculateMintAmount(depositAmounts[i]));
        }

        require(sum == msg.value, "Sum of amounts mismatch value");

        _deposit();
    }

    function bulkFreeMint(
        address[] calldata accounts,
        uint256[] calldata mintAmounts
    ) public virtual hasOperatorRole onlyWhitelisted onlyFreeMint {
        require(
            accounts.length == mintAmounts.length,
            "Arrays length mismatch"
        );

        uint256 sum = 0;
        for (uint256 i = 0; i < accounts.length; ++i) {
            require(accounts[i] != address(0), "Empty address");
            require(mintAmounts[i] > 0, "Empty amount");

            sum += mintAmounts[i];
            poas.mint(accounts[i], mintAmounts[i]);
        }

        _capCheck(sum); // check if the total mint amount is within the mint cap
        _updateCap(sum);
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
     * @dev Calculate the mint amount based on the deposit amount
     * @param depositAmount The amount of OAS to deposit (in wei)
     * @return The calculated mint amount based on the mint rate
     */
    function calculateMintAmount(
        uint256 depositAmount
    ) public view virtual returns (uint256) {
        if (isFreeMint()) {
            revert("No deposit needed for free mint");
        }
        return (depositAmount * mintRate) / 100;
    }

    /**
     * @dev Calculate the deposit amount based on the mint amount
     * @param mintAmount The amount of tokens to mint
     * @return The calculated deposit amount based on the mint rate
     */
    function calculateDepositAmount(
        uint256 mintAmount
    ) public view virtual returns (uint256) {
        return isFreeMint() ? 0 : (mintAmount * 100) / mintRate;
    }

    /**
     * @dev Internal function to check if the mint is free
     * @return True if the mint is free, false otherwise
     */
    function isFreeMint() public view virtual returns (bool) {
        return mintRate == 0;
    }

    /**
     * @dev Internal function to check if the mint amount is within the mint cap
     * @param mintAmount The amount of tokens to mint
     * @notice Checks if the total mint amount is within the mint cap
     * @notice Checks if the individual mint amount is within the whitelist allowance
     */
    function _capCheck(uint256 mintAmount) internal view virtual {
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
    }

    /**
     * @dev Internal function to update the minted amount and the whitelist allowance
     * @param mintAmount The amount of tokens to mint
     * @notice Updates the minted amount
     * @notice Updates the whitelist allowance
     */
    function _updateCap(uint256 mintAmount) internal virtual {
        mintedAmount += mintAmount;
        if (!disableWhitelistCheck) {
            whitelistWithAllowanceMap[msg.sender] -= mintAmount;
        }
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
        require(depositAmount == msg.value, "Amount mismatch");

        poas.mint(account, calculateMintAmount(depositAmount));
        _deposit();
    }

    /**
     * @dev Internal function to free mint tokens for a single account
     * @param account The address that will receive the minted tokens
     * @param mintAmount The amount of tokens to mint
     * @notice Checks if the mint amount is within the mint cap
     * @notice Updates the minted amount and the whitelist allowance
     */
    function _freeMint(address account, uint256 mintAmount) internal virtual {
        require(account != address(0), "Empty address");
        require(mintAmount > 0, "Empty amount");
        _capCheck(mintAmount);

        poas.mint(account, mintAmount);
        _updateCap(mintAmount);
    }

    /**
     * @dev Deposits the OAS collateral to the POAS contract
     * @notice Forwards all the OAS value sent in the transaction
     */
    function _deposit() internal virtual {
        poas.depositCollateral{value: msg.value}();
    }
}
