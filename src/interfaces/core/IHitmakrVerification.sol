// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IHitmakrVerification
 * @author Hitmakr Protocol
 * @notice Interface for the HitmakrVerification contract, managing verification status of user profiles.
 * @dev This interface defines functions for checking and setting verification status, both for individual accounts and in batches. It also includes events for tracking verification updates and an emergency pause mechanism.
 */
interface IHitmakrVerification {
    /// @notice Event emitted when a user's verification status is updated
    event VerificationUpdated(address indexed user, bool status);
    /// @notice Event emitted when a batch verification update is completed
    event BatchVerificationProcessed(uint256 count);
    /// @notice Event emitted when the emergency pause state is toggled
    event EmergencyAction(bool paused);

    /// @notice Error for unauthorized access
    error Unauthorized();
    /// @notice Error for invalid address parameters
    error InvalidAddress();
    /// @notice Error for attempting to verify a user without a profile
    error NoProfile();
    /// @notice Error for attempting to set a verification status that is already the current status
    error StatusUnchanged();
    /// @notice Error for exceeding the maximum batch size in batch operations
    error BatchTooLarge();
    /// @notice Error when a batch operation processes zero accounts successfully.
    error ZeroSuccess();

    /**
     * @notice Checks the verification status of a given account.
     * @param account The address of the account to check.
     * @return True if the account is verified, false otherwise.
     */
    function verificationStatus(address account) external view returns (bool);

    /**
     * @notice Retrieves the address of the HitmakrControlCenter contract.
     * @return The address of the HitmakrControlCenter contract.
     */
    function HITMAKR_CONTROL_CENTER() external view returns (address);

    /**
     * @notice Retrieves the address of the HitmakrProfiles contract.
     * @return The address of the HitmakrProfiles contract.
     */
    function HITMAKR_PROFILES() external view returns (address);

    /**
     * @notice Sets the verification status for a single account.
     * @param account The address of the account.
     * @param grant True to verify, false to unverify.
     * @dev Only callable by authorized admins.
     */
    function setVerification(address account, bool grant) external;

    /**
     * @notice Batch sets the verification status for multiple accounts.
     * @param accounts An array of addresses to update.
     * @param grant True to verify, false to unverify.
     * @dev Only callable by authorized admins.
     */
    function batchSetVerification(address[] calldata accounts, bool grant) external;

    /**
     * @notice Toggles the emergency pause state of the contract.
     * @dev Only callable by authorized admins.
     */
    function toggleEmergencyPause() external;
}