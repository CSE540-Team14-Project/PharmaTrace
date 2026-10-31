// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IColdChainMonitor
/// @notice Temperature readings and automatic breach detection.
interface IColdChainMonitor {
    /// @dev Temperatures are int16 in tenths of a degree Celsius (45 = 4.5 C) to avoid floats.
    struct TempRange { int16 minTemp; int16 maxTemp; bool set; }
    struct Reading   { int16 temperature; uint64 timestamp; bytes32 payloadHash; }

    event TempRangeSet(uint256 indexed batchId, int16 minTemp, int16 maxTemp);
    event ReadingRecorded(uint256 indexed batchId, int16 temperature, uint64 timestamp);
    event BreachDetected(uint256 indexed batchId, int16 temperature, uint64 timestamp);

    /// @notice Manufacturer sets the safe range once per batch (e.g. 20..80 for 2-8 C).
    function setTempRange(uint256 batchId, int16 minTemp, int16 maxTemp) external;

    /// @notice Oracle (IoT simulator) posts a reading. Out-of-range => batch marked Compromised.
    function recordReading(uint256 batchId, int16 temperature, uint64 timestamp, bytes32 payloadHash) external;

    function getTempRange(uint256 batchId) external view returns (TempRange memory);
    function getReadingCount(uint256 batchId) external view returns (uint256);
    function getReading(uint256 batchId, uint256 index) external view returns (Reading memory);
    function hasBreach(uint256 batchId) external view returns (bool);
}
