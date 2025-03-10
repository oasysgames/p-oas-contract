// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract POAS is ERC20, AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAYMENT_ROLE = keccak256("PAYMENT_ROLE");

    event CollateralDeposited(address indexed from, uint256 amount);
    event CollateralWithdrawn(address indexed to, uint256 amount);
    event PaymentProcessed(address indexed from, address indexed to, uint256 amount);
    event BulkMinted(address[] recipients, uint256[] amounts);

    constructor() ERC20("pOAS", "pOAS") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function depositCollateral() external payable onlyRole(ADMIN_ROLE) {
        emit CollateralDeposited(msg.sender, msg.value);
    }

    function withdrawCollateral(uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(getCollateralRatio() >= 1e18, "Insufficient collateral ratio");
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        emit CollateralWithdrawn(msg.sender, amount);
    }

    function getCollateralRatio() public view returns (uint256) {
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) return type(uint256).max;
        return (address(this).balance * 1e18) / totalSupply;
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (from != address(0) && to != address(0)) {
            if (hasRole(PAYMENT_ROLE, to)) {
                require(
                    address(this).balance >= amount,
                    "Insufficient collateral"
                );
                super._update(from, address(0), amount); // burn
                (bool success, ) = to.call{value: amount}("");
                require(success, "Transfer failed");
                emit PaymentProcessed(from, to, amount);
            } else {
                revert("Recipient must have PAYMENT_ROLE");
            }
        } else {
            super._update(from, to, amount);
        }
    }

    function bulkMint(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyRole(MINTER_ROLE) nonReentrant {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        require(recipients.length > 0, "Empty arrays");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            require(amounts[i] > 0, "Amount must be greater than 0");
            totalAmount += amounts[i];
            _mint(recipients[i], amounts[i]);
        }

        emit BulkMinted(recipients, amounts);
    }

    receive() external payable {
        emit CollateralDeposited(msg.sender, msg.value);
    }
} 