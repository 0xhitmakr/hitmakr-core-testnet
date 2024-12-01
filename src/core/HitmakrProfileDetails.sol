// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/core/IHitmakrProfiles.sol";

/**
 * @title HitmakrProfileDetails
 * @author Hitmakr Protocol
 * @notice Contract for managing additional profile details for Hitmakr users.
 * @dev This contract stores and manages extended profile information for users who have registered a profile using the `HitmakrProfiles` contract.
 * It allows users to set and update their full name, profile image URI, bio, date of birth, and country.
 * Data validation ensures data integrity and reasonable limits on field lengths.
 */
contract HitmakrProfileDetails {
    /// @notice Error for when a user tries to interact with details without having a profile
    error NoProfile();
    /// @notice Error for when a provided string exceeds the maximum allowed length
    error InvalidLength();
    /// @notice Error for when an invalid timestamp (e.g., future date) is provided
    error InvalidTimestamp();
    /// @notice Error for when a user attempts to update details without having initialized them
    error UnauthorizedUpdate();
    /// @notice Error for when a required field is left empty
    error EmptyField();
    /// @notice Error for when the provided date of birth results in an age below the minimum allowed
    error InvalidAge();
    /// @notice Error for when a zero address is provided where it shouldn't be
    error ZeroAddress();

    /// @notice Maximum length for the full name field
    uint256 private constant FULLNAME_MAX_LENGTH = 100;
    /// @notice Maximum length for the bio field
    uint256 private constant BIO_MAX_LENGTH = 500;
    /// @notice Maximum length for the image URI field
    uint256 private constant IMAGE_URI_MAX_LENGTH = 200;
    /// @notice Maximum length for the country field
    uint256 private constant COUNTRY_MAX_LENGTH = 56;
    /// @notice Minimum allowed age in years
    uint256 private constant MINIMUM_AGE = 6;
    /// @notice Number of seconds in a year, used for age calculations
    uint256 private constant YEAR_IN_SECONDS = 365 days;
    
    /// @notice The instance of the HitmakrProfiles contract
    IHitmakrProfiles public immutable profilesContract;

    /**
     * @notice Structure holding additional profile details for a user.
     * @param fullName The user's full name
     * @param imageURI URI pointing to the user's profile image
     * @param bio A short biography or description
     * @param dateOfBirth The user's date of birth as a Unix timestamp
     * @param country The user's country
     * @param lastUpdated The timestamp of the last profile details update
     * @param initialized Flag indicating if the profile details have been initialized
     */
    struct ProfileDetails {
        string fullName;
        string imageURI;
        string bio;
        uint64 dateOfBirth;
        string country;
        uint64 lastUpdated;
        bool initialized;
    }

    /// @notice Mapping of user addresses to their profile details
    mapping(address => ProfileDetails) public profileDetails;
    /// @notice The total number of profiles with initialized details
    uint256 public detailsCount;

    /**
     * @notice Event emitted when a user's profile details are created
     * @param user The address of the user
     * @param username The user's Hitmakr username
     * @param fullName The full name provided by the user
     * @param dateOfBirth The date of birth provided by the user
     * @param country The country provided by the user
     * @param timestamp The timestamp of the event
     */
    event ProfileDetailsCreated(
        address indexed user,
        string username,
        string fullName,
        uint64 dateOfBirth,
        string country,
        uint64 timestamp
    );

    /**
     * @notice Event emitted when a user's profile details are updated
     * @param user The address of the user
     * @param username The user's Hitmakr username
     * @param timestamp The timestamp of the event
     */
    event ProfileDetailsUpdated(
        address indexed user,
        string username,
        uint64 timestamp
    );

    /**
     * @notice Constructor initializes the contract with the HitmakrProfiles contract address
     * @param _profilesContract The address of the HitmakrProfiles contract
     */
    constructor(address _profilesContract) {
        if(_profilesContract == address(0)) revert ZeroAddress();
        profilesContract = IHitmakrProfiles(_profilesContract);
    }

    /// @notice Modifier that ensures only the profile owner can call the modified function
    modifier onlyProfileOwner() {
        if (!profilesContract._hasProfile(msg.sender)) revert NoProfile();
        _;
    }

    /**
     * @dev Internal function to validate the length of a string
     * @param str The string to be validated
     * @param maxLength The maximum allowed length of the string
     */
    function _validateLength(string calldata str, uint256 maxLength) private pure {
        if (bytes(str).length > maxLength) revert InvalidLength();
    }

    /**
     * @dev Internal function to validate a date of birth timestamp
     * @param timestamp The date of birth as a Unix timestamp
     */
    function _validateDateOfBirth(uint64 timestamp) private view {
        if (timestamp == 0) revert EmptyField();
        if (timestamp >= block.timestamp) revert InvalidTimestamp();
        
        uint256 age = (block.timestamp - timestamp) / YEAR_IN_SECONDS;
        if (age < MINIMUM_AGE) revert InvalidAge();
    }

    /**
     * @notice Sets the profile details for the calling user
     * @param fullName The user's full name
     * @param imageURI The URI of the user's profile image
     * @param bio The user's bio
     * @param dateOfBirth The user's date of birth as a Unix timestamp
     * @param country The user's country
     * @dev This function can be used both for initial setup and updating all fields at once.
     * If this is the first time setting details (initialized == false), it will increment detailsCount
     * and emit ProfileDetailsCreated. Otherwise, it will emit ProfileDetailsUpdated.
     */
    function setProfileDetails(
        string calldata fullName,
        string calldata imageURI,
        string calldata bio,
        uint64 dateOfBirth,
        string calldata country
    ) external onlyProfileOwner {
        if (bytes(fullName).length == 0) revert EmptyField();
        _validateLength(fullName, FULLNAME_MAX_LENGTH);
        _validateLength(imageURI, IMAGE_URI_MAX_LENGTH);
        _validateLength(bio, BIO_MAX_LENGTH);
        if (bytes(country).length == 0) revert EmptyField();
        _validateLength(country, COUNTRY_MAX_LENGTH);

        _validateDateOfBirth(dateOfBirth);

        bool isNewProfile = !profileDetails[msg.sender].initialized;

        profileDetails[msg.sender] = ProfileDetails({
            fullName: fullName,
            imageURI: imageURI,
            bio: bio,
            dateOfBirth: dateOfBirth,
            country: country,
            lastUpdated: uint64(block.timestamp),
            initialized: true
        });

        string memory username = profilesContract._nameByAddress(msg.sender);

        if (isNewProfile) {
            unchecked {
                ++detailsCount;
            }
            emit ProfileDetailsCreated(
                msg.sender,
                username,
                fullName,
                dateOfBirth,
                country,
                uint64(block.timestamp)
            );
        } else {
            emit ProfileDetailsUpdated(msg.sender, username, uint64(block.timestamp));
        }
    }

    /**
     * @notice Updates specific fields in the profile details for the calling user
     * @param fullName The user's updated full name (empty string to leave unchanged)
     * @param imageURI The updated URI of the user's profile image (empty string to leave unchanged)
     * @param bio The user's updated bio (empty string to leave unchanged)
     * @param country The user's updated country (empty string to leave unchanged)
     * @dev Only updates the fields that are provided (non-empty).
     * The date of birth cannot be updated through this function - use setProfileDetails instead.
     * Emits a ProfileDetailsUpdated event.
     */
    function updateProfileDetails(
        string calldata fullName,
        string calldata imageURI,
        string calldata bio,
        string calldata country
    ) external onlyProfileOwner {
        if (!profileDetails[msg.sender].initialized) revert NoProfile();

        ProfileDetails storage details = profileDetails[msg.sender];

        if (bytes(fullName).length > 0) {
            _validateLength(fullName, FULLNAME_MAX_LENGTH);
            details.fullName = fullName;
        }
        if (bytes(imageURI).length > 0) {
            _validateLength(imageURI, IMAGE_URI_MAX_LENGTH);
            details.imageURI = imageURI;
        }
        if (bytes(bio).length > 0) {
            _validateLength(bio, BIO_MAX_LENGTH);
            details.bio = bio;
        }
        if (bytes(country).length > 0) {
            _validateLength(country, COUNTRY_MAX_LENGTH);
            details.country = country;
        }

        details.lastUpdated = uint64(block.timestamp);
        
        string memory username = profilesContract._nameByAddress(msg.sender);
        emit ProfileDetailsUpdated(msg.sender, username, uint64(block.timestamp));
    }
}