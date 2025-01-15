// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IHitmakrCreativeID
 * @author Hitmakr Protocol
 * @notice Interface for the HitmakrCreativeID contract that manages unique Creative IDs for verified users
 */
interface IHitmakrCreativeID {
    /// @notice Custom errors
    error UserNotVerified();
    error InvalidCountryCode();
    error InvalidRegistryCode();
    error CreativeIDTaken();
    error AlreadyHasCreativeID();
    error ZeroAddress();
    error Unauthorized();

    /**
     * @notice Structure to store information about a Creative ID
     * @member id The actual Creative ID string
     * @member timestamp The timestamp when the Creative ID was registered
     * @member exists A boolean indicating whether the Creative ID exists
     */
    struct CreativeIDInfo {
        string id;
        uint40 timestamp;
        bool exists;
    }

    /// @notice Event emitted when a Creative ID is registered
    event CreativeIDRegistered(address indexed user, string creativeId, uint40 timestamp);
    /// @notice Event emitted when the contract's pause state changes
    event EmergencyAction(bool paused);

    /// @notice Returns the verification contract instance
    function verificationContract() external view returns (address);
    
    /// @notice Returns the Creative ID information for a given address
    function creativeIDRegistry(address) external view returns (CreativeIDInfo memory);
    
    /// @notice Returns whether a Creative ID is taken
    function takenCreativeIDs(string memory) external view returns (bool);
    
    /// @notice Returns the total number of registered Creative IDs
    function totalCreativeIDs() external view returns (uint256);

    /**
     * @notice Allows a verified user to register a new Creative ID
     * @param countryCode The two-letter country code (uppercase)
     * @param registryCode The five-character alphanumeric registry code (uppercase)
     */
    function register(
        string calldata countryCode, 
        string calldata registryCode
    ) external;

    /**
     * @notice Toggles the emergency pause state of the contract
     */
    function toggleEmergencyPause() external;

    /**
    * @notice Gets the Creative ID information for a given user
    * @param user The address to check
    * @return id The Creative ID string
    * @return timestamp The registration timestamp
    * @return exists Whether the Creative ID exists
    */
    function getCreativeID(address user) external view returns (
        string memory id,
        uint40 timestamp,
        bool exists
    );
}