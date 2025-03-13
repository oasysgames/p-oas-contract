// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IAccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {StringsUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import {IPOAS} from "./interfaces/IPOAS.sol";

/**
 * @title POAS - pOAS Token Contract
 *
 * The pOAS token is a specialized ERC20 token with additional features:
 * - Role-based access control (Admin, Operator, Recipient)
 * - Collateral-backed payments
 * - Minting and burning with tracking
 * - Recipient management
 */
contract POAS is
    Initializable,
    ReentrancyGuardUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC20BurnableUpgradeable,
    IPOAS
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant RECIPIENT_ROLE = keccak256("RECIPIENT_ROLE");

    uint256 private _totalMinted;
    uint256 private _totalBurned;
    mapping(address => string) private _recipientNames;
    mapping(address => string) private _recipientDescriptions;

    constructor() {
        // Prevent initialization of implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract setting.
     * @param _admin The address of initial admin.
     */
    function initialize(address _admin) public virtual initializer {
        if (_admin == address(0)) {
            revert POASError("admin address is zero");
        }

        // Call parent initializers
        __ReentrancyGuard_init();
        __AccessControlEnumerable_init();
        __ERC20_init("pOAS", "POAS");
        __ERC20Burnable_init();

        // Set up roles
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(RECIPIENT_ROLE, ADMIN_ROLE);
        _grantRole(ADMIN_ROLE, _admin);
    }

    /**
     * @inheritdoc IPOAS
     */
    function totalMinted() public view virtual returns (uint256) {
        return _totalMinted;
    }

    /**
     * @inheritdoc IPOAS
     */
    function totalBurned() public view virtual returns (uint256) {
        return _totalBurned;
    }

    /**
     * @inheritdoc IPOAS
     */
    function mint(
        address account,
        uint256 amount
    ) public virtual onlyRole(OPERATOR_ROLE) {
        _mint(account, amount);
    }

    /**
     * @inheritdoc IPOAS
     */
    function bulkMint(
        address[] calldata accounts,
        uint256[] calldata amounts
    ) public virtual onlyRole(OPERATOR_ROLE) {
        uint256 length = accounts.length;
        if (length != amounts.length) {
            revert POASMintError("array length mismatch");
        }
        for (uint256 i = 0; i < length; i++) {
            _mint(accounts[i], amounts[i]);
        }
    }

    /**
     * @inheritdoc ERC20BurnableUpgradeable
     */
    function burn(
        uint256 amount
    ) public virtual override(ERC20BurnableUpgradeable, IPOAS) {
        super.burn(amount);
    }

    /**
     * @inheritdoc IPOAS
     */
    function depositCollateral()
        public
        payable
        virtual
        onlyRole(OPERATOR_ROLE)
    {
        emit CollateralDeposited(msg.value);
    }

    /**
     * @inheritdoc IPOAS
     */
    function withdrawCollateral(uint256 amount) public virtual {
        withdrawCollateralTo(msg.sender, amount);
    }

    /**
     * @inheritdoc IPOAS
     */
    function withdrawCollateralTo(
        address to,
        uint256 amount
    ) public virtual onlyRole(OPERATOR_ROLE) nonReentrant {
        if (to == address(0)) {
            revert POASWithdrawCollateralError("to address is zero");
        }
        if (amount > address(this).balance) {
            revert POASWithdrawCollateralError("insufficient collateral");
        }
        (bool success, ) = to.call{value: amount}("");
        if (!success) {
            revert POASWithdrawCollateralError("transfer failed");
        }
        emit CollateralWithdrawn(to, amount);
    }

    /**
     * @inheritdoc IPOAS
     */
    function getCollateralRatio() public view virtual returns (uint256 ratio) {
        uint256 tot = totalSupply();
        if (tot > 0) {
            ratio = (address(this).balance * 1e18) / tot;
        }
    }

    /**
     * @inheritdoc IERC20Upgradeable
     */
    function transfer(
        address,
        uint256
    )
        public
        virtual
        override(ERC20Upgradeable, IERC20Upgradeable)
        returns (bool)
    {
        revert POASPaymentError("cannot pay with transfer");
    }

    /**
     * @inheritdoc IPOAS
     */
    function transferFrom(
        address from,
        address recipient,
        uint256 amount
    )
        public
        virtual
        override(ERC20Upgradeable, IPOAS)
        nonReentrant
        returns (bool)
    {
        if (from == msg.sender) {
            revert POASPaymentError("cannot pay from self");
        }
        if (!hasRole(RECIPIENT_ROLE, recipient)) {
            revert POASPaymentError("recipient not found");
        }
        if (amount == 0) {
            revert POASPaymentError("ammount is zero");
        }
        if (amount > address(this).balance) {
            revert POASPaymentError("insufficient collateral");
        }

        // The sender must have been previously approved by 'from'.
        // The sender doesn't need to have RECIPIENT_ROLE, providing flexibility for the app side.
        burnFrom(from, amount);

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert POASPaymentError("transfer failed to recipient");
        }

        emit Paid(from, recipient, amount);
        return true;
    }

    /**
     * @inheritdoc IPOAS
     */
    function addRecipients(
        address[] calldata recipients,
        string[] calldata names,
        string[] calldata descriptions
    ) public virtual onlyRole(ADMIN_ROLE) {
        uint256 length = recipients.length;
        if (length != names.length || length != descriptions.length) {
            revert POASAddRecipientError("array length mismatch");
        }

        for (uint256 i = 0; i < length; i++) {
            address recipient = recipients[i];
            string memory name = names[i];
            string memory description = descriptions[i];
            if (recipient == address(0)) {
                revert POASAddRecipientError("recipient address is zero");
            }
            if (bytes(name).length == 0) {
                revert POASAddRecipientError("name is empty");
            }
            if (bytes(description).length == 0) {
                revert POASAddRecipientError("description is empty");
            }
            if (hasRole(RECIPIENT_ROLE, recipient)) {
                revert POASAddRecipientError("already exists");
            }

            _grantRole(RECIPIENT_ROLE, recipient);
            _recipientNames[recipient] = name;
            _recipientDescriptions[recipient] = description;
            emit RecipientAdded(recipient, name, description);
        }
    }

    /**
     * @inheritdoc IPOAS
     */
    function removeRecipients(
        address[] calldata recipients
    ) public virtual onlyRole(ADMIN_ROLE) {
        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; i++) {
            address recipient = recipients[i];
            if (recipient == address(0)) {
                revert POASRemoveRecipientError("recipient address is zero");
            }
            if (!hasRole(RECIPIENT_ROLE, recipient)) {
                revert POASRemoveRecipientError("recipient not found");
            }

            _revokeRole(RECIPIENT_ROLE, recipient);
            emit RecipientRemoved(recipient, _recipientNames[recipient]);
        }
    }

    /**
     * @inheritdoc IAccessControlUpgradeable
     * @dev Overrides grantRole to prevent direct addition of Recipients.
     */
    function grantRole(
        bytes32 role,
        address account
    )
        public
        virtual
        override(AccessControlUpgradeable, IAccessControlUpgradeable)
    {
        if (role == RECIPIENT_ROLE) {
            revert POASAddRecipientError("use addRecipients instead");
        }
        super.grantRole(role, account);
    }

    /**
     * @inheritdoc IPOAS
     */
    function getRecipientCount() public view virtual returns (uint256) {
        return getRoleMemberCount(RECIPIENT_ROLE);
    }

    /**
     * @inheritdoc IPOAS
     */
    function getRecipient(
        address recipient
    )
        public
        view
        virtual
        returns (string memory name, string memory description)
    {
        if (!hasRole(RECIPIENT_ROLE, recipient)) {
            revert POASError("recipient not found");
        }
        name = _recipientNames[recipient];
        description = _recipientDescriptions[recipient];
    }

    /**
     * @inheritdoc IPOAS
     */
    function getRecipientJSON(
        address recipient
    ) public view virtual returns (string memory json) {
        (string memory name, string memory description) = getRecipient(
            recipient
        );
        json = _makeRecipientJSON(recipient, name, description);
    }

    /**
     * @inheritdoc IPOAS
     */
    function getRecipients(
        uint256 cursor,
        uint256 size
    )
        public
        view
        virtual
        returns (
            address[] memory recipients,
            string[] memory names,
            string[] memory descriptions,
            uint256 nextCursor
        )
    {
        uint256 length = getRoleMemberCount(RECIPIENT_ROLE);
        if (cursor >= length) {
            return (recipients, names, descriptions, length);
        }

        uint256 resultSize = size;
        if (cursor + size > length) {
            resultSize = length - cursor;
        }
        nextCursor = cursor + resultSize;

        recipients = new address[](resultSize);
        names = new string[](resultSize);
        descriptions = new string[](resultSize);
        for (uint256 i = 0; i < resultSize; i++) {
            uint256 memberIndex = cursor + i;
            recipients[i] = getRoleMember(RECIPIENT_ROLE, memberIndex);
            names[i] = _recipientNames[recipients[i]];
            descriptions[i] = _recipientDescriptions[recipients[i]];
        }
    }

    /**
     * @inheritdoc IPOAS
     */
    function getRecipientsJSON(
        uint256 cursor,
        uint256 size
    ) public view virtual returns (string memory json, uint256 nextCursor) {
        (
            address[] memory recipients,
            string[] memory names,
            string[] memory descriptions,
            uint256 newCursor
        ) = getRecipients(cursor, size);
        nextCursor = newCursor;

        uint256 length = recipients.length;
        json = "[";
        for (uint256 i = 0; i < length; i++) {
            if (i > 0) {
                json = string.concat(json, ",");
            }
            json = string.concat(
                json,
                _makeRecipientJSON(recipients[i], names[i], descriptions[i])
            );
        }
        json = string.concat(json, "]");
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            AccessControlEnumerableUpgradeable.supportsInterface(interfaceId) ||
            interfaceId == type(IERC20Upgradeable).interfaceId ||
            interfaceId == type(IPOAS).interfaceId;
    }

    /**
     * @dev Internal function to mint tokens.
     * Overrides ERC20Upgradeable._mint to track total minted amount and emit Minted event.
     * @param account The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function _mint(address account, uint256 amount) internal virtual override {
        if (amount == 0) {
            revert POASMintError("ammount is zero");
        }
        super._mint(account, amount);
        _totalMinted += amount;
        emit Minted(account, amount);
    }

    /**
     * @dev Internal function to burn tokens.
     * Overrides ERC20Upgradeable._burn to track total burned amount and emit Burned event.
     * @param account The address whose tokens will be burned
     * @param amount The amount of tokens to burn
     */
    function _burn(address account, uint256 amount) internal virtual override {
        if (amount == 0) {
            revert POASBurnError("ammount is zero");
        }
        super._burn(account, amount);
        _totalBurned += amount;
        emit Burned(account, amount);
    }

    /**
     * @dev Internal function to create a JSON representation of a recipient.
     * @param recipient The recipient address
     * @param name The name of the recipient
     * @param description The description of the recipient
     * @return json A JSON string representing the recipient
     */
    function _makeRecipientJSON(
        address recipient,
        string memory name,
        string memory description
    ) internal view virtual returns (string memory json) {
        json = string.concat(
            '{"address":"',
            StringsUpgradeable.toHexString(recipient),
            '","name":"',
            name,
            '","description":"',
            description,
            '"}'
        );
    }
}
