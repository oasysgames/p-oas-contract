// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {POAS} from "./POAS.sol";

contract ClaimSample is Ownable {
    POAS public poas;
    uint256 public constant CLAIM_AMOUNT = 100 * 1e18;
    mapping(address => bool) public hasClaimed;

    event Claimed(address indexed user, uint256 amount);

    constructor(address poasAddress) Ownable() {
        poas = POAS(poasAddress);
    }

    function claim() external {
        require(!hasClaimed[msg.sender], "Already claimed");
        hasClaimed[msg.sender] = true;

        require(
            poas.hasRole(poas.OPERATOR_ROLE(), address(this)),
            "Contract needs OPERATOR_ROLE"
        );

        poas.mint(msg.sender, CLAIM_AMOUNT);
        emit Claimed(msg.sender, CLAIM_AMOUNT);
    }
}
