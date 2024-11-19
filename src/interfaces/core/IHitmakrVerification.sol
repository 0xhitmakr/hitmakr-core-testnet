// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IHitmakrVerification
 * @author Hitmakr Protocol
 * @notice This interface defines the functions and events for interacting with the `HitmakrVerification` contract.
 * This contract manages the verification status of user profiles, a crucial step for users who want to become
 * creatives on the Hitmakr platform. Only verified users can upload songs and receive a Creative ID.  Verification
 * status is controlled by administrators defined in the `HitmakrControlCenter` contract.
 */
interface IHitmakrVerification {
    /*
     * Custom errors for gas-efficient error handling and clear revert reasons.
     */
    error Unauthorized();
    error InvalidAddress();
    error NoProfile();
    error StatusUnchanged();
    error BatchTooLarge();
    error ZeroSuccess();


    /*
     * Events emitted by the contract. These events provide a record of verification updates and
     * emergency actions, allowing for off-chain monitoring.  The `indexed` keyword allows efficient
     * filtering of events by user address.
     */
    event VerificationUpdated(address indexed user, bool status);
    event BatchVerificationProcessed(uint256 count);
    event EmergencyAction(bool paused);

    /**
     * @notice Sets or revokes the verification status for a single user profile. Only callable by
     * administrator addresses defined in the associated `HitmakrControlCenter` contract.
     * @param account The address of the user whose verification status is being updated.
     * @param grant `true` to grant verification, `false` to revoke it.  Reverts if the verification status
     * is already set to the requested value.
     */
    function setVerification(address account, bool grant) external;


    /**
     * @notice Batch updates the verification status for multiple user profiles. This function is
     * optimized for gas efficiency.  Only callable by administrators.
     * @param accounts An array of addresses to update.
     * @param grant `true` to grant verification, `false` to revoke it. The function skips invalid
     * addresses and addresses without existing profiles.
     */
    function batchSetVerification(address[] calldata accounts, bool grant) external;


    /**
     * @notice Toggles the emergency pause state of the contract.  This function is restricted to
     * administrators and can be used to halt verification updates in case of an emergency.
     */
    function toggleEmergencyPause() external;


    /**
     * @notice Checks the verification status of a given address.
     * @param account The address to check.
     * @return `true` if the address is verified, `false` otherwise.
     */
    function isVerified(address account) external view returns (bool);

    /**
     * @notice Retrieves the address of the `HitmakrControlCenter` contract.
     * @return The address of the `HitmakrControlCenter` contract.
     */
    function HITMAKR_CONTROL_CENTER() external view returns (address);

    /**
     * @notice Retrieves the address of the `HitmakrProfiles` contract.
     * @return The address of the `HitmakrProfiles` contract.
     */
    function HITMAKR_PROFILES() external view returns (address);

    /**
     * @notice Checks if the contract is currently paused.
     * @return `true` if the contract is paused, `false` otherwise.
     */
    function paused() external view returns (bool);
}