// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title IHitmakrProfiles
 * @author Hitmakr Protocol
 * @notice Interface for the HitmakrProfiles contract, which manages user profiles as ERC721 tokens.
 * @dev This interface defines functions for registering profiles, checking profile existence, and retrieving profile information.  It inherits from the standard IERC721 interface, but adds specific functionality and error definitions relevant to Hitmakr profiles.  These profiles are expected to be Soulbound and non-transferable.
 */
interface IHitmakrProfiles is IERC721 {
    /// @notice Error for invalid username length (too short or too long)
    error InvalidUsernameLength();
    /// @notice Error for attempting to register a username that is already taken
    error UsernameTaken();
    /// @notice Error for providing a username with invalid characters
    error InvalidUsername();
    /// @notice Error for when a user attempts to register a second profile
    error AlreadyHasProfile();
    /// @notice Error for attempting to transfer a profile (not allowed, as they are Soulbound)
    error TransferNotAllowed();
    /// @notice Error for attempting to approve a profile for transfer or other actions.
    error ApprovalNotAllowed();
    /// @notice Error when a zero address is passed as a parameter.
    error ZeroAddress();

    /// @notice Event emitted when a new profile is created
    event ProfileCreated(address indexed user, string name, uint256 indexed tokenId);

    /**
     * @notice Registers a new profile with the given username for the calling user.
     * @param name The desired username for the profile.
     * @dev Reverts if the username is invalid, already taken, or if the user already has a profile.
     */
    function register(string calldata name) external;

    /**
     * @notice Returns the total number of profiles created.
     * @return The total profile count.
     */
    function _profileCount() external view returns (uint256);
    
    /**
     * @notice Returns the address associated with a given profile name hash.
     * @param nameHash The keccak256 hash of the profile username.
     * @return The address associated with the name hash, or the zero address if not found.
     */
    function _profileByNameHash(bytes32 nameHash) external view returns (address);
    
    /**
     * @notice Checks if a user already has a profile.
     * @param user The address of the user to check.
     * @return True if the user has a profile, false otherwise.
     */
    function _hasProfile(address user) external view returns (bool);
    
    /**
     * @notice Returns the username associated with a given address.
     * @param user The address of the user.
     * @return The username associated with the address, or an empty string if not found.
     */
    function _nameByAddress(address user) external view returns (string memory);
    
    /**
     * @notice Returns the token URI for the given token ID.
     * @param tokenId The ID of the token.
     * @return The token URI.
     * @dev This function is inherited from IERC721 and should return a URI pointing to the token's metadata.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}