#!/usr/bin/env bash
# =============================================================================
# compile-circuit.sh
# =============================================================================
# Compiles houseApproval.circom and produces:
#   • houseApproval.r1cs          — R1CS constraint file
#   • houseApproval_js/           — WASM witness generator
#   • pot14_final.ptau             — Powers of Tau (downloaded if absent)
#   • circuit_0000.zkey            — Initial proving key
#   • circuit_final.zkey           — Finalised proving key (Groth16)
#   • verification_key.json        — Exported verification key
#   • ../public-chain/contracts/Verifier.sol  — Solidity verifier (overwrites stub)
#
# Usage:
#   cd circuits
#   chmod +x compile-circuit.sh
#   ./compile-circuit.sh
#
# Prerequisites:
#   • Node.js >= 18
#   • circom  >= 2.1   (cargo install circom  OR  npm install -g circom)
#   • snarkjs >= 0.7   (npm install -g snarkjs)
#   • circomlib        (npm install circomlib  — in the circuits/ directory)
# =============================================================================

set -euo pipefail

CIRCUIT_NAME="houseApproval"
PTAU_FILE="pot14_final.ptau"
PTAU_URL="https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_14.ptau"
VERIFIER_OUT="../public-chain/contracts/Verifier.sol"

echo "============================================================"
echo " ZKP Circuit Compilation — HouseApproval (Groth16 / BN254)"
echo "============================================================"
echo ""

# ── 0. Install circomlib if not present ──────────────────────────────────────
if [ ! -d "node_modules/circomlib" ]; then
  echo "[0/6] Installing circomlib..."
  npm install circomlib
fi

# ── 1. Compile circom → r1cs + wasm ─────────────────────────────────────────
echo "[1/6] Compiling ${CIRCUIT_NAME}.circom..."
circom "${CIRCUIT_NAME}.circom" \
  --r1cs \
  --wasm \
  --sym \
  --output . \
  -l node_modules

echo "      Constraints: $(snarkjs r1cs info ${CIRCUIT_NAME}.r1cs 2>&1 | grep '#Constraints')"

# ── 2. Download Powers of Tau (if missing) ───────────────────────────────────
if [ ! -f "${PTAU_FILE}" ]; then
  echo "[2/6] Downloading ${PTAU_FILE} (~70 MB)..."
  curl -L "${PTAU_URL}" -o "${PTAU_FILE}"
else
  echo "[2/6] ${PTAU_FILE} already present — skipping download."
fi

# ── 3. Setup: generate initial zkey ──────────────────────────────────────────
echo "[3/6] Generating initial proving key (circuit_0000.zkey)..."
snarkjs groth16 setup \
  "${CIRCUIT_NAME}.r1cs" \
  "${PTAU_FILE}" \
  circuit_0000.zkey

# ── 4. Contribute to phase-2 ceremony (deterministic for local dev) ──────────
echo "[4/6] Contributing to phase-2 ceremony..."
echo "zkp-bridge-local-entropy-$(date +%s)" | \
  snarkjs zkey contribute \
    circuit_0000.zkey \
    circuit_final.zkey \
    --name="House Approval Ceremony" \
    -v

# ── 5. Export verification key ───────────────────────────────────────────────
echo "[5/6] Exporting verification_key.json..."
snarkjs zkey export verificationkey circuit_final.zkey verification_key.json

# ── 6. Generate Solidity Verifier ────────────────────────────────────────────
echo "[6/6] Generating Solidity Verifier → ${VERIFIER_OUT}..."
snarkjs zkey export solidityverifier circuit_final.zkey "${VERIFIER_OUT}"

echo ""
echo "============================================================"
echo " Done!"
echo "  • verification_key.json  → circuits/verification_key.json"
echo "  • Verifier.sol           → ${VERIFIER_OUT}"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. cd ../public-chain && npm install && npx hardhat compile"
echo "  2. npx hardhat run scripts/deploy.ts --network localhost"
echo "  3. cd ../relayer && npm install && npx ts-node src/relayer.ts"
