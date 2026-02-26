#!/usr/bin/env bash
# =============================================================================
# setup-quorum.sh
# =============================================================================
# Bootstraps the private GoQuorum network using the ConsenSys Quorum
# Developer Quickstart.
#
# Usage:
#   cd private-chain
#   chmod +x setup-quorum.sh
#   ./setup-quorum.sh
#
# Prerequisites:
#   • Docker >= 20.10
#   • Docker Compose >= 2.x
#   • Node.js >= 18
#   • npx (ships with npm)
# =============================================================================

set -euo pipefail

QUICKSTART_DIR="quorum-quickstart"

echo "========================================================"
echo "  Private GoQuorum Network Setup"
echo "========================================================"
echo ""

# ── 1. Clone / update Quorum Developer Quickstart ────────────────────────────
if [ -d "${QUICKSTART_DIR}" ]; then
  echo "[1/4] ${QUICKSTART_DIR} already exists — skipping clone."
else
  echo "[1/4] Bootstrapping Quorum Developer Quickstart via npx..."
  # Consensys quickstart — interactive mode disabled, use IBFT2 preset
  npx quorum-dev-quickstart \
    --clientType=besu-tessera \
    --outputPath="./${QUICKSTART_DIR}" \
    --consensus=ibft2 \
    --privacy=true \
    --monitoring=none \
    --noPrompt
fi

cd "${QUICKSTART_DIR}"

# ── 2. Start the network ──────────────────────────────────────────────────────
echo ""
echo "[2/4] Starting GoQuorum network (Docker Compose)..."
./run.sh

# ── 3. Verify RPC is accessible ──────────────────────────────────────────────
echo ""
echo "[3/4] Checking JSON-RPC endpoint..."
sleep 5   # brief pause for nodes to initialize
BLOCK=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545 | python3 -c "import sys,json; print(json.load(sys.stdin)['result'])" 2>/dev/null || echo "pending")
echo "  Current block: ${BLOCK}"

# ── 4. Print account info ─────────────────────────────────────────────────────
echo ""
echo "[4/4] Default accounts (from genesis / key files):"
echo "  Check ${QUICKSTART_DIR}/config/besu/networkFiles/ for keys"
echo "  Or use: docker exec <node-container> geth account list"
echo ""
echo "========================================================"
echo "  GoQuorum is running on http://127.0.0.1:8545"
echo "  Update your .env file with the role private keys."
echo "  Then deploy the governance contract:"
echo "    cd .. && npx ts-node scripts/deploy-governance.ts"
echo "========================================================"
