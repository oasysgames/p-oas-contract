// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./POAS.sol";

contract ClaimSample is Ownable {
    POAS public poas;
    uint256 public constant CLAIM_AMOUNT = 100 * 1e18;
    mapping(address => bool) public hasClaimed;

    event Claimed(address indexed user, uint256 amount);

    constructor(address poasAddress) Ownable(msg.sender) {
        poas = POAS(poasAddress);
    }

    function claim() external {
        require(!hasClaimed[msg.sender], "Already claimed");
        hasClaimed[msg.sender] = true;
        
        require(
            poas.hasRole(poas.MINTER_ROLE(), address(this)),
            "Contract needs MINTER_ROLE"
        );
        
        poas.mint(msg.sender, CLAIM_AMOUNT);
        emit Claimed(msg.sender, CLAIM_AMOUNT);
    }
} 