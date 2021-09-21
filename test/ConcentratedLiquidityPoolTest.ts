import { expect } from "chai";
import { ethers, network } from "hardhat";
import { initialize } from "./harness/Concentrated";
import { getBigNumber, randBetween, ZERO } from "./harness/helpers";

describe.only("Concentrated Liquidity Product Pool", function () {
  let snapshotId;

  before(async function () {
    await initialize();
    snapshotId = await ethers.provider.send("evm_snapshot", []);
    console.log("snapshot ", snapshotId);
  });

  afterEach(async () => {
    await network.provider.send("evm_revert", [snapshotId]);
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });

  describe("Add liquidity", function () {
    it("Balanced liquidity to a balanced pool", async function () {
      const amount = getBigNumber(randBetween(10, 100));
      // await addLiquidity(0, amount, amount);
      expect("a").to.not.be.eq("b");
    });
  });
});
