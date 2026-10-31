// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IRoleManager
/// @notice Read-side view of PharmaTrace roles. Other contracts depend only on
///         this interface, so access rules live in exactly one place.
interface IRoleManager {
    /// @dev Role ids are keccak256 hashes, same as OpenZeppelin AccessControl.
    function MANUFACTURER_ROLE() external view returns (bytes32);
    function DISTRIBUTOR_ROLE() external view returns (bytes32);
    function PHARMACY_ROLE() external view returns (bytes32);
    function REGULATOR_ROLE() external view returns (bytes32);
    function ORACLE_ROLE() external view returns (bytes32);

    /// @notice True if `account` holds `role`.
    function hasRole(bytes32 role, address account) external view returns (bool);
}
