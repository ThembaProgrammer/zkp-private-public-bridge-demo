// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  HouseTokenizingGovernance
 * @notice Deployed on the private GoQuorum network.
 *         Three designated parties (Agent, Bank, HousingDept) each call
 *         their approval function for a given houseId.  Once all three have
 *         approved, the HouseFullyApproved event is emitted — the relayer
 *         picks this up and triggers ZKP-based minting on the public chain.
 */
contract HouseTokenizingGovernance {

    // ── Roles ──────────────────────────────────────────────────────────────
    address public immutable agent;
    address public immutable bank;
    address public immutable housingDept;

    // ── State ──────────────────────────────────────────────────────────────
    struct ApprovalState {
        bool agentApproved;
        bool bankApproved;
        bool housingDeptApproved;
        bool fullyApproved;
    }

    mapping(uint256 => ApprovalState) public approvals;

    // ── Events ─────────────────────────────────────────────────────────────
    /// @notice Emitted each time a single party approves a real estate asset.
    event HouseApproved(
        uint256 indexed houseId,
        address indexed approver,
        string  role
    );

    /// @notice Emitted when ALL THREE parties have approved.
    ///         The relayer listens for this event.
    event HouseFullyApproved(uint256 indexed houseId);

    // ── Modifiers ──────────────────────────────────────────────────────────
    modifier onlyAgent()       { require(msg.sender == agent,       "Not Agent");       _; }
    modifier onlyBank()        { require(msg.sender == bank,        "Not Bank");        _; }
    modifier onlyHousingDept() { require(msg.sender == housingDept, "Not HousingDept"); _; }

    // ── Constructor ────────────────────────────────────────────────────────
    constructor(
        address _agent,
        address _bank,
        address _housingDept
    ) {
        agent       = _agent;
        bank        = _bank;
        housingDept = _housingDept;
    }

    // ── External Functions ─────────────────────────────────────────────────

    /**
     * @notice Agent approves a real estate tokenization.
     * @param houseId  The unique on-chain identifier for the real estate asset.
     */
    function approveAsAgent(uint256 houseId) external onlyAgent {
        ApprovalState storage s = approvals[houseId];
        require(!s.agentApproved, "Agent already approved");
        s.agentApproved = true;
        emit HouseApproved(houseId, msg.sender, "Agent");
        _checkFullApproval(houseId);
    }

    /**
     * @notice Bank approves a real estate tokenization.
     * @param houseId  The unique on-chain identifier for the real estate asset.
     */
    function approveAsBank(uint256 houseId) external onlyBank {
        ApprovalState storage s = approvals[houseId];
        require(!s.bankApproved, "Bank already approved");
        s.bankApproved = true;
        emit HouseApproved(houseId, msg.sender, "Bank");
        _checkFullApproval(houseId);
    }

    /**
     * @notice Housing Department approves a real estate tokenization.
     * @param houseId  The unique on-chain identifier for the real estate asset.
     */
    function approveAsHousingDept(uint256 houseId) external onlyHousingDept {
        ApprovalState storage s = approvals[houseId];
        require(!s.housingDeptApproved, "HousingDept already approved");
        s.housingDeptApproved = true;
        emit HouseApproved(houseId, msg.sender, "HousingDept");
        _checkFullApproval(houseId);
    }

    // ── View Functions ─────────────────────────────────────────────────────
    function getApprovalState(uint256 houseId)
        external
        view
        returns (bool _agent, bool _bank, bool _housing, bool _full)
    {
        ApprovalState storage s = approvals[houseId];
        return (s.agentApproved, s.bankApproved, s.housingDeptApproved, s.fullyApproved);
    }

    // ── Internal ───────────────────────────────────────────────────────────
    function _checkFullApproval(uint256 houseId) internal {
        ApprovalState storage s = approvals[houseId];
        if (
            s.agentApproved &&
            s.bankApproved  &&
            s.housingDeptApproved &&
            !s.fullyApproved
        ) {
            s.fullyApproved = true;
            emit HouseFullyApproved(houseId);
        }
    }
}
