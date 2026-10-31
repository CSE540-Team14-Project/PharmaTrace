// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IBatchRegistry
/// @notice Public surface of the batch lifecycle + custody contract.
interface IBatchRegistry {
    /// @dev Lifecycle. Created -> Shipped -> Received -> Stored -> Dispensed.
    ///      Compromised (cold chain broken) and Recalled (regulator) are terminal flags.
    enum Status { Created, Shipped, Received, Stored, Dispensed, Compromised, Recalled }

    struct Batch {
        uint256 id;
        string  drugName;
        string  lotNumber;
        uint64  expiryDate;        // unix seconds
        bytes32 certificateHash;   // hash of certificate stored on IPFS (CID kept off-chain / in event)
        address manufacturer;
        address currentHolder;
        address pendingRecipient;  // non-zero only while Shipped
        Status  status;
        uint64  createdAt;
    }

    struct CustodyRecord {
        address from;
        address to;
        Status  status;
        uint64  timestamp;
    }

    // ---- events (audit trail) ----
    event BatchRegistered(uint256 indexed batchId, address indexed manufacturer, string drugName, string lotNumber);
    event CertificateAttached(uint256 indexed batchId, bytes32 certificateHash, string ipfsCid);
    event BatchShipped(uint256 indexed batchId, address indexed from, address indexed to);
    event CustodyAccepted(uint256 indexed batchId, address indexed newHolder);
    event BatchStored(uint256 indexed batchId, address indexed holder, string location);
    event BatchDispensed(uint256 indexed batchId, address indexed pharmacy);
    event StatusForced(uint256 indexed batchId, Status status, address indexed by);

    // ---- manufacturer ----
    function registerBatch(string calldata drugName, string calldata lotNumber, uint64 expiryDate, bytes32 certificateHash, string calldata ipfsCid) external returns (uint256 batchId);
    function attachCertificate(uint256 batchId, bytes32 certificateHash, string calldata ipfsCid) external;

    // ---- custody chain (current holder / recipient) ----
    function shipBatch(uint256 batchId, address to) external;
    function acceptCustody(uint256 batchId) external;
    function logStorage(uint256 batchId, string calldata location) external;
    function markDispensed(uint256 batchId) external;

    // ---- called only by ColdChainMonitor / ComplianceRegistry ----
    function markCompromised(uint256 batchId) external;
    function markRecalled(uint256 batchId) external;

    // ---- reads ----
    function getBatch(uint256 batchId) external view returns (Batch memory);
    function getCustodyTrail(uint256 batchId) external view returns (CustodyRecord[] memory);
    function batchCount() external view returns (uint256);
}
