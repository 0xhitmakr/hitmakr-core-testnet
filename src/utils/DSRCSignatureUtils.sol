// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title DSRCSignatureUtils
 * @author Hitmakr Protocol
 * @notice This library provides utility functions for verifying cross-chain signatures related to Decentralized
 * Standard Recording Codes (DSRCs).  It's designed to be used by other contracts within the Hitmakr ecosystem,
 * specifically by the verifier responsible for deploying DSRCs on behalf of users.  The library enforces strict
 * validation rules on signatures and DSRC parameters to ensure security and prevent misuse.  It includes functions
 * for hashing DSRC parameters, calculating domain separators, verifying signatures, and splitting signatures into
 * their component parts.  The library incorporates enhanced security checks, including deadline validation and
 * stricter checks on signature values, to mitigate potential vulnerabilities.
 */
library DSRCSignatureUtils {
    /**
     * @notice Custom errors for gas-efficient error handling and detailed revert reasons.  These errors
     * provide specific information about the nature of the validation failure.
     */
    error InvalidSignature();
    error SignatureExpired();
    error InvalidSignatureLength();
    error InvalidVValue();
    error DeadlineTooLong();
    error DeadlineTooShort();
    error InvalidArrayLengths();
    error ArrayTooLong();
    error ZeroAddress();
    error TooManyRecipients(uint256 provided, uint256 maximum);
    error InvalidTotalPercentage(uint256 provided);
    error URITooLong(uint256 provided, uint256 maximum);
    error EmptyURI();
    error PriceTooHigh(uint256 provided, uint256 maximum);

    /*
     * Event emitted when a signature is successfully verified.  Provides information about the signer,
     * deadline, and selected chain.  Indexed parameters enable efficient event filtering.
     */
    event SignatureVerified(address indexed signer, uint256 deadline, string selectedChain);

    /*
     * Constants used for validation, including maximum and minimum deadline durations, maximum array lengths,
     * maximum number of recipients, maximum URI length, and basis points for percentage calculations.
     * `SALT` is used to create a unique domain separator for this library.
     */
    uint256 private constant MAX_DEADLINE_DURATION = 1 hours;
    uint256 private constant MIN_DEADLINE_DURATION = 5 minutes;
    uint256 private constant MAX_ARRAY_LENGTH = 100;
    uint256 private constant MAX_RECIPIENTS = 10;
    uint256 private constant MAX_URI_LENGTH = 1000;
    uint256 private constant BASIS_POINTS = 10000;  // Used for percentage calculations (100% = 10000 basis points)

    bytes32 private constant SALT = keccak256("HITMAKR_DSRC_V1");

    /*
     * Struct to define the parameters required for creating a DSRC.  This struct is used for hashing
     * and signature verification.
     */
    struct DSRCParams {
        string tokenURI;        // URI of the token metadata.
        uint256 price;         // Price of the DSRC.
        address[] recipients;  // Array of recipient addresses for royalties/splits.
        uint256[] percentages; // Array of percentages (in basis points) for each recipient.
        uint256 nonce;         // Nonce to prevent replay attacks.
        uint256 deadline;      // Deadline for the signature validity.
        string selectedChain;   // The blockchain where the DSRC will be deployed.
    }

    // Typehashes for EIP-712 signature verification
    bytes32 private constant EIP712DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,address verifyingContract,bytes32 salt)"
    );

    bytes32 private constant DSRC_TYPEHASH = keccak256(
        "DSRCParams(string tokenURI,uint256 price,address[] recipients,uint256[] percentages,uint256 nonce,uint256 deadline,string selectedChain)"
    );


    /*
     * Internal helper functions for validating DSRC parameters. These functions help ensure that the
     * parameters meet the required criteria before being used for signature verification.
     */

    /**
     * @dev Validates the length and content of the token URI.  Reverts if the URI is empty or exceeds the
     * maximum allowed length.
     * @param uri The token URI string to validate.
     */
    function _validateURI(string memory uri) private pure {
        uint256 length = bytes(uri).length;
        if (length == 0) revert EmptyURI();
        if (length > MAX_URI_LENGTH) revert URITooLong(length, MAX_URI_LENGTH);
    }

    /**
     * @dev Validates that the price is within acceptable bounds. Reverts if the price exceeds the maximum
     * allowed value.
     * @param price The price to validate.
     */
    function _validatePrice(uint256 price) private pure {
        if (price > type(uint216).max) revert PriceTooHigh(price, type(uint216).max);
    }

    /**
     * @dev Validates that the sum of percentages in the `percentages` array equals 100% (represented as
     * `BASIS_POINTS`). Reverts if the total percentage is not equal to 100% or if any individual percentage
     * exceeds the maximum value for a uint16.
     * @param percentages An array of percentages (in basis points) to validate.
     */
    function _validatePercentages(uint256[] memory percentages) private pure {
        uint256 totalPercentage;
        for (uint256 i = 0; i < percentages.length; i++) {
            if (percentages[i] > type(uint16).max) revert InvalidTotalPercentage(percentages[i]); // Check individual percentage bounds
            totalPercentage += percentages[i];
        }
        if (totalPercentage != BASIS_POINTS) revert InvalidTotalPercentage(totalPercentage);
    }


    /**
     * @notice Calculates the EIP-712 domain separator for this library.  This is a crucial component of
     * EIP-712 signature verification and helps prevent replay attacks across different domains.
     * @param name The name of the signing domain.
     * @param version The version of the signing domain.
     * @param verifyingContract The address of the contract that will verify the signature.
     * @return The calculated domain separator.
     */
    function getDomainSeparator(
        string memory name,
        string memory version,
        address verifyingContract
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                verifyingContract,
                SALT
            )
        );
    }

    /**
     * @notice Hashes the DSRC parameters using EIP-712.  This creates a unique digest that is then used
     * for signature verification. Includes additional validation checks on the DSRC parameters to ensure
     * data integrity.
     * @param params The DSRC parameters to hash.
     * @return The calculated hash of the DSRC parameters.
     */
    function hashDSRCParams(DSRCParams memory params) internal pure returns (bytes32) {
        if (params.recipients.length != params.percentages.length) revert InvalidArrayLengths();
        if (params.recipients.length > MAX_ARRAY_LENGTH) revert ArrayTooLong();
        if (params.recipients.length > MAX_RECIPIENTS) revert TooManyRecipients(params.recipients.length, MAX_RECIPIENTS);
        if (params.recipients.length == 0) revert InvalidArrayLengths();

        _validateURI(params.tokenURI);
        _validatePrice(params.price);
        _validatePercentages(params.percentages);

        for (uint256 i = 0; i < params.recipients.length; i++) {
            if (params.recipients[i] == address(0)) revert ZeroAddress();
        }

        return keccak256(
            abi.encode(
                DSRC_TYPEHASH,
                keccak256(bytes(params.tokenURI)),
                params.price,
                keccak256(abi.encodePacked(params.recipients)),
                keccak256(abi.encodePacked(params.percentages)),
                params.nonce,
                params.deadline,
                keccak256(bytes(params.selectedChain))
            )
        );
    }

    /**
     * @notice Verifies a signature against the hashed DSRC parameters and the calculated domain separator.
     * Implements enhanced security checks, including deadline validation and stricter checks on signature
     * values, to prevent common vulnerabilities. Emits a `SignatureVerified` event if the signature is valid.
     * @param params The DSRC parameters associated with the signature.
     * @param signature The signature to verify.
     * @param name The name of the signing domain.
     * @param version The version of the signing domain.
     * @param verifyingContract The address of the contract verifying the signature.
     * @return signer The recovered address of the signer. Reverts if the signature is invalid or expired.
     */
    function verify(
        DSRCParams memory params,
        bytes memory signature,
        string memory name,
        string memory version,
        address verifyingContract
    ) internal returns (address signer) {
        if (block.timestamp > params.deadline) revert SignatureExpired();
        if (params.deadline < block.timestamp + MIN_DEADLINE_DURATION) revert DeadlineTooShort();
        if (params.deadline > block.timestamp + MAX_DEADLINE_DURATION) revert DeadlineTooLong();


        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                getDomainSeparator(name, version, verifyingContract),
                hashDSRCParams(params)
            )
        );

        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);

        // Stricter signature validation
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidSignature();
        }

        address recoveredSigner = ecrecover(digest, v, r, s);
        if (recoveredSigner == address(0)) revert InvalidSignature();

        emit SignatureVerified(recoveredSigner, params.deadline, params.selectedChain);
        return recoveredSigner;
    }


    /**
     * @notice Splits a raw ECDSA signature into its component parts (r, s, and v).  Performs validation
     * checks on the signature length and `v` value.  Reverts if the signature is invalid.
     * @param sig The raw ECDSA signature.
     * @return r The `r` value of the signature.
     * @return s The `s` value of the signature.
     * @return v The `v` value of the signature.
     */
    function splitSignature(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        if (sig.length != 65) revert InvalidSignatureLength();

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        if (v < 27) v += 27;
        if (v != 27 && v != 28) revert InvalidVValue();  // Ensure v is valid
    }
}