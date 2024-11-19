// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IHitmakrCreativeID
 * @author Hitmakr Protocol
 * @notice Interface for HitmakrCreativeID contract
 */
interface IHitmakrCreativeID {
    /// @dev Custom errors
    error UserNotVerified();
    error InvalidCountryCode();
    error InvalidRegistryCode();
    error CreativeIDTaken();
    error AlreadyHasCreativeID();
    error InvalidVerificationContract();
    error Unauthorized();

    /// @dev Structs
    struct CreativeIDInfo {
        string id;           // The actual creative ID
        uint40 timestamp;    // When it was created
        bool exists;         // If it exists
    }

    /// @dev Events
    event CreativeIDRegistered(address indexed user, string creativeId, uint40 timestamp);
    event EmergencyAction(bool paused);

    /**
     * @notice Register a new creative ID
     * @param countryCode Two-letter country code (uppercase)
     * @param registryCode Five-character alphanumeric code (uppercase)
     */
    function register(string calldata countryCode, string calldata registryCode) external;

    /**
     * @notice Emergency pause toggle
     */
    function toggleEmergencyPause() external;

    /**
     * @notice Get creative ID information for a user
     * @param user Address to query
     * @return id The creative ID
     * @return timestamp When it was created
     * @return exists If it exists
     */
    function getCreativeID(address user) external view returns (
        string memory id,
        uint40 timestamp,
        bool exists
    );

    /**
     * @notice Check if a user has a creative ID
     * @param user Address to check
     * @return bool True if user has a creative ID
     */
    function hasCreativeID(address user) external view returns (bool);

    /**
     * @notice Check if a creative ID is already taken
     * @param creativeId Creative ID to check
     * @return bool True if creative ID is taken
     */
    function isCreativeIDTaken(string calldata creativeId) external view returns (bool);

    /**
     * @notice Get total number of registered creative IDs
     * @return uint256 Total number of creative IDs
     */
    function getTotalCreativeIDs() external view returns (uint256);

    /**
     * @notice Get the verification contract address
     * @return IHitmakrVerification The verification contract interface
     */
    function verificationContract() external view returns (address);
}