const { ethers } = require("hardhat");

async function main() {
  const SmartLendProtocol = await ethers.getContractFactory("SmartLendProtocol");
  const smartLendProtocol = await SmartLendProtocol.deploy();

  await smartLendProtocol.deployed();

  console.log("SmartLendProtocol contract deployed to:", smartLendProtocol.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
