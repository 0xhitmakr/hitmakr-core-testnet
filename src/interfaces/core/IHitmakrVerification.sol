// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IHitmakrVerification
 * @author Hitmakr Protocol
 * @notice Interface for the HitmakrVerification contract that manages verification status of Hitmakr profiles
 */
interface IHitmakrVerification {
    /// @notice Custom errors
    error Unauthorized();
    error InvalidAddress();
    error NoProfile();
    error StatusUnchanged();
    error BatchTooLarge();
    error ZeroSuccess();

    /// @notice Events
    event VerificationUpdated(address indexed user, bool status);
    event BatchVerificationProcessed(uint256 count);
    event EmergencyAction(bool paused);

    /// @notice Returns the HitmakrControlCenter contract instance
    function HITMAKR_CONTROL_CENTER() external view returns (address);

    /// @notice Returns the HitmakrProfiles contract instance
    function HITMAKR_PROFILES() external view returns (address);

    /// @notice Returns the verification status for a given address
    function verificationStatus(address) external view returns (bool);

    /**
     * @notice Sets the verification status for a single account
     * @param account The address of the account to update
     * @param grant True to verify the account, false to unverify
     */
    function setVerification(
        address account, 
        bool grant
    ) external;

    /**
     * @notice Batch sets the verification status for multiple accounts
     * @param accounts An array of addresses to update
     * @param grant True to verify the accounts, false to unverify
     */
    function batchSetVerification(
        address[] calldata accounts,
        bool grant
    ) external;

    /**
     * @notice Toggles the emergency pause state of the contract
     */
    function toggleEmergencyPause() external;
}