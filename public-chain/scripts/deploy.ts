/**
 * deploy.ts
 * ---------
 * Deploys Verifier.sol and HouseToken.sol to the public Hardhat network.
 *
 * Usage:
 *   npx hardhat run scripts/deploy.ts --network localhost
 *
 * Writes deployed addresses to ../relayer/.deployed.json so the relayer
 * can pick them up automatically.
 */

import { ethers } from "hardhat";
import * as fs   from "fs";
import * as path from "path";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(`\nDeploying contracts with: ${deployer.address}`);
  console.log(`Balance: ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH\n`);

  // ── 1. Deploy Verifier ───────────────────────────────────────────────────
  console.log("Deploying Verifier...");
  const VerifierFactory = await ethers.getContractFactory("Groth16Verifier");
  const verifier        = await VerifierFactory.deploy();
  await verifier.waitForDeployment();
  const verifierAddress = await verifier.getAddress();
  console.log(`  Verifier deployed at: ${verifierAddress}`);

  // ── 2. Deploy HouseToken ─────────────────────────────────────────────────
  console.log("Deploying HouseToken...");
  const baseURI          = "ipfs://QmPlaceholderCID/{id}.json"; // replace with real CID
  const HouseTokenFactory = await ethers.getContractFactory("HouseToken");
  const houseToken        = await HouseTokenFactory.deploy(verifierAddress, baseURI);
  await houseToken.waitForDeployment();
  const houseTokenAddress = await houseToken.getAddress();
  console.log(`  HouseToken deployed at: ${houseTokenAddress}`);

  // ── 3. Persist addresses for the relayer ────────────────────────────────
  // Merge so that the governance address written by deploy-governance.ts is preserved.
  const outPath = path.join(__dirname, "../../relayer/.deployed.json");
  let existing: Record<string, unknown> = {};
  if (fs.existsSync(outPath)) {
    existing = JSON.parse(fs.readFileSync(outPath, "utf8"));
  }
  const deployed = {
    ...existing,
    network:     "hardhat-localhost-8546",
    verifier:    verifierAddress,
    houseToken:  houseTokenAddress,
    deployedAt:  new Date().toISOString(),
  };

  fs.writeFileSync(outPath, JSON.stringify(deployed, null, 2));
  console.log(`\nAddresses saved to: ${outPath}`);
  console.log(JSON.stringify(deployed, null, 2));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
