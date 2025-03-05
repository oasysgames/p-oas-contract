import { expect } from "chai";
import { ethers } from "hardhat";
import { POAS, PaymentSample } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("PaymentSample", function () {
    let poas: POAS;
    let paymentSample: PaymentSample;
    let owner: SignerWithAddress;
    let user: SignerWithAddress;

    beforeEach(async function () {
        [owner, user] = await ethers.getSigners();
        
        const POAS = await ethers.getContractFactory("POAS");
        poas = await POAS.deploy();
        
        const PaymentSample = await ethers.getContractFactory("PaymentSample");
        paymentSample = await PaymentSample.deploy(await poas.getAddress());

        // PaymentSampleコントラクトにPAYMENT_ROLEを付与
        await poas.grantRole(
            await poas.PAYMENT_ROLE(),
            await paymentSample.getAddress()
        );

        // ユーザーにpOASを発行
        await poas.mint(user.address, ethers.parseEther("1000"));
        
        // 担保を追加
        await poas.depositCollateral({ value: ethers.parseEther("1000") });
    });

    describe("Payment Functions", function () {
        it("should receive pOAS payment and convert to OAS", async function () {
            const amount = ethers.parseEther("100");
            
            // approve the payment
            await poas.connect(user).approve(
                await paymentSample.getAddress(),
                amount
            );
            
            await expect(paymentSample.connect(user).pay(amount))
                .to.emit(paymentSample, "PaymentReceived")
                .withArgs(user.address, amount);

            expect(await ethers.provider.getBalance(
                await paymentSample.getAddress()
            )).to.equal(amount);
        });

        it("should fail payment without approval", async function () {
            const amount = ethers.parseEther("100");
            
            await expect(
                paymentSample.connect(user).pay(amount)
            ).to.be.reverted;
        });

        it("should allow owner to withdraw OAS", async function () {
            const amount = ethers.parseEther("100");
            
            // approve and pay
            await poas.connect(user).approve(
                await paymentSample.getAddress(),
                amount
            );
            await paymentSample.connect(user).pay(amount);

            const initialBalance = await ethers.provider.getBalance(owner.address);
            
            await expect(paymentSample.connect(owner).withdrawOAS(amount))
                .to.emit(paymentSample, "OASWithdrawn")
                .withArgs(owner.address, amount);

            const finalBalance = await ethers.provider.getBalance(owner.address);
            expect(finalBalance).to.be.gt(initialBalance);
        });

        it("should fail withdrawal if insufficient balance", async function () {
            const amount = ethers.parseEther("100");
            await expect(
                paymentSample.connect(owner).withdrawOAS(amount)
            ).to.be.revertedWith("Insufficient balance");
        });
    });
}); 