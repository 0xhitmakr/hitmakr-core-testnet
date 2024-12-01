// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/core/IHitmakrProfiles.sol";

/**
 * @title HitmakrProfileDetails
 * @author Hitmakr Protocol
 * @notice Contract for managing additional profile details for Hitmakr users.
 * @dev This contract allows users to store and manage extended profile information linked to their Hitmakr profile. It interacts with the `IHitmakrProfiles` contract to ensure that only profile owners can manage their details.  It includes validation for input lengths, timestamps, and age restrictions.
 */
contract HitmakrProfileDetails {
    /// @notice Error for when a user tries to interact with details without having a profile
    error NoProfile();
    /// @notice Error for when a provided string exceeds the maximum allowed length
    error InvalidLength();
    /// @notice Error for when an invalid timestamp (e.g., future date) is provided
    error InvalidTimestamp();
    /// @notice Error when update not initialized for the user
    error UnauthorizedUpdate();
    /// @notice Error for when a required field is left empty
    error EmptyField();
    /// @notice Error for when the calculated age based on date of birth is below the minimum requirement
    error InvalidAge();
    /// @notice Error for when a zero address is passed as parameter
    error ZeroAddress();

    /// @notice Maximum length for full name strings
    uint256 private constant FULLNAME_MAX_LENGTH = 100;
    /// @notice Maximum length for bio strings
    uint256 private constant BIO_MAX_LENGTH = 500;
    /// @notice Maximum length for image URI strings
    uint256 private constant IMAGE_URI_MAX_LENGTH = 200;
    /// @notice Maximum length for country strings
    uint256 private constant COUNTRY_MAX_LENGTH = 56;
    /// @notice Minimum allowed age in years
    uint256 private constant MINIMUM_AGE = 6;
    /// @notice Number of seconds in a year (used for age calculation)
    uint256 private constant YEAR_IN_SECONDS = 365 days;
    
    /// @notice Instance of the HitmakrProfiles contract
    IHitmakrProfiles public immutable profilesContract;

    /**
     * @notice Structure to hold the additional profile details for a user.
     * @member fullName The user's full name.
     * @member imageURI URI pointing to the user's profile image.
     * @member bio A short biography or description provided by the user.
     * @member dateOfBirth The user's date of birth as a Unix timestamp.
     * @member country The user's country.
     * @member lastUpdated Timestamp of the last update to the profile details.
     * @member initialized Boolean flag indicating whether the profile details have been initialized.
     */
    struct ProfileDetails {
        string fullName;
        string imageURI;
        string bio;
        uint256 dateOfBirth;
        string country;
        uint256 lastUpdated;
        bool initialized;
    }

    /// @notice Mapping from user address to their profile details
    mapping(address => ProfileDetails) public profileDetails;
    /// @notice Count of profiles with initialized details
    uint256 public detailsCount;

    /**
     * @notice Emitted when a user creates their profile details for the first time.
     * @param user The address of the user.
     * @param username The username associated with the user's profile.
     * @param fullName The full name provided by the user.
     * @param dateOfBirth The date of birth provided by the user.
     * @param country The country provided by the user.
     * @param timestamp The timestamp when the event was emitted.
     */
    event ProfileDetailsCreated(
        address indexed user,
        string username,
        string fullName,
        uint256 dateOfBirth,
        string country,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a user updates their existing profile details.
     * @param user The address of the user.
     * @param username The username associated with the user's profile.
     * @param timestamp The timestamp when the event was emitted.
     */
    event ProfileDetailsUpdated(
        address indexed user,
        string username,
        uint256 timestamp
    );

    /**
     * @notice Constructor to initialize the contract with the `HitmakrProfiles` contract address.
     * @param _profilesContract The address of the deployed `HitmakrProfiles` contract.
     */
    constructor(address _profilesContract) {
        if(_profilesContract == address(0)) revert ZeroAddress();
        profilesContract = IHitmakrProfiles(_profilesContract);
    }

    /// @notice Modifier to ensure that only the owner of a profile can call the modified function.
    modifier onlyProfileOwner() {
        if (!profilesContract._hasProfile(msg.sender)) revert NoProfile();
        _;
    }

     /**
     * @dev Internal helper function to validate the length of a string.
     * @param str The string to validate.
     * @param maxLength The maximum allowed length of the string.
     */
    function _validateLength(string calldata str, uint256 maxLength) private pure {
        if (bytes(str).length > maxLength) revert InvalidLength();
    }

    /**
     * @dev Internal helper function to validate a date of birth timestamp.
     * @param timestamp The date of birth as a Unix timestamp.
     */
    function _validateDateOfBirth(uint256 timestamp) private view {
        if (timestamp == 0) revert EmptyField();
        if (timestamp >= block.timestamp) revert InvalidTimestamp();
        
        uint256 age = (block.timestamp - timestamp) / YEAR_IN_SECONDS;
        if (age < MINIMUM_AGE) revert InvalidAge();
    }

     /**
     * @notice Sets the profile details for the calling user.  This function is used for initial setup of profile details.
     * @param fullName The user's full name.
     * @param imageURI URI of the user's profile image.
     * @param bio The user's bio.
     * @param dateOfBirth The user's date of birth as a Unix timestamp.
     * @param country The user's country.
     * @dev Emits a `ProfileDetailsCreated` event.
     */
    function setProfileDetails(
        string calldata fullName,
        string calldata imageURI,
        string calldata bio,
        uint256 dateOfBirth,
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
            lastUpdated: uint256(block.timestamp),
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
                uint256(block.timestamp)
            );
        } else {
            emit ProfileDetailsUpdated(msg.sender, username, uint256(block.timestamp));
        }
    }

    /**
     * @notice Updates specific fields in the user's profile details. This function can be used to update one or more fields without overwriting the entire profile.
     * @param fullName The user's updated full name.  An empty string will leave this field unchanged.
     * @param imageURI  The user's updated profile image URI. An empty string will leave this field unchanged.
     * @param bio The user's updated bio. An empty string will leave this field unchanged.
     * @param country The user's updated country. An empty string will leave this field unchanged.
     * @dev Only callable by the profile owner. Emits a `ProfileDetailsUpdated` event.
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

        details.lastUpdated = uint256(block.timestamp);
        
        string memory username = profilesContract._nameByAddress(msg.sender);
        emit ProfileDetailsUpdated(msg.sender, username, uint256(block.timestamp));
    }

    /**
     * @notice Retrieves all profile information for a user, including details from the linked `HitmakrProfiles` contract.
     * @param user The address of the user whose profile information is being retrieved.
     * @return username The user's username.
     * @return fullName The user's full name.
     * @return imageURI The URI of the user's profile image.
     * @return bio The user's biography.
     * @return dateOfBirth The user's date of birth as Unix timestamp.
     * @return country The user's country.
     * @return lastUpdated The timestamp of the last profile update.
     * @return initialized Boolean indicating whether the profile details have been initialized.
     */
    function getCompleteProfile(address user) external view returns (
        string memory username,
        string memory fullName,
        string memory imageURI,
        string memory bio,
        uint256 dateOfBirth,
        string memory country,
        uint256 lastUpdated,
        bool initialized
    ) {
        ProfileDetails memory details = profileDetails[user];
        return (
            profilesContract._nameByAddress(user),
            details.fullName,
            details.imageURI,
            details.bio,
            details.dateOfBirth,
            details.country,
            details.lastUpdated,
            details.initialized
        );
    }
}