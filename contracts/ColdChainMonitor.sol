// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IColdChainMonitor} from "./interfaces/IColdChainMonitor.sol";
import {IBatchRegistry} from "./interfaces/IBatchRegistry.sol";
import {IRoleManager} from "./interfaces/IRoleManager.sol";

/// @title ColdChainMonitor
/// @notice Stores temperature readings per batch and flags a batch automatically
///         when a reading leaves its safe range.
/// @dev Only accounts with ORACLE_ROLE (the IoT simulator wallet) may post readings.
///      Full sensor payloads live off-chain; only a hash is stored here for integrity.
///      On a breach this contract calls BatchRegistry.markCompromised().
contract ColdChainMonitor is IColdChainMonitor {
    IRoleManager public immutable roles;
    IBatchRegistry public immutable registry;

    mapping(uint256 => TempRange) private _ranges;
    mapping(uint256 => Reading[]) private _readings;
    mapping(uint256 => bool) private _breached;

    error NotAuthorized();
    error InvalidRange();
    error RangeNotSet();
    error RangeAlreadySet();

    constructor(address roleManager, address batchRegistry) {
        roles = IRoleManager(roleManager);
        registry = IBatchRegistry(batchRegistry);
    }

    /// @notice Manufacturer of the batch sets the safe range once (tenths of a degree C).
    function setTempRange(uint256 batchId, int16 minTemp, int16 maxTemp) external {
        if (registry.getBatch(batchId).manufacturer != msg.sender) revert NotAuthorized();
        if (minTemp >= maxTemp) revert InvalidRange();
        if (_ranges[batchId].set) revert RangeAlreadySet();
        _ranges[batchId] = TempRange(minTemp, maxTemp, true);
        emit TempRangeSet(batchId, minTemp, maxTemp);
    }

    /// @notice Oracle posts one reading. Out of range => BreachDetected + batch Compromised.
    function recordReading(uint256 batchId, int16 temperature, uint64 timestamp, bytes32 payloadHash) external {
        if (!roles.hasRole(roles.ORACLE_ROLE(), msg.sender)) revert NotAuthorized();
        TempRange memory r = _ranges[batchId];
        if (!r.set) revert RangeNotSet();

        _readings[batchId].push(Reading(temperature, timestamp, payloadHash));
        emit ReadingRecorded(batchId, temperature, timestamp);

        if ((temperature < r.minTemp || temperature > r.maxTemp) && !_breached[batchId]) {
            _breached[batchId] = true;
            emit BreachDetected(batchId, temperature, timestamp);
            registry.markCompromised(batchId);
        }
    }

    function getTempRange(uint256 batchId) external view returns (TempRange memory) { return _ranges[batchId]; }
    function getReadingCount(uint256 batchId) external view returns (uint256) { return _readings[batchId].length; }
    function getReading(uint256 batchId, uint256 index) external view returns (Reading memory) { return _readings[batchId][index]; }
    function hasBreach(uint256 batchId) external view returns (bool) { return _breached[batchId]; }
}
