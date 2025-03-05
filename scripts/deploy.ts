import { ethers } from "hardhat";

async function main() {
  const POAS = await ethers.getContractFactory("POAS");
  const poas = await POAS.deploy();
  await poas.waitForDeployment();

  const address = await poas.getAddress();
  console.log(`POAS deployed to: ${address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 