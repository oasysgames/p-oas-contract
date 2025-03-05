import { expect } from "chai";
import { ethers } from "hardhat";
import { POAS, ClaimSample } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("POAS", function () {
    let poas: POAS;
    let claimSample: ClaimSample;
    let owner: SignerWithAddress;
    let minter: SignerWithAddress;
    let paymentReceiver: SignerWithAddress;
    let user: SignerWithAddress;

    const ADMIN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ADMIN_ROLE"));
    const MINTER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
    const PAYMENT_ROLE = ethers.keccak256(ethers.toUtf8Bytes("PAYMENT_ROLE"));

    beforeEach(async function () {
        [owner, minter, paymentReceiver, user] = await ethers.getSigners();
        
        const POAS = await ethers.getContractFactory("POAS");
        poas = await POAS.deploy();
        
        const ClaimSample = await ethers.getContractFactory("ClaimSample");
        claimSample = await ClaimSample.deploy(await poas.getAddress());

        await poas.grantRole(MINTER_ROLE, minter.address);
        await poas.grantRole(PAYMENT_ROLE, paymentReceiver.address);
        await poas.grantRole(MINTER_ROLE, await claimSample.getAddress());
    });

    describe("Basic Functionality", function () {
        it("should mint tokens correctly", async function () {
            const amount = ethers.parseEther("100");
            await poas.connect(minter).mint(user.address, amount);
            expect(await poas.balanceOf(user.address)).to.equal(amount);
        });

        it("should fail transfer to non-payment address", async function () {
            const amount = ethers.parseEther("100");
            await poas.connect(minter).mint(user.address, amount);
            await expect(
                poas.connect(user).transfer(owner.address, amount)
            ).to.be.revertedWith("Recipient must have PAYMENT_ROLE");
        });

        it("should bulk mint tokens correctly", async function () {
            const recipients = [user.address, paymentReceiver.address];
            const amounts = [
                ethers.parseEther("100"),
                ethers.parseEther("200")
            ];

            await expect(poas.connect(minter).bulkMint(recipients, amounts))
                .to.emit(poas, "BulkMinted")
                .withArgs(recipients, amounts);

            expect(await poas.balanceOf(user.address))
                .to.equal(amounts[0]);
            expect(await poas.balanceOf(paymentReceiver.address))
                .to.equal(amounts[1]);
        });

        it("should fail bulk mint with mismatched arrays", async function () {
            const recipients = [user.address, paymentReceiver.address];
            const amounts = [ethers.parseEther("100")];

            await expect(
                poas.connect(minter).bulkMint(recipients, amounts)
            ).to.be.revertedWith("Arrays length mismatch");
        });

        it("should fail bulk mint with zero amount", async function () {
            const recipients = [user.address];
            const amounts = [0];

            await expect(
                poas.connect(minter).bulkMint(recipients, amounts)
            ).to.be.revertedWith("Amount must be greater than 0");
        });
    });

    describe("Collateral Management", function () {
        it("should track collateral ratio correctly", async function () {
            const amount = ethers.parseEther("100");
            await poas.connect(minter).mint(user.address, amount);
            
            expect(await poas.getCollateralRatio()).to.equal(0);
            
            await poas.connect(owner).depositCollateral({ value: amount });
            expect(await poas.getCollateralRatio()).to.equal(ethers.parseEther("1"));
        });

        it("should fail payment when insufficient collateral", async function () {
            const amount = ethers.parseEther("100");
            await poas.connect(minter).mint(user.address, amount);
            
            await expect(
                poas.connect(user).transfer(paymentReceiver.address, amount)
            ).to.be.revertedWith("Insufficient collateral");
        });
    });

    describe("ClaimSample", function () {
        it("should allow users to claim once", async function () {
            await poas.connect(owner).depositCollateral({ 
                value: ethers.parseEther("1000") 
            });
            
            await claimSample.connect(user).claim();
            expect(await poas.balanceOf(user.address)).to.equal(
                ethers.parseEther("100")
            );
            
            await expect(
                claimSample.connect(user).claim()
            ).to.be.revertedWith("Already claimed");
        });
    });
}); 