// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
// import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract POAS is ERC20, AccessControl {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant RECIPIENT_ROLE = keccak256("RECIPIENT_ROLE");

    uint256 public constant DECIMALS_FACTOR = 1e18;

    uint256 public totalMinted;
    uint256 public totalBurned;

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

    constructor() ERC20("pOAS", "pOAS") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    // receive() external payable {
    //     emit CollateralDeposited(msg.sender, msg.value);
    // }

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

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
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
        // what means?
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
            // why?
            ratio = type(uint256).max;
        } else {
            ratio = balance / totalSupply;
        }
    }

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

    // Warning!  oOAS dosen't behave usual ERC20 token when transferring(`transfer` and `transferFrom`)
    // pOAS burn sent token, then send OAS to recipient
    // Use `normalTransfer` and `normalTransferFrom` for usual ERC20 token behavior
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override onlyRoleByAccount(RECIPIENT_ROLE, to) {
        require(address(this).balance >= amount, "Insufficient collateral");
        require(to != address(0), "Empty recipient");

        // Burn sent token
        super._burn(from, amount);

        // Send OAS to recipient
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed.");

        emit PaymentProcessed(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override {
        super._mint(to, amount);
        totalMinted += amount;
    }

    function _burn(address from, uint256 amount) internal override {
        super._burn(from, amount);
        totalBurned += amount;
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
}
