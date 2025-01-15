// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/accesscontrol/IControlCenter.sol";
import "../interfaces/core/IHitmakrProfiles.sol";

/**
 * @title HitmakrVerification
 * @author Hitmakr Protocol
 * @notice Manages the verification status of Hitmakr profiles.
 * @dev This contract allows admins to verify or unverify user profiles. It integrates with `HitmakrControlCenter` for access control and `HitmakrProfiles` to check for profile existence.  It also includes an emergency pause mechanism.
 */
contract HitmakrVerification is ReentrancyGuard, Pausable {
    /// @notice Custom errors for gas optimization
    error Unauthorized();
    error InvalidAddress();
    error NoProfile();
    error StatusUnchanged();
    error BatchTooLarge();
    error ZeroSuccess();

    /// @notice Maximum number of accounts that can be processed in a batch
    uint256 private constant MAX_BATCH_SIZE = 100;

    /// @notice Interface for the HitmakrControlCenter contract
    IHitmakrControlCenter public immutable HITMAKR_CONTROL_CENTER;
    /// @notice Interface for the HitmakrProfiles contract
    IHitmakrProfiles public immutable HITMAKR_PROFILES;

    /// @notice Mapping of addresses to their verification status
    mapping(address => bool) public verificationStatus;

    /// @notice Event emitted when a user's verification status is updated
    event VerificationUpdated(address indexed user, bool status);
    /// @notice Event emitted when a batch verification process is completed
    event BatchVerificationProcessed(uint256 count);
    /// @notice Event emitted when the contract's pause state is changed
    event EmergencyAction(bool paused);

    /// @notice Modifier to restrict access to only admin roles from HitmakrControlCenter
    modifier onlyAdmin() {
        bytes32 adminRole = HITMAKR_CONTROL_CENTER.ADMIN_ROLE();
        if (!AccessControl(address(HITMAKR_CONTROL_CENTER)).hasRole(adminRole, msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Constructor initializes the contract with the addresses of HitmakrControlCenter and HitmakrProfiles.
     * @param controlCenterAddress The address of the HitmakrControlCenter contract.
     * @param profilesAddress The address of the HitmakrProfiles contract.
     * @dev Reverts if either address is zero.
     */
    constructor(address controlCenterAddress, address profilesAddress) {
        if (controlCenterAddress == address(0) || profilesAddress == address(0)) revert InvalidAddress();
        
        HITMAKR_CONTROL_CENTER = IHitmakrControlCenter(controlCenterAddress);
        HITMAKR_PROFILES = IHitmakrProfiles(profilesAddress);
    }

    /**
     * @notice Sets the verification status for a single account.
     * @param account The address of the account to update.
     * @param grant True to verify the account, false to unverify.
     * @dev Only callable by admin. Reverts if the account address is invalid, 
     * the user has no profile, or the verification status is already set to the requested value.
     */
    function setVerification(
        address account, 
        bool grant
    ) 
        external 
        onlyAdmin
        whenNotPaused 
        nonReentrant 
    {
        if (account == address(0)) revert InvalidAddress();
        if (!HITMAKR_PROFILES._hasProfile(account)) revert NoProfile();
        if (verificationStatus[account] == grant) revert StatusUnchanged();

        verificationStatus[account] = grant;
        emit VerificationUpdated(account, grant);
    }

    /**
     * @notice Batch sets the verification status for multiple accounts.
     * @param accounts An array of addresses to update.
     * @param grant True to verify the accounts, false to unverify.
     * @dev Only callable by admins. Reverts if the batch size is invalid or if no accounts were successfully processed.
     */
    function batchSetVerification(
        address[] calldata accounts,
        bool grant
    ) 
        external 
        onlyAdmin 
        whenNotPaused 
        nonReentrant 
    {
        uint256 len = accounts.length;
        if (len == 0 || len > MAX_BATCH_SIZE) revert BatchTooLarge();

        uint256 successCount;
        
        for (uint256 i; i < len;) {
            address account = accounts[i];
            
            if (account == address(0) || !HITMAKR_PROFILES._hasProfile(account)) {
                unchecked { ++i; }
                continue;
            }

            bool currentStatus = verificationStatus[account];
            if (grant != currentStatus) {
                verificationStatus[account] = grant;
                emit VerificationUpdated(account, grant);
                unchecked { ++successCount; }
            }

            unchecked { ++i; }
        }

        if (successCount == 0) revert ZeroSuccess();
        emit BatchVerificationProcessed(successCount);
    }

    /**
     * @notice Toggles the emergency pause state of the contract.
     * @dev Only callable by admins. Emits an `EmergencyAction` event with the new paused state.
     */
    function toggleEmergencyPause() external onlyAdmin nonReentrant {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
        emit EmergencyAction(paused());
    }
}