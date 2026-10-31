// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title RoleManager
/// @notice Single source of truth for who may do what in PharmaTrace.
/// @dev Built on OpenZeppelin AccessControl. The Regulator is the admin of every
///      role, so only the Regulator can grant or revoke Manufacturer, Distributor,
///      Pharmacy and Oracle accounts. Other contracts call hasRole() on this contract.
contract RoleManager is AccessControl {
    bytes32 public constant MANUFACTURER_ROLE = keccak256("MANUFACTURER_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE  = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant PHARMACY_ROLE     = keccak256("PHARMACY_ROLE");
    bytes32 public constant REGULATOR_ROLE    = keccak256("REGULATOR_ROLE");
    bytes32 public constant ORACLE_ROLE       = keccak256("ORACLE_ROLE");

    error ZeroAddress();

    /// @param regulator first Regulator account (also the AccessControl default admin).
    constructor(address regulator) {
        if (regulator == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, regulator);
        _grantRole(REGULATOR_ROLE, regulator);
        // Regulator administers all business roles (not just the default admin).
        _setRoleAdmin(MANUFACTURER_ROLE, REGULATOR_ROLE);
        _setRoleAdmin(DISTRIBUTOR_ROLE,  REGULATOR_ROLE);
        _setRoleAdmin(PHARMACY_ROLE,     REGULATOR_ROLE);
        _setRoleAdmin(ORACLE_ROLE,       REGULATOR_ROLE);
        _setRoleAdmin(REGULATOR_ROLE,    REGULATOR_ROLE);
    }

    /// @notice Convenience for the frontend: which business role (if any) does this wallet have?
    /// @return role one of the *_ROLE ids, or bytes32(0) if none.
    function roleOf(address account) external view returns (bytes32 role) {
        if (hasRole(REGULATOR_ROLE, account))    return REGULATOR_ROLE;
        if (hasRole(MANUFACTURER_ROLE, account)) return MANUFACTURER_ROLE;
        if (hasRole(DISTRIBUTOR_ROLE, account))  return DISTRIBUTOR_ROLE;
        if (hasRole(PHARMACY_ROLE, account))     return PHARMACY_ROLE;
        if (hasRole(ORACLE_ROLE, account))       return ORACLE_ROLE;
        return bytes32(0);
    }
}
