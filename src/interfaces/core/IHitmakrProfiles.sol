// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title IHitmakrProfiles
 * @notice Interface for the HitmakrProfiles contract that implements Soulbound ERC721 tokens for user profiles
 */
interface IHitmakrProfiles is IERC721 {
    /// @notice Custom errors
    error InvalidUsernameLength();
    error UsernameTaken();
    error InvalidUsername();
    error AlreadyHasProfile();
    error TransferNotAllowed();
    error ApprovalNotAllowed();
    error ZeroAddress();

    /// @notice Event emitted when a profile is created
    event ProfileCreated(address indexed user, string name, uint256 indexed tokenId);

    /// @notice Returns total number of profiles created
    function _profileCount() external view returns (uint256);
    
    /// @notice Returns the address associated with a username hash
    function _profileByNameHash(bytes32) external view returns (address);
    
    /// @notice Returns whether an address has a profile
    function _hasProfile(address) external view returns (bool);
    
    /// @notice Returns the username associated with an address
    function _nameByAddress(address) external view returns (string memory);

    /**
     * @notice Registers a new profile with the given username
     * @param name The desired username for the profile
     * @dev Reverts if the username is invalid, already taken, or if the user already has a profile
     */
    function register(string calldata name) external;

    /**
     * @notice Returns the token URI for the given token ID
     * @param tokenId The ID of the token
     * @return A string representing the token URI
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /**
     * @dev Functions that are disabled due to soulbound nature
     */
    function transferFrom(address, address, uint256) external pure;
    function safeTransferFrom(address, address, uint256, bytes memory) external pure;
    function approve(address, uint256) external pure;
    function setApprovalForAll(address, bool) external pure;
}