/**
 * deploy-governance.ts
 * --------------------
 * Deploys HouseTokenizingGovernance.sol to the private GoQuorum network.
 *
 * Usage (from /private-chain):
 *   npx ts-node scripts/deploy-governance.ts
 *
 * Reads role addresses from ../.env:
 *   QUORUM_AGENT_ADDRESS, QUORUM_BANK_ADDRESS, QUORUM_HOUSING_DEPT_ADDRESS
 *   QUORUM_RPC_URL, QUORUM_DEPLOYER_PK
 */

import { ethers } from "ethers";
import * as fs    from "fs";
import * as path  from "path";
import * as dotenv from "dotenv";

dotenv.config({ path: path.join(__dirname, "../../.env") });

// ABI + bytecode — compiled with solc or hardhat
// For a quick local deploy, compile with:  npx hardhat compile  (in /public-chain, sharing solc)
// Or use the pre-compiled artifact if available.
const artifactPath = path.join(
  __dirname,
  "../../public-chain/artifacts/contracts/HouseTokenizingGovernance.sol/HouseTokenizingGovernance.json"
);

async function main() {
  const rpc        = process.env.QUORUM_RPC_URL        || "http://127.0.0.1:8545";
  const deployerPK = process.env.QUORUM_DEPLOYER_PK    || "";
  const agentAddr  = process.env.QUORUM_AGENT_ADDRESS  || "";
  const bankAddr   = process.env.QUORUM_BANK_ADDRESS   || "";
  const housingAddr= process.env.QUORUM_HOUSING_DEPT_ADDRESS || "";

  if (!deployerPK || !agentAddr || !bankAddr || !housingAddr) {
    throw new Error("Missing required env vars. Check .env file.");
  }

  const provider = new ethers.JsonRpcProvider(rpc);
  const deployer = new ethers.Wallet(deployerPK, provider);

  console.log(`\nConnected to GoQuorum at: ${rpc}`);
  console.log(`Deployer: ${deployer.address}`);

  if (!fs.existsSync(artifactPath)) {
    throw new Error(
      `Artifact not found at ${artifactPath}.\n` +
      `Run: cd public-chain && npx hardhat compile\n` +
      `(Add HouseTokenizingGovernance.sol to public-chain/contracts/ temporarily)`
    );
  }

  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
  const factory  = new ethers.ContractFactory(artifact.abi, artifact.bytecode, deployer);

  console.log("\nDeploying HouseTokenizingGovernance...");
  const contract = await factory.deploy(agentAddr, bankAddr, housingAddr);
  await contract.waitForDeployment();
  const address  = await contract.getAddress();

  console.log(`  Contract deployed at: ${address}`);

  // Persist address for the relayer
  const outPath = path.join(__dirname, "../../relayer/.deployed.json");
  let deployed: Record<string, unknown> = {};
  if (fs.existsSync(outPath)) {
    deployed = JSON.parse(fs.readFileSync(outPath, "utf8"));
  }
  deployed["governance"]    = address;
  deployed["quorumRpcUrl"]  = rpc;
  fs.writeFileSync(outPath, JSON.stringify(deployed, null, 2));
  console.log(`\nAddress saved to: ${outPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
