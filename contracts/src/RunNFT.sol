// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SSTORE2} from "./SSTORE2.sol";

/// @title RunNFT — mỗi NFT là một buổi chạy đã hoàn thành, lưu trọn on-chain
/// @notice Riêng tư: `route` CHỈ là hình dạng đường chạy. App chuẩn hoá track GPS vào lưới 256×256 rồi gửi các cặp
///         uint8 (x0,y0,x1,y1,…), y tăng xuống dưới như SVG — không có toạ độ tuyệt đối nào lên chain.
///         `areaLat/areaLng` là vùng thô ~1 km = độ * 100 làm tròn (10.78 -> 1078), dùng cho bảng xếp hạng theo khu vực.
/// @dev tokenURI dựng JSON + ảnh SVG ngay trong contract, không cần IPFS.
contract RunNFT is ERC721 {
    using Strings for uint256;

    /// @dev 2 slot: [route 20 | distance 4 | steps 4 | duration 4] [finishedAt 8 | areaLat 2 | areaLng 2]
    struct Run {
        address route; // con trỏ SSTORE2 tới các cặp (x, y) uint8
        uint32 distanceMeters;
        uint32 steps;
        uint32 durationSeconds;
        uint64 finishedAt;
        int16 areaLat;
        int16 areaLng;
    }

    uint256 public constant MAX_NAME_BYTES = 64;
    uint256 public constant MIN_ROUTE_BYTES = 4; // 2 điểm
    uint256 public constant MAX_ROUTE_BYTES = 2000; // 1000 điểm
    uint256 public constant MIN_DISTANCE_METERS = 100;
    uint256 public constant MAX_DISTANCE_METERS = 100_000;
    /// @dev Chạy bộ nhanh hơn 12 m/s (~43 km/h) là không thể.
    uint256 public constant MAX_SPEED_METERS_PER_SECOND = 12;

    uint256 public totalSupply;
    mapping(uint256 tokenId => Run) private _runs;
    mapping(uint256 tokenId => string) private _names;

    event RunMinted(
        uint256 indexed tokenId, address indexed owner, uint32 distanceMeters, uint32 steps, uint32 durationSeconds
    );

    error InvalidName();
    error InvalidRoute();
    error InvalidDistance();
    error InvalidDuration();
    error ImplausibleRun();
    error InvalidArea();

    constructor() ERC721("PawRun Runs", "PAWRUN") {}

    /// @notice Mint buổi chạy vừa xong cho người gọi. Token id bắt đầu từ 1; `finishedAt` = thời điểm mint.
    function mintRun(
        uint32 distanceMeters,
        uint32 steps,
        uint32 durationSeconds,
        int16 areaLat,
        int16 areaLng,
        string calldata name,
        bytes calldata route
    ) external returns (uint256 tokenId) {
        if (bytes(name).length == 0 || bytes(name).length > MAX_NAME_BYTES) revert InvalidName();
        if (route.length < MIN_ROUTE_BYTES || route.length > MAX_ROUTE_BYTES || route.length % 2 != 0) {
            revert InvalidRoute();
        }
        if (distanceMeters < MIN_DISTANCE_METERS || distanceMeters > MAX_DISTANCE_METERS) revert InvalidDistance();
        if (durationSeconds == 0) revert InvalidDuration();
        if (distanceMeters > uint256(durationSeconds) * MAX_SPEED_METERS_PER_SECOND) revert ImplausibleRun();
        if (areaLat < -9000 || areaLat > 9000 || areaLng < -18000 || areaLng > 18000) revert InvalidArea();

        tokenId = ++totalSupply;
        _runs[tokenId] = Run({
            route: SSTORE2.write(route),
            distanceMeters: distanceMeters,
            steps: steps,
            durationSeconds: durationSeconds,
            finishedAt: uint64(block.timestamp),
            areaLat: areaLat,
            areaLng: areaLng
        });
        _names[tokenId] = name;
        _safeMint(msg.sender, tokenId);

        emit RunMinted(tokenId, msg.sender, distanceMeters, steps, durationSeconds);
    }

    /// @notice Số liệu của buổi chạy, trừ hình đường chạy (lấy riêng bằng `routeOf`).
    function runOf(uint256 tokenId)
        external
        view
        returns (
            uint32 distanceMeters,
            uint32 steps,
            uint32 durationSeconds,
            uint64 finishedAt,
            int16 areaLat,
            int16 areaLng,
            string memory name
        )
    {
        _requireOwned(tokenId);
        Run storage run = _runs[tokenId];
        distanceMeters = run.distanceMeters;
        steps = run.steps;
        durationSeconds = run.durationSeconds;
        finishedAt = run.finishedAt;
        areaLat = run.areaLat;
        areaLng = run.areaLng;
        name = _names[tokenId];
    }

    /// @notice Hình đường chạy: các cặp (x, y) uint8 trong lưới 256×256, đúng như lúc mint.
    function routeOf(uint256 tokenId) public view returns (bytes memory) {
        _requireOwned(tokenId);
        return SSTORE2.read(_runs[tokenId].route);
    }

    /// @notice Metadata chuẩn ERC-721 dạng data URI, ảnh SVG nhúng sẵn — ví và marketplace đọc trực tiếp được.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        bytes memory route = routeOf(tokenId);
        Run memory run = _runs[tokenId];
        string memory json = string.concat(
            '{"name":"',
            Strings.escapeJSON(_names[tokenId]),
            '","description":"',
            uint256(run.distanceMeters).toString(),
            " m run, ",
            uint256(run.steps).toString(),
            " steps in ",
            uint256(run.durationSeconds).toString(),
            ' s - route shape only, no GPS coordinates. Minted with PawRun on Avalanche.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(_svg(route))),
            '","attributes":',
            _attributes(run),
            "}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _svg(bytes memory route) private pure returns (string memory) {
        string memory startX = uint256(uint8(route[0])).toString();
        string memory startY = uint256(uint8(route[1])).toString();
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="#FBF7F0"/>',
            '<polyline points="',
            string(_points(route)),
            '" fill="none" stroke="#F2690D" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>',
            '<circle cx="',
            startX,
            '" cy="',
            startY,
            '" r="5" fill="#FFFFFF" stroke="#F2690D" stroke-width="3"/></svg>'
        );
    }

    /// @dev (x0,y0,x1,y1,…) -> "x0,y0 x1,y1 …". Ghi thẳng vào một buffer cấp sẵn (tối đa "255,255 " = 4 byte cho
    ///      mỗi byte route); string.concat trong vòng lặp tốn bộ nhớ O(n²) và nổ gas với 1000 điểm.
    function _points(bytes memory route) private pure returns (bytes memory out) {
        out = new bytes(route.length * 4);
        assembly ("memory-safe") {
            let start := add(route, 0x20)
            let end := add(start, mload(route))
            let dst := add(out, 0x20)
            for { let src := start } lt(src, end) { src := add(src, 1) } {
                let v := byte(0, mload(src))
                if gt(v, 99) {
                    mstore8(dst, add(48, div(v, 100)))
                    dst := add(dst, 1)
                }
                if gt(v, 9) {
                    mstore8(dst, add(48, mod(div(v, 10), 10)))
                    dst := add(dst, 1)
                }
                mstore8(dst, add(48, mod(v, 10)))
                // sau x là ",", sau y là " "
                switch and(sub(src, start), 1)
                case 0 { mstore8(add(dst, 1), 0x2c) }
                default { mstore8(add(dst, 1), 0x20) }
                dst := add(dst, 2)
            }
            // độ dài thật, bỏ dấu cách thừa ở cuối (route luôn ≥ 4 byte nên không âm)
            mstore(out, sub(sub(dst, add(out, 0x20)), 1))
        }
    }

    function _attributes(Run memory run) private pure returns (string memory) {
        return string.concat(
            '[{"trait_type":"Distance (m)","value":',
            uint256(run.distanceMeters).toString(),
            '},{"trait_type":"Steps","value":',
            uint256(run.steps).toString(),
            '},{"trait_type":"Duration (s)","value":',
            uint256(run.durationSeconds).toString(),
            '},{"trait_type":"Area","value":"',
            _decimal(run.areaLat),
            ", ",
            _decimal(run.areaLng),
            '"}]'
        );
    }

    /// @dev 1078 -> "10.78", 10670 -> "106.70", -5 -> "-0.05"
    function _decimal(int16 value) private pure returns (string memory) {
        uint256 abs = uint256(value < 0 ? -int256(value) : int256(value));
        uint256 fraction = abs % 100;
        return
            string.concat(value < 0 ? "-" : "", (abs / 100).toString(), fraction < 10 ? ".0" : ".", fraction.toString());
    }
}
