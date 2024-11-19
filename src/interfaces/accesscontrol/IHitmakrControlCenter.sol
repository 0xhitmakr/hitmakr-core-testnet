// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IHitmakrControlCenter
 * @author Hitmakr Protocol
 * @notice This interface defines the functions for interacting with the `HitmakrControlCenter` contract.
 * The control center manages the roles of administrators and verifiers within the Hitmakr ecosystem.  It provides
 * functions for assigning and revoking these roles, as well as an emergency pause mechanism.
 */
interface IHitmakrControlCenter {
    /*
     * Custom errors for gas-efficient error handling.  These errors provide specific information about the
     * reason for a revert, which can be helpful for debugging and user feedback.
     */
    error Unauthorized();
    error InvalidAddress();
    error InvalidBatch();
    error AlreadyAdmin();
    error NotAdmin();
    error AlreadyVerifier();
    error NotVerifier();
    error ZeroSuccess();

    /*
     * Events emitted by the control center.  These events provide a record of changes to admin and verifier
     * roles, as well as emergency pause actions.  Indexed parameters allow for efficient filtering of events.
     */
    event AdminUpdated(address indexed account, bool status);
    event VerifierUpdated(address indexed account, bool status);
    event BatchVerifierProcessed(uint256 count);
    event EmergencyAction(bool paused);

    /**
     * @notice Sets or revokes the admin role for a single account.  This function can only be called by the
     * owner of the `HitmakrControlCenter` contract.
     * @param account The address of the account to modify.
     * @param grant `true` to grant admin privileges, `false` to revoke them.
     */
    function setAdmin(address account, bool grant) external;

    /**
     * @notice Sets or revokes the verifier role for a batch of accounts. This function is optimized for gas
     * efficiency and can only be called by the owner of the `HitmakrControlCenter` contract.
     * @param accounts An array of addresses to modify.
     * @param grant `true` to grant verifier privileges, `false` to revoke them.
     */
    function batchSetVerifiers(address[] calldata accounts, bool grant) external;

    /**
     * @notice Toggles the emergency pause state of the Hitmakr platform.  This function can only be called
     * by the owner of the `HitmakrControlCenter` contract.  When paused, certain critical functions may be
     * disabled to prevent further damage or exploits in case of an emergency.
     */
    function toggleEmergencyPause() external;

    /**
     * @notice Checks whether a given address has the admin role.
     * @param account The address to check.
     * @return `true` if the address has the admin role, `false` otherwise.
     */
    function isAdmin(address account) external view returns (bool);

    /**
     * @notice Checks whether a given address has the verifier role.
     * @param account The address to check.
     * @return `true` if the address has the verifier role, `false` otherwise.
     */
    function isVerifier(address account) external view returns (bool);

    /**
     * @notice Retrieves the current counts of admins and verifiers.
     * @return adminCount The number of addresses with the admin role.
     * @return verifierCount The number of addresses with the verifier role.
     */
    function getRoleCounts() external view returns (uint256 adminCount, uint256 verifierCount);
}