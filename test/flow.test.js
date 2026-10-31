// Draft smoke test: one happy path + one breach. Full suite is owned by the Testing Lead.
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PharmaTrace draft flow", () => {
  let roles, registry, monitor, compliance, reg, mfr, dist, pharm, oracle;

  beforeEach(async () => {
    [reg, mfr, dist, pharm, oracle] = await ethers.getSigners();
    roles = await ethers.deployContract("RoleManager", [reg.address]);
    registry = await ethers.deployContract("BatchRegistry", [await roles.getAddress()]);
    monitor = await ethers.deployContract("ColdChainMonitor", [await roles.getAddress(), await registry.getAddress()]);
    compliance = await ethers.deployContract("ComplianceRegistry", [await roles.getAddress(), await registry.getAddress()]);
    await registry.setModules(await monitor.getAddress(), await compliance.getAddress());
    await roles.grantRole(await roles.MANUFACTURER_ROLE(), mfr.address);
    await roles.grantRole(await roles.DISTRIBUTOR_ROLE(), dist.address);
    await roles.grantRole(await roles.PHARMACY_ROLE(), pharm.address);
    await roles.grantRole(await roles.ORACLE_ROLE(), oracle.address);
    const exp = Math.floor(Date.now() / 1000) + 86400 * 365;
    await registry.connect(mfr).registerBatch("Insulin", "LOT-001", exp, ethers.id("cert"), "Qm...");
    await monitor.connect(mfr).setTempRange(1, 20, 80); // 2.0 - 8.0 C
  });

  it("runs create -> ship -> accept -> store -> ship -> accept -> dispense", async () => {
    await registry.connect(mfr).shipBatch(1, dist.address);
    await registry.connect(dist).acceptCustody(1);
    await registry.connect(dist).logStorage(1, "Warehouse A");
    await registry.connect(dist).shipBatch(1, pharm.address);
    await registry.connect(pharm).acceptCustody(1);
    await registry.connect(pharm).markDispensed(1);
    expect((await registry.getBatch(1)).status).to.equal(4); // Dispensed
    expect((await registry.getCustodyTrail(1)).length).to.equal(7);
  });

  it("blocks non-holder transfer", async () => {
    await expect(registry.connect(dist).shipBatch(1, pharm.address)).to.be.revertedWithCustomError(registry, "NotAuthorized");
  });

  it("flags batch on out-of-range reading and shows unsafe to consumer", async () => {
    await compliance.approveBatch(1, ethers.id("report"));
    expect((await compliance.verifyForConsumer(1)).safe).to.equal(true);
    await monitor.connect(oracle).recordReading(1, 120, 1, ethers.id("p")); // 12.0 C
    expect((await registry.getBatch(1)).status).to.equal(5); // Compromised
    expect((await compliance.verifyForConsumer(1)).safe).to.equal(false);
  });

  it("recall freezes batch", async () => {
    await compliance.recallBatch(1, "contamination", ethers.id("r"));
    await expect(registry.connect(mfr).shipBatch(1, dist.address)).to.be.revertedWithCustomError(registry, "BadStatus");
  });
});
