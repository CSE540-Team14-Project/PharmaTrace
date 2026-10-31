// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IBatchRegistry} from "./interfaces/IBatchRegistry.sol";
import {IRoleManager} from "./interfaces/IRoleManager.sol";

/// @title BatchRegistry
/// @notice Creates drug batches and tracks custody from manufacturer to pharmacy.
/// @dev Rules enforced here:
///      1. Only a Manufacturer can register a batch.
///      2. Only the CURRENT HOLDER can ship it, and only to a Distributor or Pharmacy.
///      3. Only the named recipient can accept custody (two-step transfer, no forced dumps).
///      4. Compromised / Recalled / Dispensed batches are frozen: no more custody moves.
///      5. ColdChainMonitor and ComplianceRegistry are the only contracts that may
///         force Compromised / Recalled (wired once by the Regulator via setModules).
///      Every state change emits an event and appends to the custody trail.
contract BatchRegistry is IBatchRegistry {
    IRoleManager public immutable roles;

    address public coldChainMonitor;
    address public complianceRegistry;

    uint256 private _nextId = 1;
    mapping(uint256 => Batch) private _batches;
    mapping(uint256 => CustodyRecord[]) private _trail;

    error NotAuthorized();
    error UnknownBatch();
    error BadStatus(Status current);
    error BadRecipient();
    error AlreadyWired();

    constructor(address roleManager) {
        roles = IRoleManager(roleManager);
    }

    // ---------------------------------------------------------------- modifiers
    modifier onlyRole(bytes32 role) {
        if (!roles.hasRole(role, msg.sender)) revert NotAuthorized();
        _;
    }
    modifier exists(uint256 id) {
        if (_batches[id].id == 0) revert UnknownBatch();
        _;
    }
    modifier onlyHolder(uint256 id) {
        if (_batches[id].currentHolder != msg.sender) revert NotAuthorized();
        _;
    }
    /// @dev Frozen batches cannot move any further.
    modifier notFrozen(uint256 id) {
        Status s = _batches[id].status;
        if (s == Status.Compromised || s == Status.Recalled || s == Status.Dispensed) revert BadStatus(s);
        _;
    }

    // ------------------------------------------------------------------- wiring
    /// @notice One-time link to the other two contracts. Regulator only.
    function setModules(address monitor, address compliance) external onlyRole(roles.REGULATOR_ROLE()) {
        if (coldChainMonitor != address(0)) revert AlreadyWired();
        coldChainMonitor = monitor;
        complianceRegistry = compliance;
    }

    // ------------------------------------------------------------- manufacturer
    /// @notice Create a batch. Caller becomes manufacturer and first holder. Status = Created.
    function registerBatch(
        string calldata drugName,
        string calldata lotNumber,
        uint64 expiryDate,
        bytes32 certificateHash,
        string calldata ipfsCid
    ) external onlyRole(roles.MANUFACTURER_ROLE()) returns (uint256 batchId) {
        batchId = _nextId++;
        _batches[batchId] = Batch({
            id: batchId, drugName: drugName, lotNumber: lotNumber, expiryDate: expiryDate,
            certificateHash: certificateHash, manufacturer: msg.sender, currentHolder: msg.sender,
            pendingRecipient: address(0), status: Status.Created, createdAt: uint64(block.timestamp)
        });
        _trail[batchId].push(CustodyRecord(address(0), msg.sender, Status.Created, uint64(block.timestamp)));
        emit BatchRegistered(batchId, msg.sender, drugName, lotNumber);
        emit CertificateAttached(batchId, certificateHash, ipfsCid);
    }

    /// @notice Replace/attach the certificate hash (document itself lives on IPFS).
    function attachCertificate(uint256 batchId, bytes32 certificateHash, string calldata ipfsCid)
        external exists(batchId) onlyHolder(batchId)
    {
        require(msg.sender == _batches[batchId].manufacturer, "manufacturer only");
        _batches[batchId].certificateHash = certificateHash;
        emit CertificateAttached(batchId, certificateHash, ipfsCid);
    }

    // ------------------------------------------------------------ custody chain
    /// @notice Holder offers the batch to `to` (Distributor or Pharmacy). Status = Shipped.
    function shipBatch(uint256 batchId, address to)
        external exists(batchId) onlyHolder(batchId) notFrozen(batchId)
    {
        Batch storage b = _batches[batchId];
        if (b.status == Status.Shipped) revert BadStatus(b.status);
        if (!(roles.hasRole(roles.DISTRIBUTOR_ROLE(), to) || roles.hasRole(roles.PHARMACY_ROLE(), to))) revert BadRecipient();
        b.pendingRecipient = to;
        b.status = Status.Shipped;
        _trail[batchId].push(CustodyRecord(msg.sender, to, Status.Shipped, uint64(block.timestamp)));
        emit BatchShipped(batchId, msg.sender, to);
    }

    /// @notice Named recipient takes custody. Status = Received.
    function acceptCustody(uint256 batchId) external exists(batchId) notFrozen(batchId) {
        Batch storage b = _batches[batchId];
        if (b.status != Status.Shipped) revert BadStatus(b.status);
        if (b.pendingRecipient != msg.sender) revert NotAuthorized();
        address from = b.currentHolder;
        b.currentHolder = msg.sender;
        b.pendingRecipient = address(0);
        b.status = Status.Received;
        _trail[batchId].push(CustodyRecord(from, msg.sender, Status.Received, uint64(block.timestamp)));
        emit CustodyAccepted(batchId, msg.sender);
    }

    /// @notice Holder records where the batch is stored. Status = Stored.
    function logStorage(uint256 batchId, string calldata location)
        external exists(batchId) onlyHolder(batchId) notFrozen(batchId)
    {
        Batch storage b = _batches[batchId];
        if (b.status != Status.Received) revert BadStatus(b.status);
        b.status = Status.Stored;
        _trail[batchId].push(CustodyRecord(msg.sender, msg.sender, Status.Stored, uint64(block.timestamp)));
        emit BatchStored(batchId, msg.sender, location);
    }

    /// @notice Pharmacy hands the drug to a patient. Status = Dispensed (final).
    function markDispensed(uint256 batchId)
        external exists(batchId) onlyHolder(batchId) notFrozen(batchId) onlyRole(roles.PHARMACY_ROLE())
    {
        Batch storage b = _batches[batchId];
        if (b.status != Status.Received && b.status != Status.Stored) revert BadStatus(b.status);
        b.status = Status.Dispensed;
        _trail[batchId].push(CustodyRecord(msg.sender, address(0), Status.Dispensed, uint64(block.timestamp)));
        emit BatchDispensed(batchId, msg.sender);
    }

    // ------------------------------------------------- module-only forced states
    /// @notice ColdChainMonitor calls this when a reading is out of range.
    function markCompromised(uint256 batchId) external exists(batchId) {
        if (msg.sender != coldChainMonitor) revert NotAuthorized();
        _force(batchId, Status.Compromised);
    }

    /// @notice ComplianceRegistry calls this when the Regulator recalls a batch.
    function markRecalled(uint256 batchId) external exists(batchId) {
        if (msg.sender != complianceRegistry) revert NotAuthorized();
        _force(batchId, Status.Recalled);
    }

    function _force(uint256 batchId, Status s) private {
        Batch storage b = _batches[batchId];
        if (b.status == Status.Recalled) return;            // recall is the strongest flag
        if (b.status == Status.Compromised && s == Status.Compromised) return;
        b.status = s;
        b.pendingRecipient = address(0);
        _trail[batchId].push(CustodyRecord(b.currentHolder, b.currentHolder, s, uint64(block.timestamp)));
        emit StatusForced(batchId, s, msg.sender);
    }

    // -------------------------------------------------------------------- reads
    function getBatch(uint256 batchId) external view exists(batchId) returns (Batch memory) {
        return _batches[batchId];
    }
    function getCustodyTrail(uint256 batchId) external view exists(batchId) returns (CustodyRecord[] memory) {
        return _trail[batchId];
    }
    function batchCount() external view returns (uint256) { return _nextId - 1; }
}
