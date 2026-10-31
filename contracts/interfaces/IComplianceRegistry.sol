// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IComplianceRegistry
/// @notice Regulator approvals/recalls and the public consumer check.
interface IComplianceRegistry {
    struct ComplianceRecord {
        bool    approved;
        bool    recalled;
        bytes32 reportHash;   // hash of approval/recall document on IPFS
        string  reason;       // recall reason (empty if not recalled)
        uint64  updatedAt;
    }

    event BatchApproved(uint256 indexed batchId, bytes32 reportHash, address indexed regulator);
    event BatchRecalled(uint256 indexed batchId, string reason, address indexed regulator);

    function approveBatch(uint256 batchId, bytes32 reportHash) external;
    function recallBatch(uint256 batchId, string calldata reason, bytes32 reportHash) external;

    function getComplianceRecord(uint256 batchId) external view returns (ComplianceRecord memory);

    /// @notice One-call public check used by the consumer QR page.
    /// @return exists       batch id is real
    /// @return safe         approved && not compromised && not recalled && not expired
    /// @return status       lifecycle status code (see IBatchRegistry.Status)
    function verifyForConsumer(uint256 batchId) external view returns (bool exists, bool safe, uint8 status);
}
