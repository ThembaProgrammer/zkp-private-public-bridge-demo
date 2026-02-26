// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title  HouseToken
 * @notice ERC-1155 token deployed on the public Hardhat / mainnet-fork chain.
 *
 *         Minting is only possible when a valid Groth16 ZKP is supplied,
 *         proving that the Agent + Bank approved the real estate asset on the
 *         private GoQuorum chain — WITHOUT revealing the individual approvals.
 *
 *  Token ID semantics
 *  ──────────────────
 *  Each unique houseId maps 1-to-1 to an ERC-1155 token ID.
 *  Only one token (amount = 1) is ever minted per real estate asset.
 */
interface IVerifier {
    function verifyProof(
        uint[2]    calldata _pA,
        uint[2][2] calldata _pB,
        uint[2]    calldata _pC,
        uint[1]    calldata _pubSignals
    ) external view returns (bool);
}

contract HouseToken is ERC1155, Ownable {

    // ── State ──────────────────────────────────────────────────────────────
    IVerifier public immutable verifier;

    /// @dev Tracks which houseIds have already been minted.
    mapping(uint256 => bool) public minted;

    // ── Events ─────────────────────────────────────────────────────────────
    event HouseTokenMinted(
        uint256 indexed houseId,
        address indexed recipient,
        bytes32         proofHash
    );

    // ── Errors ─────────────────────────────────────────────────────────────
    error InvalidProof();
    error AlreadyMinted(uint256 houseId);

    // ── Constructor ────────────────────────────────────────────────────────
    /**
     * @param _verifier  Address of the deployed Groth16 Verifier contract.
     * @param _uri       Base URI for token metadata (can be IPFS CID template).
     */
    constructor(address _verifier, string memory _uri)
        ERC1155(_uri)
        Ownable(msg.sender)
    {
        verifier = IVerifier(_verifier);
    }

    // ── External ───────────────────────────────────────────────────────────

    /**
     * @notice Mints a house NFT after verifying the ZKP.
     *
     * @param houseId      The real estate asset identifier (public signal).
     * @param _pA          Proof point A  (Groth16).
     * @param _pB          Proof point B  (Groth16).
     * @param _pC          Proof point C  (Groth16).
     * @param _pubSignals  Public signals array — [houseId].
     * @param recipient    Address that will receive the token.
     *
     * @dev  The relayer calls this function after generating the proof
     *       off-chain via snarkjs.
     */
    function mintHouseToken(
        uint256    houseId,
        uint[2]    calldata _pA,
        uint[2][2] calldata _pB,
        uint[2]    calldata _pC,
        uint[1]    calldata _pubSignals,
        address    recipient
    ) external {
        // 1. One-time mint guard
        if (minted[houseId]) revert AlreadyMinted(houseId);

        // 2. Public signal consistency check: houseId must match _pubSignals[0]
        require(_pubSignals[0] == houseId, "HouseToken: houseId mismatch");

        // 3. ZKP verification
        bool valid = verifier.verifyProof(_pA, _pB, _pC, _pubSignals);
        if (!valid) revert InvalidProof();

        // 4. Mint exactly 1 token
        minted[houseId] = true;
        _mint(recipient, houseId, 1, "");

        emit HouseTokenMinted(
            houseId,
            recipient,
            keccak256(abi.encode(_pA, _pB, _pC))
        );
    }

    // ── Admin ──────────────────────────────────────────────────────────────

    /**
     * @notice Owner can update the metadata URI.
     * @param newUri  New base URI (e.g. "ipfs://Qm.../{id}.json").
     */
    function setURI(string calldata newUri) external onlyOwner {
        _setURI(newUri);
    }
}
