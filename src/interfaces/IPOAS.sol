// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IAccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/IAccessControlEnumerableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title IPOAS - Interface for pOAS Token
 *
 * The pOAS token is a specialized ERC20 token with additional features:
 * - Role-based access control (Admin, Operator, Recipient)
 * - Collateral-backed payments
 * - Minting and burning with tracking
 * - Recipient management
 */
interface IPOAS is IAccessControlEnumerableUpgradeable, IERC20Upgradeable {
    /**
     * @dev Emitted when tokens are minted to an account
     * @param to The address receiving the minted tokens
     * @param amount The number of tokens minted
     */
    event Minted(address indexed to, uint256 amount);

    /**
     * @dev Emitted when tokens are burned from an account
     * @param from The address burning the tokens
     * @param amount The number of tokens burned
     */
    event Burned(address indexed from, uint256 amount);

    /**
     * @dev Emitted when a payment is made
     * @param from The address paying (burning tokens)
     * @param recipient The address receiving the payment
     * @param amount The payment amount
     */
    event Paid(address indexed from, address indexed recipient, uint256 amount);

    /**
     * @dev Emitted when collateral is deposited into the contract
     * @param amount The amount of collateral deposited
     */
    event CollateralDeposited(uint256 amount);

    /**
     * @dev Emitted when collateral is withdrawn from the contract
     * @param to The address receiving the withdrawn collateral
     * @param amount The amount of collateral withdrawn
     */
    event CollateralWithdrawn(address indexed to, uint256 amount);

    /**
     * @dev Emitted when a new payment recipient is added
     * @param recipient The address of the new recipient
     * @param name The name of the recipient
     * @param desc A description of the recipient
     */
    event RecipientAdded(address indexed recipient, string name, string desc);

    /**
     * @dev Emitted when a payment recipient is removed
     * @param recipient The address of the removed recipient
     * @param name The name of the removed recipient
     */
    event RecipientRemoved(address indexed recipient, string name);

    /**
     * @dev Generic error for general contract failures
     * @param message A descriptive error message
     */
    error POASError(string message);

    /**
     * @dev Error specific to token minting operations
     * @param message A descriptive error message related to minting
     */
    error POASMintError(string message);

    /**
     * @dev Error specific to token burning operations
     * @param message A descriptive error message related to burning
     */
    error POASBurnError(string message);

    /**
     * @dev Error specific to collateral withdrawal operations
     * @param message A descriptive error message related to collateral withdrawal
     */
    error POASWithdrawCollateralError(string message);

    /**
     * @dev Error specific to payment operations
     * @param message A descriptive error message related to payments
     */
    error POASPaymentError(string message);

    /**
     * @dev Error specific to recipient addition operations
     * @param message A descriptive error message related to adding recipients
     */
    error POASAddRecipientError(string message);

    /**
     * @dev Error specific to recipient removal operations
     * @param message A descriptive error message related to removing recipients
     */
    error POASRemoveRecipientError(string message);

    /**
     * @dev Returns the ADMIN_ROLE
     */
    function ADMIN_ROLE() external view returns (bytes32);

    /**
     * @dev Returns the OPERATOR_ROLE
     */
    function OPERATOR_ROLE() external view returns (bytes32);

    /**
     * @dev Returns the RECIPIENT_ROLE
     */
    function RECIPIENT_ROLE() external view returns (bytes32);

    /**
     * @dev Total minted amount
     *      Unlike totalSupply, this does not decrease when tokens are burned
     */
    function totalMinted() external view returns (uint256);

    /**
     * @dev Total burned amount
     */
    function totalBurned() external view returns (uint256);

    /**
     * @dev Mint tokens
     * @param account The recipient address
     * @param amount The amount to mint
     */
    function mint(address account, uint256 amount) external;

    /**
     * @dev Mint tokens to multiple accounts
     * @param accounts List of recipient addresses
     * @param amounts List of amounts to mint
     */
    function bulkMint(
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external;

    /**
     * @dev Burn tokens
     * @param amount The amount to burn
     */
    function burn(uint256 amount) external;

    /**
     * @dev Make a payment
     *      Overrides `ERC20.transferFrom`
     * @param from The payer
     * @param recipient The payment recipient
     * @param amount The payment amount
     */
    function transferFrom(
        address from,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Add collateral into the contract
     */
    function depositCollateral() external payable;

    /**
     * @dev Withdraw collateral from the contract
     * @param to The withdrawal address
     * @param amount The amount to withdraw
     */
    function withdrawCollateral(address to, uint256 amount) external;

    /**
     * @dev Returns the ratio of collateral to token totalSupply in 1e18 format
     *      1 ether (1e18) represents 100%, 0.5 ether (5e17) represents 50%
     * @return ratio The collateral ratio in 1e18 format
     */
    function getCollateralRatio() external view returns (uint256 ratio);

    /**
     * @dev Add Recipients
     *      Adding through `AccessControl.grantRole` will result in an error
     * @param recipients List of recipient addresses to add
     * @param names List of names
     * @param descriptions List of descriptions
     */
    function addRecipients(
        address[] calldata recipients,
        string[] calldata names,
        string[] calldata descriptions
    ) external;

    /**
     * @dev Remove Recipients
     *      This is a syntactic sugar for `AccessControl.revokeRole`
     * @param recipients List of recipient addresses to remove
     */
    function removeRecipients(address[] calldata recipients) external;

    /**
     * @dev Returns the number of Recipients
     * @return count The number of registered Recipients
     */
    function getRecipientCount() external view returns (uint256);

    /**
     * @dev Returns a Recipient
     * @param recipient The Recipient address
     * @return name The name
     * @return description The description
     */
    function getRecipient(
        address recipient
    ) external view returns (string memory name, string memory description);

    /**
     * @dev Returns a Recipient in JSON format
     * @param recipient The Recipient address
     * @return json The Recipient in JSON format
     */
    function getRecipientJSON(
        address recipient
    ) external view returns (string memory json);

    /**
     * @dev Returns a list of Recipients
     * @param cursor Cursor for pagination
     * @param size Size for pagination
     * @return recipients List of Recipient addresses
     * @return names List of names
     * @return descriptions List of descriptions
     * @return nextCursor Next cursor for pagination
     */
    function getRecipients(
        uint256 cursor,
        uint256 size
    )
        external
        view
        returns (
            address[] memory recipients,
            string[] memory names,
            string[] memory descriptions,
            uint256 nextCursor
        );

    /**
     * @dev Returns a list of Recipients in JSON format
     * @param cursor Cursor for pagination
     * @param size Size for pagination
     * @return json List of Recipients in JSON format
     * @return nextCursor Next cursor for pagination
     */
    function getRecipientsJSON(
        uint256 cursor,
        uint256 size
    ) external view returns (string memory json, uint256 nextCursor);
}
