// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IComplianceRegistry} from "./interfaces/IComplianceRegistry.sol";
import {IBatchRegistry} from "./interfaces/IBatchRegistry.sol";
import {IRoleManager} from "./interfaces/IRoleManager.sol";

/// @title ComplianceRegistry
/// @notice Regulator approvals and recalls, plus the one-call check for consumers.
/// @dev Only the Regulator can approve or recall. A recall calls
///      BatchRegistry.markRecalled(), which freezes the batch. verifyForConsumer()
///      is a pure read, so the public QR page needs no wallet or gas.
contract ComplianceRegistry is IComplianceRegistry {
    IRoleManager public immutable roles;
    IBatchRegistry public immutable registry;

    mapping(uint256 => ComplianceRecord) private _records;

    error NotAuthorized();

    constructor(address roleManager, address batchRegistry) {
        roles = IRoleManager(roleManager);
        registry = IBatchRegistry(batchRegistry);
    }

    modifier onlyRegulator() {
        if (!roles.hasRole(roles.REGULATOR_ROLE(), msg.sender)) revert NotAuthorized();
        _;
    }

    /// @notice Regulator signs off a batch (report hash points to IPFS document).
    function approveBatch(uint256 batchId, bytes32 reportHash) external onlyRegulator {
        registry.getBatch(batchId); // reverts if batch does not exist
        ComplianceRecord storage r = _records[batchId];
        require(!r.recalled, "already recalled");
        r.approved = true;
        r.reportHash = reportHash;
        r.updatedAt = uint64(block.timestamp);
        emit BatchApproved(batchId, reportHash, msg.sender);
    }

    /// @notice Regulator recalls a batch. Permanent. Batch is frozen in BatchRegistry.
    function recallBatch(uint256 batchId, string calldata reason, bytes32 reportHash) external onlyRegulator {
        registry.getBatch(batchId);
        ComplianceRecord storage r = _records[batchId];
        r.recalled = true;
        r.approved = false;
        r.reason = reason;
        r.reportHash = reportHash;
        r.updatedAt = uint64(block.timestamp);
        registry.markRecalled(batchId);
        emit BatchRecalled(batchId, reason, msg.sender);
    }

    function getComplianceRecord(uint256 batchId) external view returns (ComplianceRecord memory) {
        return _records[batchId];
    }

    /// @notice Public check for the consumer QR page.
    function verifyForConsumer(uint256 batchId) external view returns (bool exists, bool safe, uint8 status) {
        if (batchId == 0 || batchId > registry.batchCount()) return (false, false, 0);
        IBatchRegistry.Batch memory b = registry.getBatch(batchId);
        ComplianceRecord memory r = _records[batchId];
        bool notBad = b.status != IBatchRegistry.Status.Compromised && b.status != IBatchRegistry.Status.Recalled;
        return (true, r.approved && !r.recalled && notBad && b.expiryDate > block.timestamp, uint8(b.status));
    }
}
