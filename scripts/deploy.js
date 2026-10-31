// Deploys all four contracts in dependency order and wires them together.
const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const roles = await (await hre.ethers.deployContract("RoleManager", [deployer.address])).waitForDeployment();
  const registry = await (await hre.ethers.deployContract("BatchRegistry", [await roles.getAddress()])).waitForDeployment();
  const monitor = await (await hre.ethers.deployContract("ColdChainMonitor", [await roles.getAddress(), await registry.getAddress()])).waitForDeployment();
  const compliance = await (await hre.ethers.deployContract("ComplianceRegistry", [await roles.getAddress(), await registry.getAddress()])).waitForDeployment();
  await (await registry.setModules(await monitor.getAddress(), await compliance.getAddress())).wait();

  console.log({
    RoleManager: await roles.getAddress(),
    BatchRegistry: await registry.getAddress(),
    ColdChainMonitor: await monitor.getAddress(),
    ComplianceRegistry: await compliance.getAddress(),
  });
}
main().catch((e) => { console.error(e); process.exit(1); });
