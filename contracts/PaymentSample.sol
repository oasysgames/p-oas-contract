// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./POAS.sol";

contract PaymentSample is Ownable {
    POAS public poas;
    
    event PaymentReceived(address indexed from, uint256 amount);
    event OASWithdrawn(address indexed to, uint256 amount);

    constructor(address poasAddress) Ownable(msg.sender) {
        poas = POAS(poasAddress);
        // コントラクトデプロイ時にPAYMENT_ROLEを取得する必要がある
        require(
            poas.hasRole(poas.PAYMENT_ROLE(), address(this)),
            "Contract needs PAYMENT_ROLE"
        );
    }

    // pOASでの支払いを受け付ける
    function pay(uint256 amount) external {
        // 送信者からpOASを受け取る（事前にapproveが必要）
        require(
            poas.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        emit PaymentReceived(msg.sender, amount);
    }

    // 管理者がOASを引き出す
    function withdrawOAS(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        emit OASWithdrawn(msg.sender, amount);
    }

    // OASを受け取れるようにする
    receive() external payable {}
} 