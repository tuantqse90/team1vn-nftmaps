// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SSTORE2} from "./SSTORE2.sol";

/// @title MapNFT — mỗi NFT là ảnh một bé chó/mèo, gắn với toạ độ nơi bắt gặp
/// @notice Toạ độ lưu dạng số nguyên = độ * 1e6 (10.776889 -> 10776889).
///         Ảnh JPEG nhỏ lưu on-chain (SSTORE2); tokenURI dựng JSON + ảnh ngay trong contract, không cần IPFS.
/// @dev App nhận diện chó/mèo bằng model chạy trên máy (Apple Vision) rồi mới cho mint.
///      Contract chỉ ghi lại kết quả, không tự kiểm chứng được nội dung ảnh.
///      Owner (= người deploy) là moderator: có thể ẩn một bé khỏi bản đồ trong app khi chủ thật yêu cầu.
contract MapNFT is ERC721, Ownable {
    using Strings for uint256;

    enum Species {
        None,
        Cat,
        Dog
    }

    /// @dev Gói vừa 1 slot: 4 + 4 + 1 + 1 + 20 + 1 byte.
    struct Pin {
        int32 lat;
        int32 lng;
        Species species;
        uint8 confidence; // % độ tin cậy của model, 0..100
        address photo; // con trỏ SSTORE2 tới JPEG
        bool hidden; // moderator ẩn khỏi bản đồ — chỉ là cờ cho app, NFT vẫn nguyên vẹn
    }

    uint256 public constant MAX_NAME_BYTES = 64;
    uint256 public constant MAX_PHOTO_BYTES = 24_000;

    uint256 public totalSupply;
    mapping(uint256 tokenId => Pin) private _pins;
    mapping(uint256 tokenId => string) private _names;

    event PetMinted(uint256 indexed tokenId, address indexed owner, Species species, int32 lat, int32 lng);
    event PetHiddenChanged(uint256 indexed tokenId, bool hidden);

    error InvalidCoordinates();
    error InvalidSpecies();
    error InvalidConfidence();
    error InvalidName();
    error InvalidPhoto();

    constructor() ERC721("NFT Maps", "NFTMAP") Ownable(msg.sender) {}

    /// @notice Mint NFT ảnh chó/mèo tại (lat, lng) cho người gọi. Token id bắt đầu từ 1.
    function mint(int32 lat, int32 lng, Species species, uint8 confidence, string calldata name, bytes calldata photo)
        external
        returns (uint256 tokenId)
    {
        if (lat < -90e6 || lat > 90e6 || lng < -180e6 || lng > 180e6) revert InvalidCoordinates();
        if (species == Species.None) revert InvalidSpecies();
        if (confidence > 100) revert InvalidConfidence();
        if (bytes(name).length == 0 || bytes(name).length > MAX_NAME_BYTES) revert InvalidName();
        if (photo.length == 0 || photo.length > MAX_PHOTO_BYTES) revert InvalidPhoto();

        tokenId = ++totalSupply;
        _pins[tokenId] = Pin(lat, lng, species, confidence, SSTORE2.write(photo), false);
        _names[tokenId] = name;
        _safeMint(msg.sender, tokenId);

        emit PetMinted(tokenId, msg.sender, species, lat, lng);
    }

    /// @notice Moderator ẩn/hiện một bé trên bản đồ của app. Không burn, không chặn chuyển nhượng hay tokenURI.
    /// @dev Ghi vào slot `Pin` sẵn có (nonzero -> nonzero), rẻ hơn hẳn một mapping riêng.
    function setHidden(uint256 tokenId, bool hidden) external onlyOwner {
        _requireOwned(tokenId);
        _pins[tokenId].hidden = hidden;
        emit PetHiddenChanged(tokenId, hidden);
    }

    /// @notice App đọc cờ này để bỏ ghim khỏi bản đồ.
    function isHidden(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return _pins[tokenId].hidden;
    }

    /// @notice Mọi thứ bản đồ cần cho một ghim, trừ ảnh (ảnh lấy riêng bằng `photoOf` khi mở chi tiết).
    function pinOf(uint256 tokenId)
        external
        view
        returns (int32 lat, int32 lng, Species species, uint8 confidence, string memory name)
    {
        _requireOwned(tokenId);
        Pin memory pin = _pins[tokenId];
        return (pin.lat, pin.lng, pin.species, pin.confidence, _names[tokenId]);
    }

    /// @notice Ảnh JPEG gốc của token.
    function photoOf(uint256 tokenId) public view returns (bytes memory) {
        _requireOwned(tokenId);
        return SSTORE2.read(_pins[tokenId].photo);
    }

    /// @notice Metadata chuẩn ERC-721 dạng data URI, ảnh nhúng sẵn — ví và marketplace đọc trực tiếp được.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        Pin memory pin = _pins[tokenId];
        string memory image = string.concat("data:image/jpeg;base64,", Base64.encode(photoOf(tokenId)));
        string memory json = string.concat(
            '{"name":"',
            Strings.escapeJSON(_names[tokenId]),
            '","description":"',
            _speciesName(pin.species),
            " spotted at ",
            _coordinates(pin),
            ' - minted with NFT Maps on Avalanche.","image":"',
            image,
            '","attributes":',
            _attributes(pin),
            "}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _attributes(Pin memory pin) private pure returns (string memory) {
        return string.concat(
            '[{"trait_type":"Species","value":"',
            _speciesName(pin.species),
            '"},{"trait_type":"Confidence","value":',
            uint256(pin.confidence).toString(),
            ',"max_value":100},{"trait_type":"Location","value":"',
            _coordinates(pin),
            '"}]'
        );
    }

    function _speciesName(Species species) private pure returns (string memory) {
        return species == Species.Cat ? "Cat" : "Dog";
    }

    function _coordinates(Pin memory pin) private pure returns (string memory) {
        return string.concat(_decimal(pin.lat), ", ", _decimal(pin.lng));
    }

    /// @dev 10776889 -> "10.776889", -500 -> "-0.000500"
    function _decimal(int32 value) private pure returns (string memory) {
        uint256 abs = uint256(value < 0 ? -int256(value) : int256(value));
        bytes memory fraction = bytes((abs % 1e6).toString());
        bytes memory padding = new bytes(6 - fraction.length);
        for (uint256 i; i < padding.length; ++i) {
            padding[i] = "0";
        }
        return string.concat(value < 0 ? "-" : "", (abs / 1e6).toString(), ".", string(padding), string(fraction));
    }
}
