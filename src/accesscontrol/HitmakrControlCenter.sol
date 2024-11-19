// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title HitmakrControlCenter
 * @author Hitmakr Protocol
 * @notice This contract handles core administrative functions for the Hitmakr Protocol.  It manages
 * administrator and verifier roles, allowing for fine-grained control over critical operations.  The contract
 * is designed with gas efficiency as a primary concern, leveraging optimized storage patterns and minimizing
 * external calls.  It also integrates OpenZeppelin's `Pausable` and `ReentrancyGuard` contracts for enhanced
 * security.
 */
contract HitmakrControlCenter is Ownable, Pausable, ReentrancyGuard {

    /*
     * We use custom errors instead of string reverts to save on gas.  Each error represents a specific
     * exceptional condition that can occur within the contract.
     */
    error Unauthorized();
    error InvalidAddress();
    error InvalidBatch();
    error AlreadyAdmin();
    error NotAdmin();
    error AlreadyVerifier();
    error NotVerifier();
    error ZeroSuccess();


    /*
     * To minimize storage costs, we pack the admin and verifier counts into a single struct.  We use uint248 for
     * verifier count to allow for a very large number of verifiers, while uint8 for admin count is sufficient
     * given the expected smaller number of administrators.  This packing saves significant gas compared to
     * storing these counts in separate variables.
     */
    struct RoleData {
        uint248 verifierCount;
        uint8 adminCount;
    }

    RoleData private _roleData;


    /*
     * We use separate mappings for admins and verifiers for gas efficiency.  While a single mapping with
     * an enum could be used, this approach results in lower gas costs during lookups.
     */
    mapping(address => bool) private _admins;
    mapping(address => bool) private _verifiers;


    /*
     *  We set a maximum batch size for verifier updates to prevent excessively large transactions that
     *  could consume too much gas.
     */
    uint256 private constant MAX_BATCH_SIZE = 100;


    /*
     * Events are emitted for key actions, allowing off-chain monitoring and analysis. We minimize the number
     * of indexed parameters to reduce event emission costs.
     */
    event AdminUpdated(address indexed account, bool status);
    event VerifierUpdated(address indexed account, bool status);
    event BatchVerifierProcessed(uint256 count);
    event EmergencyAction(bool paused);



    /**
     * @notice Constructor. Initializes the contract with the deployer as the first admin.
     */
    constructor() Ownable(msg.sender) {
        _admins[msg.sender] = true;
        _roleData.adminCount = 1;
        emit AdminUpdated(msg.sender, true);
    }



    /**
     * @notice Sets or revokes admin privileges for a single account.  Only callable by the contract owner.
     * @param account  The address of the account to modify.
     * @param grant  True to grant admin privileges, false to revoke.
     */
    function setAdmin(address account, bool grant)
        external
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        if (account == address(0)) revert InvalidAddress();

        if (grant) {
            if (_admins[account]) revert AlreadyAdmin();
            _admins[account] = true;
            unchecked { ++_roleData.adminCount; }  // Using unchecked increment for gas efficiency, since overflow is highly unlikely.
        } else {
            if (!_admins[account]) revert NotAdmin();
            if (account == owner()) revert Unauthorized(); // Owner cannot remove their own admin role.
            _admins[account] = false;
            unchecked { --_roleData.adminCount; } // Using unchecked decrement for gas efficiency.
        }

        emit AdminUpdated(account, grant);
    }



    /**
     * @notice Sets or revokes verifier privileges for a batch of accounts.  This function is optimized for gas efficiency
     * by processing multiple accounts in a single transaction.  Only callable by the contract owner.
     * @param accounts  An array of addresses to modify.
     * @param grant  True to grant verifier privileges, false to revoke.
     */
    function batchSetVerifiers(address[] calldata accounts, bool grant)
        external
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        uint256 len = accounts.length;
        if (len == 0 || len > MAX_BATCH_SIZE) revert InvalidBatch();  // Enforce a reasonable batch size.

        uint256 successCount;
        address account;

        for (uint256 i; i < len;) {
            account = accounts[i];
            // Skip zero addresses to prevent issues.
            if (account == address(0)) {
                 unchecked { ++i; }
                 continue;
            }

            bool currentStatus = _verifiers[account];

            // Only update if the status is actually changing.
            if (grant != currentStatus) {
                _verifiers[account] = grant;
                emit VerifierUpdated(account, grant);
                unchecked { ++successCount; }  // Safe to use unchecked increment.
            }

            unchecked { ++i; }  // Safe to use unchecked increment.
        }

        if (successCount == 0) revert ZeroSuccess();


        if (grant) {
            unchecked {  _roleData.verifierCount += uint248(successCount); } // Safe unchecked addition
        } else {
            unchecked { _roleData.verifierCount -= uint248(successCount); } // Safe unchecked subtraction
        }

        emit BatchVerifierProcessed(successCount);
    }



    /**
     * @notice Allows the owner to pause or unpause the contract in case of an emergency.  This will halt
     * most critical functions to prevent further damage or exploits.
     */
    function toggleEmergencyPause() external onlyOwner nonReentrant {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
        emit EmergencyAction(paused());
    }



    /**
     * @notice Checks if a given address has admin privileges.
     * @param account  The address to check.
     * @return  True if the address has admin privileges, false otherwise.
     */
    function isAdmin(address account) public view returns (bool) {
        return _admins[account];
    }


    /**
     * @notice Checks if a given address has verifier privileges.
     * @param account The address to check.
     * @return True if the address has verifier privileges, false otherwise.
     */
    function isVerifier(address account) public view returns (bool) {
        return _verifiers[account];
    }


    /**
     * @notice Returns the current count of admins and verifiers. Primarily used for off-chain monitoring.
     * @return adminCount  The current number of admins.
     * @return verifierCount  The current number of verifiers.
     */
    function getRoleCounts() external view returns (uint256 adminCount, uint256 verifierCount) {
        return (_roleData.adminCount, _roleData.verifierCount);
    }
}