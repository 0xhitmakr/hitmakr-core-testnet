// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IHitmakrControlCenter
 * @author Hitmakr Protocol
 * @notice Interface for the HitmakrControlCenter contract, which manages roles and emergency pausing.
 * @dev This interface defines functions for setting admins, managing verifiers in batches, and toggling the emergency pause state of the system.
 */
interface IHitmakrControlCenter {
    /// @notice Error for invalid address parameters
    error InvalidAddress();
    /// @notice Error for invalid batch parameters (e.g., empty array or exceeding max size)
    error InvalidBatch();
    /// @notice Error for zero successful operations in batch processing
    error ZeroSuccess();

    /**
     * @notice Structure to hold role counts.
     * @param verifierCount The number of verifier accounts.
     * @param adminCount The number of admin accounts.
     */
    struct RoleCounter {
        uint248 verifierCount;
        uint8 adminCount;
    }

    /// @notice Event emitted after a batch of verifiers is processed
    event BatchVerifierProcessed(uint256 count);
    /// @notice Event emitted when the emergency pause state is toggled
    event EmergencyAction(bool paused);

    /**
     * @notice Sets the admin status of an account.
     * @param account The address of the account.
     * @param grant True to grant admin status, false to revoke.
     */
    function setAdmin(address account, bool grant) external;
    
    /**
     * @notice Batch sets the verifier status of multiple accounts.
     * @param accounts An array of addresses to modify.
     * @param grant True to grant verifier status, false to revoke.
     */
    function batchSetVerifiers(address[] calldata accounts, bool grant) external;
    
    /**
     * @notice Toggles the emergency pause state of the contract.
     */
    function toggleEmergencyPause() external;
    
    /**
     * @notice Retrieves the current role counts.
     * @return A `RoleCounter` struct containing the number of admins and verifiers.
     */
    function roleCounter() external view returns (RoleCounter memory);

    /**
     * @notice Returns the bytes32 representation of the ADMIN_ROLE.
     * @return The ADMIN_ROLE hash.
     */
    function ADMIN_ROLE() external view returns (bytes32);
    
    /**
     * @notice Returns the bytes32 representation of the VERIFIER_ROLE.
     * @return The VERIFIER_ROLE hash.
     */
    function VERIFIER_ROLE() external view returns (bytes32);
    
    /**
     * @notice Returns the current paused state of the contract.
     * @return True if the contract is paused, false otherwise.
     */
    function paused() external view returns (bool);
}