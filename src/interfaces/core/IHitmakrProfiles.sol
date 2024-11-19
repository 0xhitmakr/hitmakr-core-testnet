// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title IHitmakrProfiles Interface
 * @author Hitmakr Protocol
 * @notice This interface defines the functions and events for interacting with the `HitmakrProfiles` contract.
 * This contract manages user profiles within the Hitmakr ecosystem, represented as non-transferable (SoulBound)
 * ERC721 tokens. Each profile is associated with a unique username and on-chain metadata, including a
 * dynamically generated SVG image.
 */
interface IHitmakrProfiles is IERC721 {
    /**
     * @notice Emitted when a new profile is created.
     * @param user The address of the user who created the profile.
     * @param name The username chosen for the profile.
     * @param tokenId The ID of the newly minted ERC721 token representing the profile.
     */
    event ProfileCreated(address indexed user, string name, uint256 indexed tokenId);

    /*
     * Custom errors for gas-efficient error handling. These provide specific revert reasons for better
     * debugging and user experience.
     */
    error InvalidUsernameLength();
    error UsernameTaken();
    error InvalidUsername();
    error AlreadyHasProfile();
    error TransferNotAllowed();
    error ApprovalNotAllowed();
    error ZeroAddress();

    /**
     * @notice Registers a new profile with the given username, minting a SoulBound NFT to the caller.
     * @param name The desired username for the profile.  Must meet the following requirements:
     *   - Length between 3 and 30 characters inclusive.
     *   - Contains only lowercase alphanumeric characters (a-z, 0-9).
     *   - Not already taken by another user.
     *
     * Reverts if the caller already has a profile.
     */
    function register(string calldata name) external;

    /**
     * @notice Retrieves the token URI for the given token ID.  The token URI contains the profile metadata,
     * including a dynamically generated SVG image.
     * @param tokenId The ID of the token.
     * @return A string representing the token URI.  This URI will resolve to a JSON document containing the
     * profile metadata.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /**
     * @notice Retrieves the address associated with a given username.
     * @param name The username to look up.
     * @return The address of the user who owns the profile with the given username, or the zero address if
     * no such profile exists.
     */
    function profileAddressByName(string calldata name) external view returns (address);

    /**
     * @notice Checks if a given address already has a registered profile.
     * @param user The address to check.
     * @return `true` if the address has a profile, `false` otherwise.
     */
    function hasProfile(address user) external view returns (bool);

    /**
     * @notice Retrieves the username associated with a given address.
     * @param user The address to look up.
     * @return The username associated with the given address, or an empty string if the address does not
     * have a profile.
     */
    function nameByAddress(address user) external view returns (string memory);

    /**
     * @notice Retrieves the total number of profiles created.
     * @return The total count of registered profiles.
     */
    function profileCount() external view returns (uint256);
}