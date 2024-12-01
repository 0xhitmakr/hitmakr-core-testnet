// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/**
 * @title HitmakrProfiles Contract
 * @notice This contract implements Soulbound ERC721 tokens for user profiles.
 * @dev Profiles are non-transferable and linked to a unique username.  The SVG image for the NFT is dynamically generated.
 */
contract HitmakrProfiles is ERC721 {
    using Strings for uint256;
    using Strings for address;

    /// @notice Custom errors for gas optimization
    error InvalidUsernameLength();
    error UsernameTaken();
    error InvalidUsername();
    error AlreadyHasProfile();
    error TransferNotAllowed();
    error ApprovalNotAllowed();
    error ZeroAddress();

    /// @notice Minimum allowed username length
    uint256 private immutable MINIMUM_LENGTH = 3;
    /// @notice Maximum allowed username length
    uint256 private immutable MAXIMUM_LENGTH = 30;
    /// @notice Total number of profiles created
    uint256 public _profileCount;
    
    /// @notice Mapping from username hash to user address
    mapping(bytes32 => address) public _profileByNameHash;
    /// @notice Mapping from user address to boolean indicating profile existence
    mapping(address => bool) public _hasProfile;
    /// @notice Mapping from user address to username string
    mapping(address => string) public _nameByAddress;

    /// @notice Event emitted when a profile is created
    event ProfileCreated(address indexed user, string name, uint256 indexed tokenId);
    
    /// @notice Prefix for the SVG image data
    bytes private constant SVG_PREFIX = bytes('<svg width="440" height="255" viewBox="0 0 440 255" fill="none" xmlns="http://www.w3.org/2000/svg"> <rect width="440" height="255" rx="25" fill="url(#paint0_linear_170_24)"/> <path d="M388.916 42.0514C390.176 42.3864 391.419 42.7837 392.621 43.2862C394.368 44.0169 396.122 44.7545 397.696 45.8197C398.537 46.3884 399.456 46.8522 400.186 47.5895C400.338 47.7434 400.334 47.7925 400.237 47.9339C399.945 48.3627 399.788 48.799 399.873 49.3567C400.043 50.4799 401.425 51.1725 402.372 50.5074C402.793 50.2112 402.952 50.314 403.164 50.6915C403.779 51.7869 404.38 52.8697 404.365 54.1934C404.346 55.7265 403.663 56.897 402.506 57.8194C401.022 59.0022 399.263 59.5407 397.432 59.8737C394.691 60.3722 391.942 60.284 389.194 59.9324C386.315 59.5639 383.531 58.81 380.808 57.8202C379.527 57.3544 378.285 56.7932 377.083 56.1525C375.665 55.3969 374.257 54.6185 373.008 53.5947C372.5 53.1787 372.011 52.7392 371.53 52.292C371.105 51.8975 371.116 51.8864 371.522 51.5057C372.568 50.5245 372.827 48.9029 372.054 47.6937C371.425 46.7114 370.356 46.004 369.05 46.3C368.688 46.382 368.573 46.263 368.644 45.8944C368.855 44.7995 369.475 43.9447 370.299 43.243C371.844 41.9269 373.739 41.4455 375.671 41.0495C376.912 40.795 378.171 40.7457 379.423 40.7367C380.84 40.7264 382.266 40.7717 383.673 41.0237C383.917 41.0675 383.99 41.1505 383.997 41.392C384.025 42.4099 384.033 42.4132 383.022 42.3274C382.172 42.2552 381.327 42.1119 380.47 42.1449C379.107 42.1975 377.759 42.3097 376.482 42.8595C375.317 43.3614 374.477 44.1905 373.915 45.3127C373.859 45.4234 373.77 45.5495 373.848 45.6995C374.036 45.733 374.105 45.5714 374.196 45.4715C375.66 43.8677 377.521 43.109 379.636 42.8259C380.984 42.6454 382.319 42.6704 383.662 42.823C383.943 42.855 384.017 42.9764 383.996 43.2285C383.981 43.4074 383.989 43.5884 383.989 43.7684C383.989 44.5617 383.992 44.5425 383.195 44.453C381.871 44.304 380.558 44.3719 379.305 44.8694C378.313 45.2632 377.63 45.9765 377.228 47.0617C377.63 46.8957 377.802 46.5837 378.035 46.359C379.023 45.4044 380.247 45.0152 381.559 44.8387C382.271 44.743 382.988 44.685 383.709 44.7999C383.915 44.8327 384.007 44.9067 383.991 45.1114C383.988 45.1412 383.99 45.1714 383.991 45.2014C384.015 46.0134 384.012 45.9919 383.222 46.114C382.47 46.2304 381.714 46.3512 381.049 46.772C379.901 47.4974 379.653 48.515 380.396 49.6412C380.914 50.426 381.637 51.0107 382.426 51.5045C383.809 52.369 385.326 52.8974 386.917 53.2125C388.604 53.5467 390.289 53.5934 391.925 52.9674C392.662 52.6854 393.26 52.2319 393.376 51.362C393.446 50.8422 393.281 50.3799 393.008 49.9604C392.283 48.8445 391.228 48.1144 390.058 47.5407C389.674 47.3529 389.31 47.088 388.853 47.0845C388.87 46.9099 388.901 46.735 388.902 46.56C388.91 45.0569 388.912 43.554 388.916 42.0514ZM387.536 56.9014C387.665 57.1099 387.849 57.1067 388.005 57.1947C388.162 57.2832 388.382 57.2525 388.569 57.2959C390.43 57.726 392.316 57.8997 394.221 57.7635C395.444 57.676 396.637 57.4337 397.706 56.7702C398.783 56.1012 399.543 55.2004 399.83 53.9334C398.61 55.5875 396.902 56.4657 394.979 56.9614C393.352 57.3805 391.679 57.2787 390.018 57.2649C389.948 57.2642 389.879 57.2162 389.807 57.2064C389.05 57.1029 388.293 57.0025 387.536 56.9014ZM388.288 55.1252C388.349 55.2084 388.362 55.2467 388.381 55.2502C389.694 55.4855 391.011 55.6619 392.348 55.5347C393.25 55.449 394.133 55.2707 394.892 54.7414C395.521 54.3022 396.041 53.7647 396.227 52.8705C395.807 53.395 395.391 53.7794 394.915 54.0937C393.239 55.2017 391.362 55.297 389.442 55.1639C389.074 55.1384 388.708 55.0682 388.288 55.1252Z" fill="url(#paint1_linear_170_24)"/> <path d="M388.916 42.0513C388.912 43.554 388.909 45.0568 388.902 46.5595C388.901 46.7345 388.87 46.9093 388.853 47.084C388.94 47.4835 388.897 47.889 388.889 48.2903C388.883 48.5485 388.967 48.7003 389.186 48.8332C389.612 49.092 389.988 49.4173 390.249 49.849C390.67 50.544 390.489 51.1708 389.753 51.523C388.936 51.9138 388.07 51.9092 387.196 51.782C385.898 51.593 384.69 51.1742 383.677 50.3123C383.2 49.9068 382.744 49.424 382.93 48.7373C383.123 48.0283 383.781 47.8315 384.412 47.7532C384.825 47.702 384.901 47.5558 384.901 47.1765C384.89 38.8052 384.893 30.434 384.891 22.0627C384.891 21.02 384.467 20.5623 383.45 20.433C383.151 20.3948 382.854 20.3798 382.557 20.3928C382.294 20.4043 382.194 20.3363 382.192 20.045C382.185 19.0313 382.172 19.0315 383.172 18.9808C384.94 18.8912 386.708 18.8135 388.474 18.7015C388.852 18.6775 388.914 18.794 388.913 19.1373C388.901 24.2078 388.902 29.2785 388.9 34.349C388.9 34.4782 388.9 34.6073 388.9 34.8517C389.521 34.1365 390.101 33.5437 390.789 33.0677C392.584 31.8257 394.601 31.2058 396.746 30.9907C399.714 30.693 402.58 31.105 405.286 32.395C407.522 33.4607 409.291 35.0105 410.228 37.3745C410.625 38.3785 410.756 39.4258 410.754 40.5005C410.748 45.3612 410.751 50.222 410.751 55.0827C410.751 55.5188 410.781 55.9527 410.898 56.3742C411.263 57.689 412.098 58.4078 413.457 58.4933C413.956 58.5248 413.78 58.836 413.815 59.0812C413.86 59.3978 413.688 59.441 413.419 59.4405C410.313 59.4332 407.208 59.4327 404.102 59.4397C403.827 59.4403 403.659 59.3872 403.705 59.0728C403.738 58.84 403.561 58.5285 404.037 58.5003C405.287 58.4265 406.784 57.3358 406.772 55.4887C406.74 50.4032 406.768 45.3172 406.756 40.2315C406.752 38.6825 406.045 37.4357 404.94 36.4042C403.553 35.109 401.873 34.3792 400.037 34.0057C397.632 33.5167 395.273 33.6113 392.996 34.6377C391.697 35.2228 390.645 36.1297 389.924 37.3123C389.393 38.1842 389.009 39.1828 388.96 40.2547C388.933 40.8538 388.875 41.4512 388.916 42.0513Z" fill="white"/> <path d="M369.455 46.9968C370.829 46.899 371.74 48.1675 371.744 49.1866C371.749 50.4848 370.76 51.554 369.503 51.5701C368.273 51.5861 367.238 50.5803 367.208 49.3399C367.175 47.9908 368.1 47.026 369.455 46.9968Z" fill="white"/> <path d="M400.349 49.0375C400.364 48.3765 400.915 47.8374 401.559 47.8529C402.227 47.869 402.752 48.4424 402.727 49.128C402.703 49.7934 402.161 50.2979 401.493 50.2759C400.825 50.2539 400.333 49.7219 400.349 49.0375Z" fill="white"/> <path d="M387.536 56.9014C388.293 57.0026 389.05 57.1029 389.807 57.2066C389.879 57.2164 389.948 57.2644 390.018 57.2651C391.679 57.2789 393.352 57.3808 394.979 56.9616C396.902 56.4659 398.61 55.5878 399.83 53.9336C399.543 55.2006 398.783 56.1014 397.705 56.7704C396.637 57.4339 395.444 57.6763 394.22 57.7638C392.316 57.8999 390.43 57.7263 388.569 57.2961C388.381 57.2528 388.161 57.2836 388.005 57.1949C387.849 57.1068 387.665 57.1099 387.536 56.9014Z" fill="#F9F9FA"/> <path d="M388.288 55.1253C388.708 55.0681 389.074 55.1384 389.442 55.1639C391.362 55.2971 393.239 55.2018 394.915 54.0938C395.391 53.7796 395.807 53.3953 396.227 52.8706C396.041 53.7648 395.521 54.3023 394.892 54.7414C394.133 55.2708 393.249 55.4489 392.348 55.5348C391.011 55.6619 389.694 55.4856 388.381 55.2503C388.362 55.2468 388.349 55.2084 388.288 55.1253Z" fill="#F9F9FA"/> <style> @font-face { font-family: \'Quicksand\'; font-style: normal; font-weight: 700; font-display: swap; src: url(https://fonts.gstatic.com/s/quicksand/v30/6xKtdSZaM9iE8KbpRA_hK1QN.woff2) format(\'woff2\'); unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+2074, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD; } @font-face { font-family: \'Rubik Mono One\'; font-style: normal; font-weight: 400; font-display: swap; src: url(https://fonts.gstatic.com/s/rubikmonoone/v18/UqyJK8kPP3hjw6ANTdfRk9YSN983TKU.woff2) format(\'woff2\'); unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+2074, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD; }</style> <text x="25px" y="180px" font-size="14" fill="#fff"  style="font-family: \'Quicksand\', sans-serif;font-weight:700;">');
    bytes private constant SVG_ADDRESS_SUFFIX = bytes('</text> <text x="25px" y="160px" font-size="14" fill="#fff"  style="font-family: \'Rubik Mono One\', monospace;font-weight:400;">HITMAKR PROFILE</text> <text x="25px" y="230px" font-size="16" fill="#fff"  style="font-family: \'Quicksand\', sans-serif;font-weight:700;">');
    bytes private constant SVG_SUFFIX = bytes('</text> <text x="415" y="230px" font-size="14" fill="#fff" text-anchor="end" style="font-family: \'Quicksand\', sans-serif;font-weight:700;"></text> <defs> <linearGradient id="paint0_linear_170_24" x1="0" y1="0" x2="220" y2="147.5" gradientUnits="userSpaceOnUse"> <stop stop-color="#302071"/> <stop offset="1" stop-color="#191541"/> </linearGradient> <linearGradient id="paint1_linear_170_24" x1="370.232" y1="50.4785" x2="403.702" y2="50.4785" gradientUnits="userSpaceOnUse"> <stop stop-color="#7AC68F"/> <stop offset="0.5147" stop-color="#2CBCEE"/> <stop offset="1" stop-color="#6E5DA8"/> </linearGradient> </defs> </svg>');


    /**
     * @notice Constructor initializes the ERC721 token with a name and symbol.
     */
    constructor() ERC721("Hitmakr Profiles", "HMP") {}

    /**
     * @dev Internal function to check if a character is a lowercase alphanumeric character.
     * @param char The character to check.
     * @return True if the character is lowercase alphanumeric, false otherwise.
     */
    function _isValidChar(bytes1 char) private pure returns (bool) {
        return (char >= 0x30 && char <= 0x39) || 
               (char >= 0x61 && char <= 0x7A);
    }

    /**
     * @dev Internal function to validate a username.
     * @param name The username to validate.
     * @return True if the username is valid, false otherwise.
     */
    function _validateUsername(string calldata name) private pure returns (bool) {
        bytes calldata nameBytes = bytes(name);
        uint256 len = nameBytes.length;
        
        for(uint256 i; i < len;) {
            if (!_isValidChar(nameBytes[i])) return false;
            unchecked { ++i; }
        }
        return true;
    }

    /**
     * @dev Internal function to create a hash of a username.
     * @param name The username to hash.
     * @return The hash of the username.
     */
    function _createNameHash(string calldata name) private pure returns (bytes32) {
        return keccak256(bytes(name));
    }

    /**
     * @notice Registers a new profile with the given username.
     * @param name The desired username for the profile.
     * @dev Reverts if the username is invalid, already taken, or if the user already has a profile. Emits a `ProfileCreated` event upon successful registration.
     */
    function register(string calldata name) external {
        uint256 len = bytes(name).length;
        if (len < MINIMUM_LENGTH || len > MAXIMUM_LENGTH) revert InvalidUsernameLength();
        if (!_validateUsername(name)) revert InvalidUsername();
        if (_hasProfile[msg.sender]) revert AlreadyHasProfile();
        
        bytes32 nameHash = _createNameHash(name);
        if (_profileByNameHash[nameHash] != address(0)) revert UsernameTaken();

        unchecked {
            _profileCount++;
        }
        
        uint256 tokenId = _profileCount;
        _profileByNameHash[nameHash] = msg.sender;
        _hasProfile[msg.sender] = true;
        _nameByAddress[msg.sender] = name;

        _safeMint(msg.sender, tokenId);
        
        emit ProfileCreated(msg.sender, name, tokenId);
    }

    /**
     * @dev Internal function to create the SVG image data for the token URI.
     * @param username The username of the profile.
     * @param userAddress The address of the profile owner.     
     * @return A string containing the SVG image data.
     */
    function _createSVG(string memory username, address userAddress) private pure returns (string memory) {
        return string(
            abi.encodePacked(
                SVG_PREFIX,
                userAddress.toHexString(),
                SVG_ADDRESS_SUFFIX,
                username,
                SVG_SUFFIX // Removed unnecessary SVG_USERNAME_SUFFIX
            )
        );
    }

    /**
     * @notice Returns the token URI for the given token ID.
     * @param tokenId The ID of the token.
     * @dev The token URI contains the profile's metadata, including the dynamically generated SVG image.
     * @return A string representing the token URI.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        address userAddress = ownerOf(tokenId);
        string memory username = _nameByAddress[userAddress];
        
        string memory image = _createSVG(username, userAddress);
        bytes memory encodedImage = bytes(Base64.encode(bytes(image)));

        return string(
            abi.encodePacked(
                'data:application/json;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"',
                            username,
                            '","description":"Hitmakr SoulBound Profile NFT","image":"data:image/svg+xml;base64,',
                            encodedImage,
                            '"}'
                        )
                    )
                )
            )
        );
    }

    /**
     * @dev Overrides the `transferFrom` function to prevent token transfers (Soulbound).
     */
    function transferFrom(address, address, uint256) public pure override {
        revert TransferNotAllowed();
    }

    /**
     * @dev Overrides the `safeTransferFrom` function to prevent token transfers (Soulbound).
     */
    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert TransferNotAllowed();
    }

    /**
     * @dev Overrides the `approve` function to prevent token approvals.
     */
    function approve(address, uint256) public pure override {
        revert ApprovalNotAllowed();
    }

    /**
     * @dev Overrides the `setApprovalForAll` function to prevent setting approval for all tokens.
     */
    function setApprovalForAll(address, bool) public pure override {
        revert ApprovalNotAllowed();
    }
}