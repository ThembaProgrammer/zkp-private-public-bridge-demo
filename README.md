<div align="center">

# Zero-Knowledge Real Estate Bridge

### *Where private consensus meets public truth — a cryptographic handshake between two worlds.*

---

`v1.0.0` &nbsp;|&nbsp; Solidity 0.8.20 &nbsp;|&nbsp; Circom 2.2 &nbsp;|&nbsp; Groth16 / BN254 &nbsp;|&nbsp; GoQuorum QBFT &nbsp;|&nbsp; Hardhat EVM &nbsp;|&nbsp; ERC-1155

[![Node.js](https://img.shields.io/badge/Node.js-22.x-339933?style=flat-square&logo=nodedotjs&logoColor=white)](https://nodejs.org)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-363636?style=flat-square&logo=solidity)](https://soliditylang.org)
[![Circom](https://img.shields.io/badge/Circom-2.2.3-6B46C1?style=flat-square)](https://docs.circom.io)
[![snarkjs](https://img.shields.io/badge/snarkjs-0.7.6-FF6B6B?style=flat-square)](https://github.com/iden3/snarkjs)
[![GoQuorum](https://img.shields.io/badge/GoQuorum-23.4.0-00A3E0?style=flat-square)](https://docs.goquorum.consensys.io)
[![License](https://img.shields.io/badge/License-MIT-22C55E?style=flat-square)](LICENSE)
[![ZKP](https://img.shields.io/badge/ZKP-Groth16-E91E63?style=flat-square)]()
[![Token](https://img.shields.io/badge/Token-ERC--1155-F59E0B?style=flat-square)]()

</div>

---

## Based on the article

> **https://medium.com/@thembalakhengcongo/bridging-the-secret-transparency-how-i-use-zero-knowledge-proof-zkp-to-link-private-and-public-6b5a68986dd9**

---

## The Idea

A house cannot be tokenised by one person's word alone.

This project proves that **three independent parties** — an Agent, a Bank, and a Housing Department — all privately approved a real estate asset on a **permissioned GoQuorum chain**, and then mints an **ERC-1155 NFT** on a **public Hardhat chain** to represent ownership — **without ever revealing the individual approvals on-chain**.

The bridge between the two worlds is a **Zero-Knowledge Proof**, generated off-chain by a relayer using **Groth16 / BN254** via `snarkjs`, and verified fully on-chain by a Solidity contract exported directly from the circuit's trusted setup.

---

## Architecture

```
╔══════════════════════════════════════════════╗
║          PRIVATE  GoQuorum Chain             ║
║          QBFT consensus · port 21001         ║
║                                              ║
║  ┌────────────────────────────────────────┐  ║
║  │    HouseTokenizingGovernance.sol       │  ║
║  │                                        │  ║
║  │  Agent       approveAsAgent(42)   ──┐  │  ║
║  │  Bank        approveAsBank(42)    ──┤  │  ║
║  │  HousingDept approveAsHousing(42) ──┘  │  ║
║  │                                        │  ║
║  │  → emit HouseFullyApproved(42)         │  ║
║  └────────────────────────────────────────┘  ║
╚══════════════════╦═══════════════════════════╝
                   ║  event detected
                   ▼
╔══════════════════════════════════════════════╗
║              RELAYER  (Node.js)              ║
║                                              ║
║  snarkjs.groth16.fullProve({                 ║
║    agentApproved : 1,   // private           ║
║    bankApproved  : 1,   // private           ║
║    houseId    : 42   // public            ║
║  })  →  π = (pA, pB, pC)                    ║
╚══════════════════╦═══════════════════════════╝
                   ║  mintHouseToken(42, π)
                   ▼
╔══════════════════════════════════════════════╗
║          PUBLIC   Hardhat Chain              ║
║          EVM · port 8546                     ║
║                                              ║
║  ┌─────────────────────────┐                 ║
║  │   Groth16Verifier.sol   │◄── verifyProof  ║
║  └────────────┬────────────┘                 ║
║               │ valid = true                 ║
║  ┌────────────▼────────────┐                 ║
║  │   HouseToken.sol        │                 ║
║  │   ERC-1155              │                 ║
║  │   _mint(recipient, 42)  │                 ║
║  └─────────────────────────┘                 ║
╚══════════════════════════════════════════════╝
```

### Why ZKP?

| Without ZKP | With ZKP |
|-------------|----------|
| Approval data is public | Approval data stays private |
| Trust requires seeing the data | Trust is mathematically enforced |
| Privacy vs. transparency trade-off | Both at once |
| Any party could lie about state | Circuit constraints make lying impossible |

The circuit enforces two rules at the constraint level — not at the application level:
1. `agentApproved ∈ {0,1}` and `bankApproved ∈ {0,1}` (boolean check)
2. `agentApproved × bankApproved = 1` (both must equal 1 simultaneously)

If either approval is missing, `snarkjs` cannot construct a valid proof. No valid proof means `Verifier.sol` returns `false`. `HouseToken.sol` reverts with `InvalidProof()`. The NFT is never minted. **The math is the policy.**

---

## Repository Structure

```
ZKP/
│
├── demo.sh                              ← One-command full demo (start here)
├── .env.example                         ← Environment variable template
│
├── circuits/                            ── ZKP Layer ──
│   ├── houseApproval.circom             ← Groth16 circuit (4 constraints)
│   ├── compile-circuit.sh               ← Compile + ceremony + export Verifier.sol
│   ├── circuit_final.zkey               ← Proving key  (post-ceremony)
│   ├── verification_key.json            ← Verification key
│   └── houseApproval_js/
│       └── houseApproval.wasm           ← Witness generator
│
├── private-chain/                       ── GoQuorum Layer ──
│   ├── setup-quorum.sh                  ← Bootstrap GoQuorum via Docker
│   ├── package.json
│   ├── contracts/
│   │   └── HouseTokenizingGovernance.sol
│   └── scripts/
│       └── deploy-governance.ts
│
├── public-chain/                        ── Hardhat Layer ──
│   ├── hardhat.config.ts                ← localhost = port 8546
│   ├── package.json
│   ├── contracts/
│   │   ├── HouseToken.sol               ← ERC-1155 with ZKP mint gate
│   │   ├── Verifier.sol                 ← snarkjs-generated Groth16 verifier
│   │   └── HouseTokenizingGovernance.sol← Shared for Hardhat compilation
│   └── scripts/
│       └── deploy.ts
│
└── relayer/                             ── Bridge Layer ──
    ├── package.json
    └── src/
        ├── relayer.ts                   ← Event listener + prover + minter
        └── test-flow.ts                 ← E2E test simulation
```

---

## Prerequisites

| Tool | Version | Purpose | Install |
|------|---------|---------|---------|
| **Node.js** | ≥ 18 LTS | Runtime | [nodejs.org](https://nodejs.org) |
| **npm** | ≥ 9 | Package manager | Ships with Node |
| **Docker** | ≥ 20.10 | GoQuorum network | [docs.docker.com](https://docs.docker.com/get-docker/) |
| **Docker Compose** | v2 | Container orchestration | [docs.docker.com](https://docs.docker.com/compose/install/) |
| **circom** | ≥ 2.1 | Circuit compiler | `cargo install circom` |
| **snarkjs** | ≥ 0.7 | Proof system | `npm install -g snarkjs` |
| **Rust** | stable | Required by circom | [rustup.rs](https://rustup.rs) |

> **Recommended IDE:** VS Code + [Hardhat Solidity](https://marketplace.visualstudio.com/items?itemName=NomicFoundation.hardhat-solidity) extension

---

## Quickstart — One Command

```bash
git clone https://github.com/ThembaProgrammer/zkp-private-public-bridge-demo
cd zkp-bridge
cp .env.example .env        # fill in your keys (see .env.example)
chmod +x demo.sh && ./demo.sh
```

`demo.sh` handles everything: cleanup → circuit compile → Solidity compile → GoQuorum → deploy governance → Hardhat node → deploy public contracts → start relayer → run E2E test.

---

## Step-by-Step Execution

### Step 0 — Clone & configure

```bash
git clone https://github.com/ThembaProgrammer/zkp-private-public-bridge-demo
cd zkp-bridge
cp .env.example .env
```

Edit `.env` — at minimum set the GoQuorum account keys once the network is running (Step 3 will tell you the addresses).

---

### Step 1 — Compile the ZKP Circuit

```bash
cd circuits
npm install circomlib          # install circuit library
chmod +x compile-circuit.sh
./compile-circuit.sh           # compile → ceremony → export Verifier.sol
```

**What this produces:**

| File | Purpose |
|------|---------|
| `houseApproval.r1cs` | R1CS constraint system (4 constraints) |
| `houseApproval_js/houseApproval.wasm` | Witness generator (used by relayer) |
| `circuit_final.zkey` | Groth16 proving key (post phase-2 ceremony) |
| `verification_key.json` | Verification key (used for local proof checks) |
| `public-chain/contracts/Verifier.sol` | **Solidity verifier — overwrites stub** |

> The circuit's public signal layout: `[0] = houseId`. This is what gets embedded in the proof and checked on-chain.

---

### Step 2 — Compile Solidity

Must run before Step 4 — the governance deploy script needs the Hardhat-compiled artifact.

```bash
cd ../public-chain
npm install
npx hardhat compile
```

---

### Step 3 — Start GoQuorum Private Network

```bash
cd ../private-chain
chmod +x setup-quorum.sh
./setup-quorum.sh
```

The quickstart boots **4 QBFT validator nodes** via Docker Compose. Once healthy, the node RPC endpoints are:

| Node | Host Port | Role in demo |
|------|-----------|-------------|
| validator1 | `21001` | Agent (deployer) |
| validator2 | `21002` | Bank |
| validator3 | `21003` | Housing Department |
| validator4 | `21004` | — |

> **Port note:** `rpcnode` maps to host port `8545`, but this conflicts with the default Hardhat port if you run both on the same machine. The demo uses **validator1 on port `21001`** as the GoQuorum RPC endpoint. Update `.env` accordingly:
> ```
> QUORUM_RPC_URL=http://127.0.0.1:21001
> ```

**Extracting account private keys** (GoQuorum quickstart uses empty keystore password):

```bash
node -e "
const { ethers } = require('ethers');
const fs = require('fs');
const nodes = ['validator1','validator2','validator3','validator4'];
Promise.all(nodes.map(async n => {
  const ks = fs.readFileSync(
    \`private-chain/quorum-test-network/config/nodes/\${n}/accountKeystore\`, 'utf8');
  const w = await ethers.Wallet.fromEncryptedJson(ks, '');
  console.log(\`\${n}: \${w.address}  \${w.privateKey}\`);
}));
"
```

---

### Step 4 — Deploy Governance Contract → GoQuorum

```bash
cd ../private-chain
npm install
npm run deploy-governance
```

Writes the governance address to `relayer/.deployed.json`.

---

### Step 5 — Start the Public Hardhat Node

```bash
cd ../public-chain

# Port 8546 — intentionally avoids conflict with GoQuorum
npx hardhat node --port 8546
```

Keep this terminal open.

---

### Step 6 — Deploy Public Contracts → Hardhat

In a new terminal:

```bash
cd public-chain
npx hardhat run scripts/deploy.ts --network localhost
```

Merges `verifier` and `houseToken` addresses into `relayer/.deployed.json` alongside the governance address from Step 4.

---

### Step 7 — Start the Relayer

```bash
cd ../relayer
npm install
npm start
```

Expected output:
```
╔══════════════════════════════════════════════════════╗
║        ZKP Cross-Chain Relayer — starting up         ║
╚══════════════════════════════════════════════════════╝
  GoQuorum   → http://127.0.0.1:21001
  Hardhat    → http://127.0.0.1:8546
  Governance → 0x9d13C6D3aFE1721BEef56B55D303B09E021E27ab
  HouseToken → 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
  Recipient  → 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

Listening for HouseFullyApproved events on GoQuorum...
```

---

### Step 8 — Run the End-to-End Test

In another terminal:

```bash
cd relayer
npm run test-flow
```

Expected output:
```
Step 1 — Agent approval...       tx: 0x6e3c37... ✓
Step 2 — Bank approval...        tx: 0x4fe877... ✓
Step 3 — HousingDept approval... tx: 0x63a300... ✓

Approval state: Agent=true | Bank=true | HousingDept=true | FullyApproved=true

HouseFullyApproved event emitted on GoQuorum.
Waiting for the relayer to generate the ZKP and mint on Hardhat...

  Waiting for relayer to mint token.
  Token balance confirmed ✓

╔══════════════════════════════════════════════════════╗
║                  TEST PASSED ✓                       ║
╚══════════════════════════════════════════════════════╝
  Recipient balance of token #42: 1
```

---

## Port Reference

| Service | Port | Notes |
|---------|------|-------|
| GoQuorum validator1 | `21001` | Primary RPC — used by relayer and test-flow |
| GoQuorum validator2 | `21002` | Bank approvals |
| GoQuorum validator3 | `21003` | HousingDept approvals |
| GoQuorum validator4 | `21004` | Spare validator |
| Hardhat JSON-RPC | `8546` | Public chain — set in `hardhat.config.ts` |

---

## Smart Contracts

### `HouseTokenizingGovernance.sol` — GoQuorum

```
Three-of-three multi-party approval registry.

approveAsAgent(houseId)       → only Agent address
approveAsBank(houseId)        → only Bank address
approveAsHousingDept(houseId) → only HousingDept address

Once all three call their function:
  emit HouseFullyApproved(houseId)   ← relayer trigger
```

### `Groth16Verifier.sol` — Hardhat *(snarkjs generated)*

```
verifyProof(pA, pB, pC, pubSignals[1]) → bool

Verifies a Groth16 proof over BN254.
pubSignals[0] = houseId
```

### `HouseToken.sol` — Hardhat

```
mintHouseToken(houseId, pA, pB, pC, pubSignals, recipient)

1. Guard: revert AlreadyMinted if houseId already minted
2. Check: pubSignals[0] == houseId
3. Verify: Groth16Verifier.verifyProof(...)  → revert InvalidProof if false
4. Mint:  _mint(recipient, houseId, 1, "")
5. Emit:  HouseTokenMinted(houseId, recipient, proofHash)
```

---

## ZKP Circuit

```
houseApproval.circom
├── Private inputs
│   ├── agentApproved   ∈ {0,1}
│   └── bankApproved    ∈ {0,1}
├── Public inputs
│   └── houseId      (uint256)
└── Constraints (4 total)
    ├── agentApproved  × (agentApproved  − 1) = 0   (boolean)
    ├── bankApproved   × (bankApproved   − 1) = 0   (boolean)
    ├── agentApproved  × bankApproved          = 1   (both must be 1)
    └── houseId     × bothApproved          = ·   (binding)
```

**Trusted setup:** Groth16 phase-2 ceremony using `powersOfTau28_hez_final_14.ptau` (supports up to 2¹⁴ = 16,384 constraints). The `compile-circuit.sh` script runs the full ceremony locally. For production, use a multi-party ceremony or an established PTAU file.

---

## Relayer Flow

```
GoQuorum event ──► generateProof(houseId)
                        │
                        ├── snarkjs.groth16.fullProve(
                        │     { agentApproved:"1",
                        │       bankApproved:"1",
                        │       houseId: id },
                        │     houseApproval.wasm,
                        │     circuit_final.zkey
                        │   )
                        │
                        ├── local verify: snarkjs.groth16.verify(vKey, pubSig, proof)
                        │
                        └── exportSolidityCallData(proof, pubSig)
                                    │
                                    ▼
                    HouseToken.mintHouseToken(
                      houseId, pA, pB, pC, pubSignals, recipient
                    )
```

---

## Environment Variables

Copy `.env.example` to `.env` and populate:

```bash
# GoQuorum
QUORUM_RPC_URL=http://127.0.0.1:21001
QUORUM_DEPLOYER_PK=<validator1 private key>
QUORUM_AGENT_PK=<validator1 private key>
QUORUM_AGENT_ADDRESS=<validator1 address>
QUORUM_BANK_PK=<validator2 private key>
QUORUM_BANK_ADDRESS=<validator2 address>
QUORUM_HOUSING_DEPT_PK=<validator3 private key>
QUORUM_HOUSING_DEPT_ADDRESS=<validator3 address>

# Hardhat
HARDHAT_RPC_URL=http://127.0.0.1:8546
HARDHAT_DEPLOYER_PK=<Hardhat account #0 private key>

# Relayer
RELAYER_PRIVATE_KEY=<Hardhat account key for signing txs>
NFT_RECIPIENT=<address to receive the minted token>

# Test
TEST_HOUSE_ID=42
MINT_POLL_TIMEOUT_MS=60000
POLL_INTERVAL_MS=3000
```

---

## Security Notes

| Topic | Status | Notes |
|-------|--------|-------|
| Private keys in `.env` | ⚠️ Dev only | Never commit `.env` to source control |
| Trusted setup | ⚠️ Single contributor | Use multi-party ceremony for production |
| Relayer witnesses | ⚠️ Hardcoded | `agentApproved=1, bankApproved=1` are hardcoded; in production, source from a confidential attestation service |
| Verifier.sol | ✅ Real | Generated by `snarkjs zkey export solidityverifier` — not a stub |
| On-chain proof check | ✅ | `Groth16Verifier.verifyProof()` runs full BN254 pairing check in EVM assembly |
| Mint idempotency | ✅ | `minted[houseId]` mapping prevents double-minting |
| Role access control | ✅ | `onlyAgent`, `onlyBank`, `onlyHousingDept` modifiers on all approval functions |


---

<div align="center">

**Built with ❤️ for the Web3 Community**

*Empowering communities through decentralized finance*

[Website](https://yourproject.com) • [Documentation](./docs) • [Twitter](https://twitter.com/yourproject) • [Discord](https://discord.gg/yourserver)

</div>
