// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/core/IHitmakrProfiles.sol";

/**
 * @title HitmakrProfileDetails
 * @author Hitmakr Protocol
 * @notice This contract allows Hitmakr profile holders to store additional details about themselves.  It works
 * in conjunction with the `HitmakrProfiles` contract, extending the basic profile information with fields
 * like full name, biography, profile image URI, date of birth, and country.  This contract enforces validation
 * rules on the input data to ensure data integrity and includes several helper functions for retrieving
 * profile information.
 */
contract HitmakrProfileDetails {
    /*
     * Custom errors for gas-efficient error handling and providing specific revert reasons.
     */
    error NoProfile();
    error InvalidLength();
    error InvalidTimestamp();
    error UnauthorizedUpdate();
    error EmptyField();
    error InvalidAge();
    error ZeroAddress();

    /*
     * Constants used for input validation. These constants define the maximum allowed lengths for various
     * string fields and the minimum allowed age.  `YEAR_IN_SECONDS` helps calculate age from timestamps.
     */
    uint256 private constant FULLNAME_MAX_LENGTH = 100;
    uint256 private constant BIO_MAX_LENGTH = 500;
    uint256 private constant IMAGE_URI_MAX_LENGTH = 200;
    uint256 private constant COUNTRY_MAX_LENGTH = 56;
    uint256 private constant MINIMUM_AGE = 6;
    uint256 private constant YEAR_IN_SECONDS = 365 days;
    
    /*
     * Immutable reference to the HitmakrProfiles contract. This reference is used to verify that a user
     * has a profile before allowing them to set or update their details.
     */
    IHitmakrProfiles public immutable profilesContract;

    /*
     * Struct to define the additional profile details that can be stored.
     */
    struct ProfileDetails {
        string fullName;      // User's full name.
        string imageURI;      // URI of the user's profile image.
        string bio;          // User's biography or short description.
        uint256 dateOfBirth; // User's date of birth (Unix timestamp).
        string country;       // User's country.
        uint256 lastUpdated; // Timestamp of the last update to the profile details.
        bool initialized;    // Boolean flag to track if the profile details have been initialized.
    }

    /*
     * Mapping from user addresses to their profile details.
     */
    mapping(address => ProfileDetails) private _profileDetails;
    

    /*
     * Counter for the total number of profiles with details set.
     */
    uint256 private _detailsCount;

    /*
     * Events emitted by the contract.  These events provide a record of profile detail changes, which is
     * useful for off-chain monitoring and analysis.  Indexed parameters allow for efficient filtering.
     */
    event ProfileDetailsCreated(
        address indexed user,
        string username,
        string fullName,
        uint256 dateOfBirth,
        string country,
        uint256 timestamp
    );

    event ProfileDetailsUpdated(
        address indexed user,
        string username,
        uint256 timestamp
    );

    /**
     * @notice Constructor initializes the contract with the address of the HitmakrProfiles contract.
     * @param _profilesContract The address of the HitmakrProfiles contract.
     */
    constructor(address _profilesContract) {
        if(_profilesContract == address(0)) revert ZeroAddress();
        profilesContract = IHitmakrProfiles(_profilesContract);
    }


    /*
     * Modifier to ensure that only the owner of a Hitmakr profile can call the modified function.
     */
    modifier onlyProfileOwner() {
        if (!profilesContract.hasProfile(msg.sender)) revert NoProfile();
        _;
    }

    /*
     * Internal helper functions for input validation. These functions are used to ensure data integrity
     * and prevent common errors.
     */
    function _validateLength(string calldata str, uint256 maxLength) private pure {
        if (bytes(str).length > maxLength) revert InvalidLength();
    }


    function _validateDateOfBirth(uint256 timestamp) private view {
        if (timestamp == 0) revert EmptyField();
        if (timestamp >= block.timestamp) revert InvalidTimestamp();
        
        uint256 age = (block.timestamp - timestamp) / YEAR_IN_SECONDS;
        if (age < MINIMUM_AGE) revert InvalidAge();
    }



    /**
     * @notice Sets or updates the profile details for the calling user.  Requires that the caller has a
     * registered Hitmakr profile.  Input data is validated to ensure data integrity.  Emits a
     * `ProfileDetailsCreated` event if this is the first time the user is setting their details, or a
     * `ProfileDetailsUpdated` event if the user is updating existing details.
     * @param fullName The user's full name.  Cannot be empty.  Max length is `FULLNAME_MAX_LENGTH`.
     * @param imageURI A URI pointing to the user's profile image. Max length is `IMAGE_URI_MAX_LENGTH`.
     * @param bio The user's biography or short description. Max length is `BIO_MAX_LENGTH`.
     * @param dateOfBirth The user's date of birth as a Unix timestamp. Must be in the past and represent an age
     * of at least `MINIMUM_AGE`.
     * @param country The user's country. Cannot be empty. Max length is `COUNTRY_MAX_LENGTH`.
     */
    function setProfileDetails(
        string calldata fullName,
        string calldata imageURI,
        string calldata bio,
        uint256 dateOfBirth,
        string calldata country
    ) external onlyProfileOwner {
        // Validate input lengths
        if (bytes(fullName).length == 0) revert EmptyField();
        _validateLength(fullName, FULLNAME_MAX_LENGTH);
        _validateLength(imageURI, IMAGE_URI_MAX_LENGTH);
        _validateLength(bio, BIO_MAX_LENGTH);
        if (bytes(country).length == 0) revert EmptyField();
        _validateLength(country, COUNTRY_MAX_LENGTH);

        // Validate date of birth
        _validateDateOfBirth(dateOfBirth);

        bool isNewProfile = !_profileDetails[msg.sender].initialized;

        // Update profile details
        _profileDetails[msg.sender] = ProfileDetails({
            fullName: fullName,
            imageURI: imageURI,
            bio: bio,
            dateOfBirth: dateOfBirth,
            country: country,
            lastUpdated: block.timestamp,
            initialized: true
        });

        string memory username = profilesContract.nameByAddress(msg.sender);

        // Update count and emit event
        if (isNewProfile) {
            unchecked {
                ++_detailsCount;
            }
            emit ProfileDetailsCreated(
                msg.sender,
                username,
                fullName,
                dateOfBirth,
                country,
                block.timestamp
            );
        } else {
            emit ProfileDetailsUpdated(msg.sender, username, block.timestamp);
        }
    }


    /**
     * @notice Allows users to update specific fields of their profile details. Only the fields provided
     * as non-empty strings will be updated.  Requires that the caller has a registered Hitmakr profile
     * and has previously initialized their profile details. Emits a `ProfileDetailsUpdated` event.
     * @param fullName The user's new full name. Provide an empty string to keep the current value. Max length is `FULLNAME_MAX_LENGTH`.
     * @param imageURI The new URI for the user's profile image.  Provide an empty string to keep the current value. Max length is `IMAGE_URI_MAX_LENGTH`.
     * @param bio The user's new bio. Provide an empty string to keep the current value.  Max length is `BIO_MAX_LENGTH`.
     * @param country The user's new country.  Provide an empty string to keep the current value. Max length is `COUNTRY_MAX_LENGTH`.
     */
    function updateProfileDetails(
        string calldata fullName,
        string calldata imageURI,
        string calldata bio,
        string calldata country
    ) external onlyProfileOwner {
        if (!_profileDetails[msg.sender].initialized) revert NoProfile();

        ProfileDetails storage details = _profileDetails[msg.sender];

        // Update only provided fields
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

        details.lastUpdated = block.timestamp;
        
        string memory username = profilesContract.nameByAddress(msg.sender);
        emit ProfileDetailsUpdated(msg.sender, username, block.timestamp);
    }


    /**
     * @notice Retrieves the profile details for a given user address.
     * @param user The address of the user whose details are being retrieved.
     * @return fullName The user's full name.
     * @return imageURI The URI of the user's profile image.
     * @return bio The user's biography.
     * @return dateOfBirth The user's date of birth as a Unix timestamp.
     * @return country The user's country.
     * @return lastUpdated The timestamp of the last update to the profile details.
     * @return initialized A boolean indicating whether the profile details have been initialized for this user.
     */
    function getProfileDetails(address user) external view returns (
        string memory fullName,
        string memory imageURI,
        string memory bio,
        uint256 dateOfBirth,
        string memory country,
        uint256 lastUpdated,
        bool initialized
    ) {
        ProfileDetails memory details = _profileDetails[user];
        return (
            details.fullName,
            details.imageURI,
            details.bio,
            details.dateOfBirth,
            details.country,
            details.lastUpdated,
            details.initialized
        );
    }



    /**
     * @notice Retrieves the complete profile information for a given user, including the username from
     * the `HitmakrProfiles` contract and the details stored in this contract.
     * @param user The address of the user whose profile information is being retrieved.
     * @return username The user's username from HitmakrProfiles.
     * @return fullName The user's full name.
     * @return imageURI The URI of the user's profile image.
     * @return bio The user's biography.
     * @return dateOfBirth The user's date of birth as a Unix timestamp.
     * @return country The user's country.
     * @return lastUpdated The timestamp of the last update to the profile details.
     * @return initialized A boolean indicating whether the profile details have been initialized for this user.

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
        ProfileDetails memory details = _profileDetails[user];
        return (
            profilesContract.nameByAddress(user),
            details.fullName,
            details.imageURI,
            details.bio,
            details.dateOfBirth,
            details.country,
            details.lastUpdated,
            details.initialized
        );
    }


    /**
     * @notice Checks whether a given user has initialized their profile details.
     * @param user The address to check.
     * @return initialized A boolean indicating whether the profile details have been initialized.
     */
    function hasProfileDetails(address user) external view returns (bool initialized) {
        return _profileDetails[user].initialized;
    }


    /**
     * @notice Retrieves the total number of profiles with details stored in this contract.
     * @return count The total count of profiles with details.
     */
    function getDetailsCount() external view returns (uint256 count) {
        return _detailsCount;
    }
}