/**
 * test-flow.ts
 * ------------
 * End-to-end simulation of the ZKP cross-chain bridge.
 *
 * Steps executed:
 *  1. Connect to GoQuorum (8545) with Agent, Bank, and HousingDept wallets.
 *  2. Call approveAsAgent(), approveAsBank(), approveAsHousingDept() for a
 *     test houseId — triggering HouseFullyApproved.
 *  3. Wait for the relayer to pick up the event, generate the ZKP proof,
 *     and call mintHouseToken() on the Hardhat node (8546).
 *  4. Poll the public chain until the token balance is confirmed.
 *
 * Usage:
 *   cd relayer && npx ts-node src/test-flow.ts
 *
 * Prerequisites:
 *   • Both chains running (GoQuorum on 8545, Hardhat on 8546).
 *   • Governance + HouseToken contracts deployed (.deployed.json exists).
 *   • Circuit compiled (houseApproval.wasm + circuit_final.zkey).
 *   • .env configured (see .env.example).
 *   • relayer.ts running in a separate terminal.
 */

import * as path    from "path";
import * as fs      from "fs";
import * as dotenv  from "dotenv";
import { ethers }   from "ethers";

dotenv.config({ path: path.join(__dirname, "../../.env") });

// ── Config ────────────────────────────────────────────────────────────────
const QUORUM_RPC   = process.env.QUORUM_RPC_URL                || "http://127.0.0.1:8545";
const HARDHAT_RPC  = process.env.HARDHAT_RPC_URL               || "http://127.0.0.1:8546";
const AGENT_PK     = process.env.QUORUM_AGENT_PK               || "";
const BANK_PK      = process.env.QUORUM_BANK_PK                || "";
const HOUSING_PK   = process.env.QUORUM_HOUSING_DEPT_PK        || "";
const RECIPIENT    = process.env.NFT_RECIPIENT                  || "";
const HOUSE_ID  = BigInt(process.env.TEST_HOUSE_ID       || "42");
const MINT_TIMEOUT = parseInt(process.env.MINT_POLL_TIMEOUT_MS || "60000", 10);

const DEPLOYED = JSON.parse(
  fs.readFileSync(path.join(__dirname, "../../relayer/.deployed.json"), "utf8")
);

// ── ABIs ──────────────────────────────────────────────────────────────────
const GOVERNANCE_ABI = [
  "function approveAsAgent(uint256 houseId) external",
  "function approveAsBank(uint256 houseId) external",
  "function approveAsHousingDept(uint256 houseId) external",
  "function getApprovalState(uint256) view returns (bool,bool,bool,bool)",
  "event HouseApproved(uint256 indexed houseId, address indexed approver, string role)",
  "event HouseFullyApproved(uint256 indexed houseId)",
];

const HOUSE_TOKEN_ABI = [
  "function balanceOf(address account, uint256 id) view returns (uint256)",
  "function minted(uint256) view returns (bool)",
];

// ── Helpers ───────────────────────────────────────────────────────────────
function sleep(ms: number) { return new Promise(r => setTimeout(r, ms)); }

async function waitForMint(
  houseToken: ethers.Contract,
  houseId: bigint,
  recipient:  string,
  timeoutMs:  number
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  process.stdout.write("\n  Waiting for relayer to mint token");
  while (Date.now() < deadline) {
    const balance: bigint = await houseToken.balanceOf(recipient, houseId);
    if (balance > 0n) {
      console.log("\n  Token balance confirmed ✓");
      return;
    }
    process.stdout.write(".");
    await sleep(2000);
  }
  throw new Error(`Mint not detected within ${timeoutMs / 1000}s`);
}

// ── Main ──────────────────────────────────────────────────────────────────
async function main() {
  if (!AGENT_PK || !BANK_PK || !HOUSING_PK) {
    throw new Error("Missing QUORUM_AGENT_PK / QUORUM_BANK_PK / QUORUM_HOUSING_DEPT_PK in .env");
  }
  if (!RECIPIENT) throw new Error("Missing NFT_RECIPIENT in .env");

  console.log("\n╔══════════════════════════════════════════════════════╗");
  console.log("║       ZKP Cross-Chain Bridge — E2E Test Flow         ║");
  console.log("╚══════════════════════════════════════════════════════╝");
  console.log(`  houseId : ${HOUSE_ID}`);
  console.log(`  GoQuorum   : ${QUORUM_RPC}`);
  console.log(`  Hardhat    : ${HARDHAT_RPC}`);
  console.log(`  Governance : ${DEPLOYED.governance}`);
  console.log(`  HouseToken : ${DEPLOYED.houseToken}\n`);

  // ── Providers & signers ─────────────────────────────────────────────────
  const quorumProvider  = new ethers.JsonRpcProvider(QUORUM_RPC);
  const hardhatProvider = new ethers.JsonRpcProvider(HARDHAT_RPC);

  const agentSigner    = new ethers.Wallet(AGENT_PK,    quorumProvider);
  const bankSigner     = new ethers.Wallet(BANK_PK,     quorumProvider);
  const housingSigner  = new ethers.Wallet(HOUSING_PK,  quorumProvider);

  console.log(`  Agent      : ${agentSigner.address}`);
  console.log(`  Bank       : ${bankSigner.address}`);
  console.log(`  HousingDept: ${housingSigner.address}\n`);

  // ── Contracts ───────────────────────────────────────────────────────────
  const govAsAgent   = new ethers.Contract(DEPLOYED.governance, GOVERNANCE_ABI, agentSigner);
  const govAsBank    = new ethers.Contract(DEPLOYED.governance, GOVERNANCE_ABI, bankSigner);
  const govAsHousing = new ethers.Contract(DEPLOYED.governance, GOVERNANCE_ABI, housingSigner);
  const houseToken   = new ethers.Contract(DEPLOYED.houseToken,  HOUSE_TOKEN_ABI, hardhatProvider);

  // Check if token was already minted (idempotency for re-runs)
  const alreadyMinted: boolean = await houseToken.minted(HOUSE_ID);
  if (alreadyMinted) {
    console.log(`Token for houseId=${HOUSE_ID} is already minted. Test passed!\n`);
    return;
  }

  // ── Step 1: Agent approves ────────────────────────────────────────────
  console.log("Step 1 — Agent approval...");
  const tx1 = await govAsAgent.approveAsAgent(HOUSE_ID);
  await tx1.wait();
  console.log(`  tx: ${tx1.hash} ✓`);

  // ── Step 2: Bank approves ─────────────────────────────────────────────
  console.log("Step 2 — Bank approval...");
  const tx2 = await govAsBank.approveAsBank(HOUSE_ID);
  await tx2.wait();
  console.log(`  tx: ${tx2.hash} ✓`);

  // ── Step 3: Housing Dept approves ─────────────────────────────────────
  console.log("Step 3 — HousingDept approval...");
  const tx3 = await govAsHousing.approveAsHousingDept(HOUSE_ID);
  await tx3.wait();
  console.log(`  tx: ${tx3.hash} ✓`);

  // Verify on-chain state
  const [ag, bk, hd, full] = await govAsAgent.getApprovalState(HOUSE_ID);
  console.log(`\nApproval state: Agent=${ag} | Bank=${bk} | HousingDept=${hd} | FullyApproved=${full}`);
  if (!full) throw new Error("Contract did not reach fullyApproved state!");

  console.log("\nHouseFullyApproved event emitted on GoQuorum.");
  console.log("Waiting for the relayer to generate the ZKP and mint on Hardhat...");

  // ── Step 4: Poll public chain for the minted token ─────────────────────
  await waitForMint(houseToken, HOUSE_ID, RECIPIENT, MINT_TIMEOUT);

  const balance: bigint = await houseToken.balanceOf(RECIPIENT, HOUSE_ID);
  console.log(`\n╔══════════════════════════════════════════════════════╗`);
  console.log(`║                  TEST PASSED ✓                       ║`);
  console.log(`╚══════════════════════════════════════════════════════╝`);
  console.log(`  Recipient balance of token #${HOUSE_ID}: ${balance}\n`);
}

main().catch((err) => {
  console.error("\n[FAIL]", err.message || err);
  process.exit(1);
});
