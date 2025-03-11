// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
// import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract POAS is ERC20, AccessControl {
    using Strings for address;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant RECIPIENT_ROLE = keccak256("RECIPIENT_ROLE");

    uint256 public constant DECIMALS_FACTOR = 1e18;

    uint256 public totalMinted;
    uint256 public totalBurned;

    bool public initalized;

    /**
     * @dev SENTINEL is used in linked list traversal to mark the start and end.
     * Apply the `Sentinel Pattern` to internal maps to make them iterable.
     * Reference: https://andrej.hashnode.dev/sentinel-pattern
     */
    address public constant SENTINEL = address(0x1);

    struct RecipientMeta {
        address pointer; // point to previously append recipient, The sentinel address is the key of the mapping
        string name;
        string desc;
    }

    // Linked list of recipients for iteration.
    //
    // Example: If recipients are added in the order A, B, C:
    //    [SENTINEL -> RecipientMeta.pointer(C)]
    //    [C        -> RecipientMeta.pointer(B)]
    //    [B        -> RecipientMeta.pointer(A)]
    //    [A        -> RecipientMeta.pointer(SENTINEL)]
    mapping(address => RecipientMeta) private _recipientMeta;

    event CollateralDeposited(address indexed from, uint256 amount);
    event CollateralWithdrawn(address indexed to, uint256 amount);
    event PaymentProcessed(
        address indexed from,
        address indexed to,
        uint256 amount
    );
    event BulkMinted(address[] recipients, uint256[] amounts);

    modifier onlyRoleByAccount(bytes32 role, address account) {
        _checkRole(role, account);
        _;
    }

    // Not initalize contract in constructor, as we adapt Upgradable proxy
    constructor() ERC20(name(), symbol()) {}

    // Initalize via proxy
    function init(address admin, address manager) public {
        require(!initalized, "Already initalized");
        initalized = true;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);
        _recipientMeta[SENTINEL] = RecipientMeta(SENTINEL, "", "");
    }

    // Override for proxy to return `name`
    // Necessary, as the openzeppelin ERC20 store it is storage
    function name() public pure override returns (string memory) {
        return "pOAS";
    }

    // Override for proxy to return `symbol`
    // Necessary, as the openzeppelin ERC20 store it is storage
    function symbol() public pure override returns (string memory) {
        return "POAS";
    }

    // NOTE: disable direct deposit, need to confirm with Manzoku-san
    // receive() external payable {
    //     emit CollateralDeposited(msg.sender, msg.value);
    // }

    // alternative of standard ERC20 transfer
    function standardTransfer(
        address to,
        uint256 amount
    ) external onlyRoleByAccount(RECIPIENT_ROLE, to) {
        transfer(to, amount);
    }

    // alternative of standard ERC20 transferFrom
    function standardTransferFrom(
        address from,
        address to,
        uint256 amount
    ) external onlyRoleByAccount(RECIPIENT_ROLE, to) {
        transferFrom(from, to, amount);
    }

    function depositCollateral(
        uint256 amount
    ) external payable onlyRole(MANAGER_ROLE) {
        require(msg.value == amount, "Invalid amount");

        emit CollateralDeposited(msg.sender, msg.value);
    }

    function withdrawCollateral(
        address to,
        uint256 amount
    ) external onlyRole(MANAGER_ROLE) {
        // what means?, need to confirm with Manzoku-san
        // require(getCollateralRatio() >= 1e18, "Insufficient collateral ratio");

        require(to != address(0), "Empty recipient");
        require(address(this).balance >= amount, "Insufficient collateral");

        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");

        emit CollateralWithdrawn(msg.sender, amount);
    }

    function getCollateralRatio()
        public
        view
        returns (uint256 ratio, bool overCollateralized)
    {
        // Never overflow because OAS total supply is limited
        uint256 balance = address(this).balance * DECIMALS_FACTOR;
        uint256 totalSupply = totalSupply();

        overCollateralized = balance >= totalSupply;

        if (totalSupply == 0) {
            // why?, need to confirm with Manzoku-san
            ratio = type(uint256).max;
        } else {
            ratio = balance / totalSupply;
        }
    }

    function mint(address to, uint256 amount) external payable {
        require(msg.value == amount, "Invalid amount");
        _mint(to, amount);
    }

    function freeMint(
        address to,
        uint256 amount
    ) external onlyRole(MANAGER_ROLE) {
        _mint(to, amount);
    }

    function bulkMint(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external payable onlyRole(MANAGER_ROLE) {
        uint256 totalAmount = _bulkMint(recipients, amounts);
        require(msg.value == totalAmount, "Invalid amount");
    }

    function bulkFreeMint(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyRole(MANAGER_ROLE) {
        _bulkMint(recipients, amounts);
    }

    function _bulkMint(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) internal returns (uint256 totalAmount) {
        uint256 len = recipients.length;
        require(len == amounts.length && len > 0, "Invalid input arrays");

        for (uint256 i = 0; i < len; ++i) {
            require(amounts[i] > 0, "Amount must be greater than 0");
            _mint(recipients[i], amounts[i]);
            totalAmount += amounts[i];
        }

        emit BulkMinted(recipients, amounts);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function grantRecipientRole(
        address account,
        string calldata name_,
        string calldata desc
    ) external onlyRole(getRoleAdmin(RECIPIENT_ROLE)) {
        require(account != address(0), "Empty account");
        require(bytes(name_).length > 0, "Empty name");
        require(bytes(desc).length > 0, "Empty description");
        require(
            _recipientMeta[account].pointer == address(0),
            "Already granted"
        );

        _grantRole(RECIPIENT_ROLE, account);

        _recipientMeta[account] = RecipientMeta(
            _recipientMeta[SENTINEL].pointer,
            name_,
            desc
        );
        _recipientMeta[SENTINEL] = RecipientMeta(account, "", "");
    }

    function gsonTransferableList()
        external
        view
        returns (string memory content)
    {
        address cursor = SENTINEL;
        while (_recipientMeta[cursor].pointer != SENTINEL) {
            cursor = _recipientMeta[cursor].pointer;
            content = string(
                abi.encodePacked(content, _jsonRecipientMeta(cursor))
            );
        }

        // prettier-ignore
        return string(abi.encodePacked("[", content, "]"));
    }

    function _jsonRecipientMeta(
        address recipient
    ) internal view returns (string memory) {
        // prettier-ignore
        return string(abi.encodePacked(
            "{",
                '"name": "', _recipientMeta[recipient].name, '",',
                '"description": "', _recipientMeta[recipient].desc, '",',
                '"address": "', recipient.toHexString(), '"',
            "}"
        ));
    }
}
