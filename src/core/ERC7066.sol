// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "../interfaces/core/IERC7066.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title ERC7066: Lockable Extension for ERC721
/// @dev Implementation for the Lockable extension ERC7066 for ERC721
/// @author StreamNFT 
abstract contract ERC7066 is ERC721, IERC7066 {
    /*///////////////////////////////////////////////////////////////
                            ERC7066 EXTENSION STORAGE                        
    //////////////////////////////////////////////////////////////*/

    //Mapping from tokenId to user address for locker
    mapping(uint256 => address) internal locker;

    /*///////////////////////////////////////////////////////////////
                              ERC7066 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the locker for the tokenId
     *      address(0) means token is not locked
     *      reverts if token does not exist
     */
    function lockerOf(uint256 tokenId) public virtual view returns(address) {
        // Using _ownerOf instead of _exists - if owner is address(0), token doesn't exist
        if (_ownerOf(tokenId) == address(0)) {
            revert("ERC7066: Nonexistent token");
        }
        return locker[tokenId];
    }

    /**
     * @dev Public function to lock the token. Verifies if the msg.sender is owner or approved
     *      reverts otherwise
     */
    function lock(uint256 tokenId) public virtual {
        require(locker[tokenId] == address(0), "ERC7066: Locked");
        require(_isAuthorized(_ownerOf(tokenId), _msgSender(), tokenId), "Require owner or approved");
        _lock(tokenId, msg.sender);
    }

    /**
     * @dev Public function to lock the token. Verifies if the msg.sender is owner
     *      reverts otherwise
     */
    function lock(uint256 tokenId, address _locker) public virtual {
        require(locker[tokenId] == address(0), "ERC7066: Locked");
        require(ownerOf(tokenId) == msg.sender, "ERC7066: Require owner");
        _lock(tokenId, _locker);
    }

    /**
     * @dev Internal function to lock the token.
     */
    function _lock(uint256 tokenId, address _locker) internal {
        locker[tokenId] = _locker;
        emit Lock(tokenId, _locker);
    }

    /**
     * @dev Public function to unlock the token. Verifies the msg.sender is locker
     *      reverts otherwise
     */
    function unlock(uint256 tokenId) public virtual {
        require(locker[tokenId] != address(0), "ERC7066: Unlocked");
        require(locker[tokenId] == msg.sender, "ERC7066: Not locker");
        _unlock(tokenId);
    }

    /**
     * @dev Internal function to unlock the token. 
     */
    function _unlock(uint256 tokenId) internal {
        delete locker[tokenId];
        emit Unlock(tokenId);
    }

    /**
     * @dev Public function to tranfer and lock the token. Reverts if caller is not owner or approved.
     *      Lock the token and set locker to caller
     *.     Optionally approve caller if bool setApprove flag is true
     */
    function transferAndLock(address from, address to, uint256 tokenId, bool setApprove) public virtual {
        _transferAndLock(tokenId, from, to, setApprove);
    }

    /**
     * @dev Internal function to tranfer, update locker/approve and lock the token.
     */
    function _transferAndLock(uint256 tokenId, address from, address to, bool setApprove) internal {
        transferFrom(from, to, tokenId); 
        if (setApprove) {
            _approve(msg.sender, tokenId, _msgSender());
        }
        _lock(tokenId, msg.sender);
    }

    /**
     * @dev Override _update to make sure token is unlocked or msg.sender is approved if 
     * token is locked
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        
        // Only check lock status for transfers (not mints)
        if (from != address(0)) { 
            require(
                locker[tokenId] == address(0) || 
                (locker[tokenId] == msg.sender && 
                 (isApprovedForAll(from, msg.sender) || getApproved(tokenId) == msg.sender)),
                "ERC7066: Locked"
            );
            // Clear the locker when transferring
            delete locker[tokenId];
        }

        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Override approve to make sure token is unlocked
     */
    function approve(address to, uint256 tokenId) public virtual override(ERC721) {
        require(locker[tokenId] == address(0), "ERC7066: Locked");
        super.approve(to, tokenId);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return
            interfaceId == type(IERC7066).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}