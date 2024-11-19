// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import "../interfaces/accesscontrol/IHitmakrControlCenter.sol";
import "../interfaces/core/IHitmakrProfiles.sol";

/**
 * @title HitmakrVerification
 * @author Hitmakr Protocol
 * @notice This contract manages the verification status of Hitmakr profiles. Verification is a crucial step
 * for users who wish to become creatives on the platform, enabling them to upload songs and obtain a unique
 * Creative ID.  Only verified users can upload content and participate as creatives within the Hitmakr ecosystem.
 * This contract is controlled by administrators designated in the `HitmakrControlCenter`. It is designed for gas
 * efficiency and incorporates security measures like reentrancy protection and an emergency pause mechanism.
 */
contract HitmakrVerification is ReentrancyGuard, Pausable {
    /*
     * Custom errors for gas-efficient error handling.
     */
    error Unauthorized();
    error InvalidAddress();
    error NoProfile();
    error StatusUnchanged();
    error BatchTooLarge();
    error ZeroSuccess();

    /*
     * Constant defining the maximum batch size for verification updates. This helps prevent
     * excessively large transactions that could consume too much gas.
     */
    uint256 private constant MAX_BATCH_SIZE = 100;

    /*
     * Immutable references to the `HitmakrControlCenter` and `HitmakrProfiles` contracts. These
     * references are set during contract construction and cannot be changed afterwards.
     */
    IHitmakrControlCenter public immutable HITMAKR_CONTROL_CENTER;
    IHitmakrProfiles public immutable HITMAKR_PROFILES;

    /*
     * Mapping to store the verification status of each address.  `true` indicates a verified profile,
     * `false` indicates an unverified or revoked verification.
     */
    mapping(address => bool) private _verificationStatus;


    /*
     * Events emitted by the contract.  These events provide a record of verification updates and emergency
     * actions, enabling off-chain monitoring and analysis.
     */
    event VerificationUpdated(address indexed user, bool status);
    event BatchVerificationProcessed(uint256 count);
    event EmergencyAction(bool paused);


    /*
     * Modifier to restrict access to only addresses with the admin role in the `HitmakrControlCenter`.
     */
    modifier onlyAdmin() {
        if (!HITMAKR_CONTROL_CENTER.isAdmin(msg.sender)) revert Unauthorized();
        _;
    }

    /**
     * @notice Constructor initializes the contract with the addresses of the `HitmakrControlCenter` and
     * `HitmakrProfiles` contracts.
     * @param controlCenterAddress The address of the `HitmakrControlCenter` contract.
     * @param profilesAddress The address of the `HitmakrProfiles` contract.
     */
    constructor(address controlCenterAddress, address profilesAddress) {
        if (controlCenterAddress == address(0) || profilesAddress == address(0)) revert InvalidAddress();
        
        HITMAKR_CONTROL_CENTER = IHitmakrControlCenter(controlCenterAddress);
        HITMAKR_PROFILES = IHitmakrProfiles(profilesAddress);
    }

    /**
     * @notice Sets or revokes the verification status for a single profile.  Only callable by admins.
     * @param account The address of the profile to update.
     * @param grant `true` to grant verification, `false` to revoke it.  Reverts if the verification status
     * is already set to the requested value.
     */
    function setVerification(address account, bool grant)
        external
        onlyAdmin
        whenNotPaused
        nonReentrant
    {
        if (account == address(0)) revert InvalidAddress();
        if (!HITMAKR_PROFILES.hasProfile(account)) revert NoProfile();
        if (_verificationStatus[account] == grant) revert StatusUnchanged();

        _verificationStatus[account] = grant;
        emit VerificationUpdated(account, grant);
    }

    /**
     * @notice Batch updates the verification status for multiple profiles.  This function is optimized for
     * gas efficiency. Only callable by admins.
     * @param accounts An array of addresses to update.  The maximum batch size is defined by `MAX_BATCH_SIZE`.
     * @param grant `true` to grant verification, `false` to revoke it.  Skips invalid addresses and addresses
     * without profiles.
     */
    function batchSetVerification(address[] calldata accounts, bool grant)
        external
        onlyAdmin
        whenNotPaused
        nonReentrant
    {
        uint256 len = accounts.length;
        if (len == 0 || len > MAX_BATCH_SIZE) revert BatchTooLarge();

        uint256 successCount;
        address account;

        for (uint256 i; i < len;) {
            account = accounts[i];
            
            if (account == address(0) || !HITMAKR_PROFILES.hasProfile(account)) {
                unchecked { ++i; } // Safe unchecked increment
                continue;
            }

            bool currentStatus = _verificationStatus[account];

            if (grant != currentStatus) {
                _verificationStatus[account] = grant;
                emit VerificationUpdated(account, grant);
                unchecked { ++successCount; } // Safe unchecked increment
            }

            unchecked { ++i; } // Safe unchecked increment
        }

        if (successCount == 0) revert ZeroSuccess();
        emit BatchVerificationProcessed(successCount);
    }


    /**
     * @notice Enables or disables the emergency pause state. Only callable by admins.  When paused,
     * functions that modify verification status will be disabled.
     */
    function toggleEmergencyPause() external onlyAdmin nonReentrant {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
        emit EmergencyAction(paused());
    }

    /**
     * @notice Checks the verification status of a given address.
     * @param account The address to check.
     * @return `true` if the address is verified, `false` otherwise.
     */
    function isVerified(address account) external view returns (bool) {
        return _verificationStatus[account];
    }
}