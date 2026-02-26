#!/usr/bin/env bash
# =============================================================================
# demo.sh — ZKP Cross-Chain Real Estate Bridge — Full End-to-End Demo
# =============================================================================
# Runs every step from scratch and prints progress throughout.
# Usage: chmod +x demo.sh && ./demo.sh
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP=0
HARDHAT_PID=""
RELAYER_PID=""

# ── Helpers ───────────────────────────────────────────────────────────────────
banner() {
  echo ""
  echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
  printf  "${BOLD}${BLUE}║  %-60s║${NC}\n" "$1"
  echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

step() {
  STEP=$((STEP+1))
  echo ""
  echo -e "${BOLD}${CYAN}┌─ Step ${STEP}: ${1}${NC}"
  echo -e "${BOLD}${CYAN}└────────────────────────────────────────────────────────────${NC}"
}

ok()   { echo -e "  ${GREEN}✔ ${1}${NC}"; }
info() { echo -e "  ${YELLOW}▶ ${1}${NC}"; }
log()  { echo -e "  ${NC}  ${1}${NC}"; }
fail() { echo -e "  ${RED}✘ ${1}${NC}"; exit 1; }

wait_rpc() {
  local url="$1" label="$2" max="${3:-30}"
  printf "  Waiting for %-30s" "$label"
  for i in $(seq 1 $max); do
    if curl -sf -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$url" >/dev/null 2>&1; then
      echo -e "  ${GREEN}ready ✔${NC}"; return 0
    fi
    printf "."; sleep 2
  done
  echo ""; fail "$label did not become ready"
}

deployed() {
  python3 -c "import json; print(json.load(open('${ROOT}/relayer/.deployed.json'))['$1'])"
}

# ── Trap: show active PIDs on exit ────────────────────────────────────────────
cleanup_msg() {
  echo ""
  echo -e "${BOLD}Active background processes:${NC}"
  [ -n "$HARDHAT_PID" ] && echo "  Hardhat node  PID $HARDHAT_PID  (http://127.0.0.1:8546)"
  [ -n "$RELAYER_PID" ] && echo "  Relayer       PID $RELAYER_PID"
  echo "  GoQuorum      Docker (http://127.0.0.1:21001)"
  echo ""
  echo "  To stop: kill $HARDHAT_PID $RELAYER_PID"
  echo "  To stop GoQuorum: cd private-chain/quorum-test-network && bash stop.sh"
}
trap cleanup_msg EXIT

# =============================================================================
# BEGIN
# =============================================================================
banner "ZKP Cross-Chain Real Estate Bridge — Full Demo"

echo -e "  ${BOLD}Architecture:${NC}"
log "Private chain  GoQuorum (QBFT)  →  HouseTokenizingGovernance.sol"
log "                                    3 parties approve a real estate"
log "                                    ↓ HouseFullyApproved event"
log "Relayer        snarkjs Groth16   →  generates ZKP proof off-chain"
log "Public chain   Hardhat EVM       →  Verifier.sol validates proof"
log "                                    HouseToken.sol mints ERC-1155 NFT"

# =============================================================================
step "Clean up previous processes"
# =============================================================================
info "Stopping any running relayer / Hardhat node..."
pkill -f "ts-node src/relayer" 2>/dev/null  && ok "Stopped previous relayer"   || true
pkill -f "hardhat node"        2>/dev/null  && ok "Stopped previous Hardhat"   || true
sleep 2
ok "Clean slate ready"

# =============================================================================
step "Prerequisites"
# =============================================================================
NODE_VER=$(node --version)
CIRCOM_VER=$(circom --version 2>&1 | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
SNARKJS_VER=$(snarkjs --version 2>&1 | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
DOCKER_VER=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)

ok "Node.js   $NODE_VER"
ok "circom    $CIRCOM_VER"
ok "snarkjs   $SNARKJS_VER"
ok "Docker    $DOCKER_VER"

# =============================================================================
step "ZKP Circuit — houseApproval.circom"
# =============================================================================
cd "$ROOT/circuits"

if [ -f "circuit_final.zkey" ] && [ -f "houseApproval_js/houseApproval.wasm" ] && [ -f "verification_key.json" ]; then
  ok "Artifacts already exist — skipping recompile"
else
  info "Compiling houseApproval.circom → R1CS + WASM..."
  circom houseApproval.circom --r1cs --wasm --sym --output . -l node_modules 2>&1 \
    | grep -E "constraints|Written|Everything"

  info "Groth16 trusted setup (phase 1 + phase 2)..."
  snarkjs groth16 setup houseApproval.r1cs pot14_final.ptau circuit_0000.zkey 2>&1 \
    | grep -E "INFO|WARN" | grep -v DEBUG | head -5

  info "Phase-2 ceremony contribution..."
  echo "demo-entropy-$(date +%s)" \
    | snarkjs zkey contribute circuit_0000.zkey circuit_final.zkey --name="Demo" 2>&1 \
    | grep -E "Contribution Hash|Circuit Hash" | head -4

  info "Exporting verification_key.json..."
  snarkjs zkey export verificationkey circuit_final.zkey verification_key.json 2>&1 \
    | grep -E "FINISHED|STARTED" | head -2

  info "Exporting Groth16 Verifier.sol..."
  snarkjs zkey export solidityverifier circuit_final.zkey \
    "$ROOT/public-chain/contracts/Verifier.sol" 2>&1 \
    | grep -E "FINISHED|STARTED" | head -2
fi

CONSTRAINTS=$(snarkjs r1cs info houseApproval.r1cs 2>&1 | grep -i "constraints" | head -2)
ok "Circuit compiled"
log "  Private signals : agentApproved, bankApproved"
log "  Public  signals : houseId"
log "  $CONSTRAINTS"
ok "Proving key      : circuit_final.zkey"
ok "Verification key : verification_key.json"
ok "Solidity verifier: public-chain/contracts/Verifier.sol"

# =============================================================================
step "Solidity Compilation — Hardhat / solc 0.8.20"
# =============================================================================
cd "$ROOT/public-chain"
info "Compiling all contracts..."
COMPILE_OUT=$(npx hardhat compile 2>&1 | tail -4)
echo "$COMPILE_OUT" | while IFS= read -r line; do log "$line"; done
ok "HouseTokenizingGovernance.sol  (GoQuorum)"
ok "Groth16Verifier.sol            (Hardhat — snarkjs generated)"
ok "HouseToken.sol ERC-1155        (Hardhat)"

# =============================================================================
step "GoQuorum Private Network — QBFT Consensus"
# =============================================================================
cd "$ROOT/private-chain/quorum-test-network"

RUNNING=$(docker ps --filter "name=quorum-test-network-validator1" \
               --filter "status=running" --format "{{.Names}}" 2>/dev/null | wc -l)
if [ "$RUNNING" -gt 0 ]; then
  ok "GoQuorum containers already running"
else
  info "Starting GoQuorum Docker Compose network..."
  docker compose up -d 2>&1 | grep -E "Started|Running|Created|Error" | head -10
fi

wait_rpc "http://127.0.0.1:21001" "GoQuorum validator1 :21001"

BLOCK_HEX=$(curl -sf -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:21001 | python3 -c "import sys,json; print(int(json.load(sys.stdin)['result'],16))")
CHAIN_ID=$(curl -sf -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
  http://127.0.0.1:21001 | python3 -c "import sys,json; print(int(json.load(sys.stdin)['result'],16))")

ok "GoQuorum is live — chainId: $CHAIN_ID  block: #$BLOCK_HEX"
echo ""
echo -e "  ${BOLD}Role → Account mapping:${NC}"
ok "Agent       (validator1) 0xed9d02e382b34818e88b88a309c7fe71e65f419d"
ok "Bank        (validator2) 0xb30f304642de3fee4365ed5cd06ea2e69d3fd0ca"
ok "HousingDept (validator3) 0x0886328869e4e1f401e1052a5f4aae8b45f42610"

# =============================================================================
step "Deploy HouseTokenizingGovernance → GoQuorum"
# =============================================================================
cd "$ROOT/private-chain"
info "Deploying with validator1 account (deployer + Agent role)..."
DEPLOY_OUT=$(npm run deploy-governance 2>&1)
echo "$DEPLOY_OUT" | grep -E "Connected|Deployer|Deploying|deployed at|Address saved" \
  | while IFS= read -r line; do ok "$line"; done
GOVERNANCE=$(deployed governance)
ok "Contract address : $GOVERNANCE"
ok "Agent    address : 0xed9d02e382b34818e88b88a309c7fe71e65f419d"
ok "Bank     address : 0xb30f304642de3fee4365ed5cd06ea2e69d3fd0ca"
ok "Housing  address : 0x0886328869e4e1f401e1052a5f4aae8b45f42610"

# =============================================================================
step "Hardhat Public Node — port 8546"
# =============================================================================
cd "$ROOT/public-chain"
info "Starting Hardhat node on port 8546..."
npx hardhat node --port 8546 > /tmp/hardhat-demo.log 2>&1 &
HARDHAT_PID=$!
wait_rpc "http://127.0.0.1:8546" "Hardhat :8546"

ACCT0=$(grep "Account #0:" /tmp/hardhat-demo.log | head -1 | awk '{print $3}')
ACCT0_BAL=$(grep "Account #0:" /tmp/hardhat-demo.log | head -1 | awk '{print $4,$5}')
ok "Hardhat node started (PID $HARDHAT_PID)"
ok "Deployer account: $ACCT0  $ACCT0_BAL"

# =============================================================================
step "Deploy Groth16Verifier + HouseToken → Hardhat"
# =============================================================================
cd "$ROOT/public-chain"
info "Deploying ZKP verifier and ERC-1155 token contract..."
DEPLOY_OUT=$(npx hardhat run scripts/deploy.ts --network localhost 2>&1)
echo "$DEPLOY_OUT" | grep -E "Deploying|deployed at|Balance|Addresses" \
  | while IFS= read -r line; do ok "$line"; done

VERIFIER=$(deployed verifier)
HOUSE_TOKEN=$(deployed houseToken)
ok "Groth16Verifier : $VERIFIER"
ok "HouseToken      : $HOUSE_TOKEN"
echo ""
log "  .deployed.json now contains all three contract addresses."

# =============================================================================
step "ZKP Relayer Service"
# =============================================================================
cd "$ROOT/relayer"
info "Starting cross-chain relayer..."
npm start > /tmp/relayer-demo.log 2>&1 &
RELAYER_PID=$!
sleep 6

echo ""
# Print the relayer startup banner from its log
grep -E "═|║|GoQuorum|Hardhat|Governance|HouseToken|Recipient|Relayer|Listening" \
  /tmp/relayer-demo.log | while IFS= read -r line; do log "$line"; done

# Confirm no fatal errors
if grep -q "Fatal\|FATAL\|Cannot find\|Error:" /tmp/relayer-demo.log 2>/dev/null; then
  fail "Relayer reported errors — check /tmp/relayer-demo.log"
fi
ok "Relayer running (PID $RELAYER_PID)"
ok "Listening for HouseFullyApproved events on GoQuorum..."

# =============================================================================
step "End-to-End Test Flow — 3 approvals → ZKP → ERC-1155 mint"
# =============================================================================
echo ""
echo -e "  ${BOLD}What will happen:${NC}"
log "  1. Agent (validator1) calls approveAsAgent(42) on GoQuorum"
log "  2. Bank  (validator2) calls approveAsBank(42) on GoQuorum"
log "  3. HousingDept (validator3) calls approveAsHousingDept(42) on GoQuorum"
log "  4. Contract emits HouseFullyApproved(houseId=42)"
log "  5. Relayer catches event, calls snarkjs.groth16.fullProve()"
log "     private: agentApproved=1, bankApproved=1"
log "     public : houseId=42"
log "  6. Relayer sends mintHouseToken(42, proof...) to Hardhat"
log "  7. Groth16Verifier.verifyProof() validates on-chain"
log "  8. HouseToken._mint(recipient, 42, 1) executes"
echo ""

cd "$ROOT/relayer"
npx ts-node src/test-flow.ts

# =============================================================================
# DONE
# =============================================================================
echo ""
banner "DEMO COMPLETE ✔"

echo -e "  ${BOLD}Deployed contracts:${NC}"
ok "GoQuorum  HouseTokenizingGovernance : $(deployed governance)"
ok "Hardhat   Groth16Verifier           : $(deployed verifier)"
ok "Hardhat   HouseToken (ERC-1155)     : $(deployed houseToken)"
echo ""
echo -e "  ${BOLD}Active services:${NC}"
ok "GoQuorum   http://127.0.0.1:21001  (Docker — QBFT 4 validators)"
ok "Hardhat    http://127.0.0.1:8546   (PID $HARDHAT_PID)"
ok "Relayer    listening               (PID $RELAYER_PID)"
