// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IHitmakrControlCenter
 * @author Hitmakr Protocol
 * @notice Interface for the HitmakrControlCenter contract that manages administrative and verifier roles
 */
interface IHitmakrControlCenter {
    // Custom errors
    error InvalidAddress();

    // Events
    event RoleStatusChanged(address indexed account, bytes32 indexed role, bool isGranted);
    event EmergencyAction(bool indexed paused);

    // View functions
    function ADMIN_ROLE() external pure returns (bytes32);
    function VERIFIER_ROLE() external pure returns (bytes32);

    /**
     * @notice Allows only the contract owner (DEFAULT_ADMIN_ROLE) to grant or revoke roles
     * @param account The address of the account to grant or revoke the role from
     * @param role The role to be granted or revoked (ADMIN_ROLE or VERIFIER_ROLE)
     * @param grant A boolean indicating whether to grant (true) or revoke (false) the role
     */
    function setRole(
        address account,
        bytes32 role,
        bool grant
    ) external;

    /**
     * @notice Allows only the contract owner (DEFAULT_ADMIN_ROLE) to toggle the emergency pause status
     */
    function toggleEmergencyPause() external;
}