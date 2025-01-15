// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/core/IHitmakrVerification.sol";
import "../interfaces/accesscontrol/IControlCenter.sol";

/**
 * @title HitmakrCreativeID
 * @author Hitmakr Protocol
 * @notice Manages unique Creative IDs for verified Hitmakr users.
 * @dev This contract allows verified users to register a unique Creative ID based on their country and a registry code. It integrates with `HitmakrVerification` for user verification and `HitmakrControlCenter` for admin access control. The contract implements an emergency pause mechanism for added security.
 */
contract HitmakrCreativeID is ReentrancyGuard, Pausable {
    /// @notice Custom errors for gas optimization
    error UserNotVerified();
    error InvalidCountryCode();
    error InvalidRegistryCode();
    error CreativeIDTaken();
    error AlreadyHasCreativeID();
    error ZeroAddress();
    error Unauthorized();

    /// @notice The HitmakrVerification contract used for checking user verification status
    IHitmakrVerification public immutable verificationContract;
    
    /**
     * @notice Structure to store information about a Creative ID.
     * @member id The actual Creative ID string.
     * @member timestamp The timestamp when the Creative ID was registered.
     * @member exists A boolean indicating whether the Creative ID exists.
     */
    struct CreativeIDInfo {
        string id;
        uint40 timestamp;
        bool exists;
    }
    
    /// @notice Mapping from user address to their Creative ID information
    mapping(address => CreativeIDInfo) public creativeIDRegistry;
    /// @notice Mapping to check if a Creative ID is already taken
    mapping(string => bool) public takenCreativeIDs;
    /// @notice Total number of registered Creative IDs
    uint256 public totalCreativeIDs;

    /// @notice Event emitted when a Creative ID is registered
    event CreativeIDRegistered(address indexed user, string creativeId, uint40 timestamp);
    /// @notice Event emitted when the contract's pause state changes
    event EmergencyAction(bool paused);

    /// @notice Modifier that restricts access to only admin users defined in HitmakrControlCenter
    modifier onlyAdmin() {
        IHitmakrControlCenter controlCenter = IHitmakrControlCenter(verificationContract.HITMAKR_CONTROL_CENTER());
        if (!AccessControl(address(controlCenter)).hasRole(controlCenter.ADMIN_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Constructor initializes the contract with the address of the HitmakrVerification contract.
     * @param _verificationContract The address of the HitmakrVerification contract.
     */
    constructor(address _verificationContract) {
        if (_verificationContract == address(0)) revert ZeroAddress();
        verificationContract = IHitmakrVerification(_verificationContract);
    }

    /**
     * @notice Allows a verified user to register a new Creative ID.
     * @param countryCode The two-letter country code (uppercase).
     * @param registryCode The five-character alphanumeric registry code (uppercase).
     * @dev Reverts if the user is not verified, the country code or registry code is invalid, or the Creative ID is already taken. Emits a `CreativeIDRegistered` event upon successful registration.
     */
    function register(
        string calldata countryCode, 
        string calldata registryCode
    ) 
        external
        whenNotPaused
        nonReentrant 
    {
        if (!verificationContract.verificationStatus(msg.sender)) revert UserNotVerified();
        if (creativeIDRegistry[msg.sender].exists) revert AlreadyHasCreativeID();
        
        if (!_isValidCountryCode(countryCode)) revert InvalidCountryCode();
        if (!_isValidRegistryCode(registryCode)) revert InvalidRegistryCode();

        string memory fullCreativeId = string.concat(countryCode, registryCode);
        if (takenCreativeIDs[fullCreativeId]) revert CreativeIDTaken();

        uint40 timestamp = uint40(block.timestamp);
        creativeIDRegistry[msg.sender] = CreativeIDInfo({
            id: fullCreativeId,
            timestamp: timestamp,
            exists: true
        });
        takenCreativeIDs[fullCreativeId] = true;
        
        unchecked {
            ++totalCreativeIDs;
        }

        emit CreativeIDRegistered(msg.sender, fullCreativeId, timestamp);
    }

    /**
     * @notice Toggles the emergency pause state of the contract.
     * @dev Only callable by admin users. Emits an `EmergencyAction` event.
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
     * @dev Internal function to validate the country code.
     * @param countryCode The country code to validate.
     * @return True if the country code is valid, false otherwise.
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

    /**
     * @dev Internal function to validate the registry code.
     * @param registryCode The registry code to validate.
     * @return True if the registry code is valid, false otherwise.
     */
    function _isValidRegistryCode(string memory registryCode) private pure returns (bool) {
        bytes memory registry = bytes(registryCode);
        if (registry.length != 5) return false;
        
        for (uint256 i = 0; i < 5;) {
            bytes1 char = registry[i];
            bool isValid = (char >= 0x30 && char <= 0x39) || 
                         (char >= 0x41 && char <= 0x5A);    
            if (!isValid) return false;
            unchecked { ++i; }
        }
        
        return true;
    }

    function getCreativeID(address user) external view returns (
        string memory id,
        uint40 timestamp,
        bool exists
    ) {
        CreativeIDInfo memory info = creativeIDRegistry[user];
        return (info.id, info.timestamp, info.exists);
    }
}