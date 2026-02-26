pragma circom 2.0.0;

/*
 * houseApproval.circom
 *
 * Proves that both the Agent and the Bank have approved a real estate
 * tokenization WITHOUT revealing the individual approval values to the
 * public chain.
 *
 * Private Signals : agentApproved, bankApproved  (must both equal 1)
 * Public  Signals : houseId                      (the on-chain token identifier)
 */

template HouseApproval() {
    // ── Private inputs (not exposed in the proof) ──────────────────────────
    signal input agentApproved;      // 1 = approved, 0 = not approved
    signal input bankApproved;       // 1 = approved, 0 = not approved

    // ── Public inputs (embedded in the proof / visible on-chain) ──────────
    signal input houseId;            // unique real estate asset identifier

    // ── Internal signals ──────────────────────────────────────────────────
    signal agentCheck;
    signal bankCheck;
    signal bothApproved;

    // ── Constraints ───────────────────────────────────────────────────────

    // 1. Each approval flag must be boolean (0 or 1)
    agentCheck <== agentApproved * (agentApproved - 1);
    agentCheck === 0;

    bankCheck <== bankApproved * (bankApproved - 1);
    bankCheck === 0;

    // 2. Both parties must have approved: agentApproved * bankApproved == 1
    bothApproved <== agentApproved * bankApproved;
    bothApproved === 1;

    // 3. houseId is declared public above — circom automatically includes
    //    all public inputs in publicSignals, so no extra constraint needed.
    //    We add a trivial self-constraint to silence unused-signal warnings.
    signal houseBound;
    houseBound <== houseId * bothApproved;
    houseBound * 0 === 0;
}

component main {public [houseId]} = HouseApproval();
