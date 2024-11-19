// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import "../interfaces/core/IHitmakrVerification.sol";
import "../interfaces/accesscontrol/IHitmakrControlCenter.sol";

/**
 * @title HitmakrCreativeID
 * @author Hitmakr Protocol
 * @notice This contract manages unique Creative IDs for verified Hitmakr users.  These IDs are essential for
 * associating creatives with their uploaded content, specifically for generating Decentralized Standard
 * Recording Codes (DSRCs).  Only verified users can register a Creative ID, which consists of a two-letter
 * country code and a five-character alphanumeric registry code. This contract enforces strict validation
 * rules and implements security measures like reentrancy protection and an emergency pause mechanism.
 */
contract HitmakrCreativeID is ReentrancyGuard, Pausable {
    /*
     * Custom errors for gas-efficient error handling and detailed revert reasons.
     */
    error UserNotVerified();
    error InvalidCountryCode();
    error InvalidRegistryCode();
    error CreativeIDTaken();
    error AlreadyHasCreativeID();
    error InvalidVerificationContract();
    error Unauthorized();

    /*
     * Immutable reference to the HitmakrVerification contract.  This is used to verify the user's
     * verification status before allowing them to register a Creative ID.
     */
    IHitmakrVerification public immutable verificationContract;
    
    /*
     * Struct to store information about a Creative ID. Packing these variables into a struct can
     * improve gas efficiency.
     */
    struct CreativeIDInfo {
        string id;           // The Creative ID string (countryCode + registryCode).
        uint40 timestamp;    // Timestamp of Creative ID registration.
        bool exists;         // Boolean indicating if the Creative ID exists for a user.
    }
    
    /*
     * Mapping to store Creative ID information for each user address.
     * Mapping to track whether a specific Creative ID is already taken.
     * Counter for the total number of Creative IDs registered.
     */
    mapping(address => CreativeIDInfo) private _creativeIDRegistry;
    mapping(string => bool) private _takenCreativeIDs;
    uint256 private _totalCreativeIDs;

    /*
     * Events emitted by the contract. These events provide a record of Creative ID registrations
     * and emergency actions. The indexed keyword on the user parameter in `CreativeIDRegistered`
     * enables efficient filtering of events by user address.
     */
    event CreativeIDRegistered(address indexed user, string creativeId, uint40 timestamp);
    event EmergencyAction(bool paused);

    /*
     * Modifier to restrict access to only administrator addresses as defined in the
     * HitmakrControlCenter contract.  This ensures only authorized users can toggle the
     * emergency pause state.
     */
    modifier onlyAdmin() {
        address controlCenter = verificationContract.HITMAKR_CONTROL_CENTER();
        IHitmakrControlCenter cc = IHitmakrControlCenter(controlCenter);
        if (!cc.isAdmin(msg.sender)) revert Unauthorized();
        _;
    }

    /**
     * @notice Constructor initializes the contract with the address of the HitmakrVerification contract.
     * @param _verificationContract The address of the HitmakrVerification contract.
     */
    constructor(address _verificationContract) {
        if (_verificationContract == address(0)) revert InvalidVerificationContract();
        verificationContract = IHitmakrVerification(_verificationContract);
    }

    /**
     * @notice Registers a new Creative ID for the calling user. Reverts if the user is not verified,
     * the country code or registry code is invalid, or the Creative ID is already taken.  Emits a
     * CreativeIDRegistered event upon successful registration.
     * @param countryCode A two-letter country code (e.g., "US", "UK"). Must be uppercase.
     * @param registryCode A five-character alphanumeric registry code (e.g., "123AB").  Must be uppercase.
     */
    function register(string calldata countryCode, string calldata registryCode)
        external
        whenNotPaused
        nonReentrant
    {
        if (!verificationContract.isVerified(msg.sender)) revert UserNotVerified();
        if (_creativeIDRegistry[msg.sender].exists) revert AlreadyHasCreativeID();
        
        if (!_isValidCountryCode(countryCode)) revert InvalidCountryCode();
        if (!_isValidRegistryCode(registryCode)) revert InvalidRegistryCode();

        string memory fullCreativeId = string.concat(countryCode, registryCode);
        if (_takenCreativeIDs[fullCreativeId]) revert CreativeIDTaken();

        uint40 timestamp = uint40(block.timestamp);
        _creativeIDRegistry[msg.sender] = CreativeIDInfo({
            id: fullCreativeId,
            timestamp: timestamp,
            exists: true
        });
        _takenCreativeIDs[fullCreativeId] = true;
        
        unchecked {  // Safe because totalCreativeIDs is unlikely to overflow.
            ++_totalCreativeIDs;
        }

        emit CreativeIDRegistered(msg.sender, fullCreativeId, timestamp);
    }

    /**
     * @notice Toggles the emergency pause state of the contract. This function is only callable by
     * administrators and is used to halt Creative ID registrations during emergencies.  Emits an
     * EmergencyAction event.
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
     * @notice Retrieves information about a user's Creative ID.
     * @param user The address of the user to query.
     * @return id The Creative ID string. Returns an empty string if the user does not have a Creative ID.
     * @return timestamp The timestamp of Creative ID registration. Returns 0 if the user does not have a 
     * Creative ID.
     * @return exists A boolean indicating whether the user has a registered Creative ID.
     */
    function getCreativeID(address user) external view returns (
        string memory id,
        uint40 timestamp,
        bool exists
    ) {
        CreativeIDInfo memory info = _creativeIDRegistry[user];
        return (info.id, info.timestamp, info.exists);
    }

    /**
     * @notice Checks if a user has a registered Creative ID.
     * @param user The address to check.
     * @return `true` if the user has a registered Creative ID, `false` otherwise.
     */
    function hasCreativeID(address user) external view returns (bool) {
        return _creativeIDRegistry[user].exists;
    }

    /**
     * @notice Checks if a given Creative ID is already taken.
     * @param creativeId The Creative ID to check.
     * @return `true` if the Creative ID is already registered, `false` otherwise.
     */
    function isCreativeIDTaken(string calldata creativeId) external view returns (bool) {
        return _takenCreativeIDs[creativeId];
    }

    /**
     * @notice Returns the total number of registered Creative IDs.
     * @return The total number of registered Creative IDs.
     */
    function getTotalCreativeIDs() external view returns (uint256) {
        return _totalCreativeIDs;
    }


    /*
     * Internal helper functions to validate the format of country and registry codes. These functions
     * help ensure data integrity and prevent invalid Creative IDs from being registered.
     */
    function _isValidCountryCode(string memory countryCode) private pure returns (bool) {
        bytes memory country = bytes(countryCode);
        if (country.length != 2) return false;
        
        for (uint256 i = 0; i < 2;) {
            if (country[i] < 0x41 || country[i] > 0x5A) return false;
            unchecked { ++i; }
        }
        
        return true;
    }

    function _isValidRegistryCode(string memory registryCode) private pure returns (bool) {
        bytes memory registry = bytes(registryCode);
        if (registry.length != 5) return false;
        
        for (uint256 i = 0; i < 5;) {
            bytes1 char = registry[i];
            bool isValid = (char >= 0x30 && char <= 0x39) || // 0-9
                         (char >= 0x41 && char <= 0x5A);     // A-Z
            if (!isValid) return false;
            unchecked { ++i; }
        }
        
        return true;
    }
}