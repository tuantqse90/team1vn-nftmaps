// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {RunNFT} from "../src/RunNFT.sol";

contract RunNFTTest is Test {
    RunNFT nft;
    address alice = makeAddr("alice");
    bytes route = hex"0010203040506070"; // 4 điểm: (0,16) (32,48) (64,80) (96,112)

    string constant SVG_HEAD =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><rect width="256" height="256" fill="#FBF7F0"/><polyline points="';
    string constant SVG_LINE_TAIL =
        '" fill="none" stroke="#F2690D" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>';

    function setUp() public {
        nft = new RunNFT();
        vm.warp(1_762_950_000);
    }

    function _mint(bytes memory r) internal returns (uint256) {
        vm.prank(alice);
        return nft.mintRun(3210, 4173, 1192, 1078, 10_670, unicode"Vòng Tao Đàn", r);
    }

    function test_MintStoresRun() public {
        vm.expectEmit(address(nft));
        emit RunNFT.RunMinted(1, alice, 3210, 4173, 1192);
        uint256 id = _mint(route);

        assertEq(id, 1);
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.ownerOf(id), alice);
        assertEq(nft.name(), "PawRun Runs");
        assertEq(nft.symbol(), "PAWRUN");

        (
            uint32 distance,
            uint32 steps,
            uint32 duration,
            uint64 finishedAt,
            int16 areaLat,
            int16 areaLng,
            string memory name
        ) = nft.runOf(id);
        assertEq(distance, 3210);
        assertEq(steps, 4173);
        assertEq(duration, 1192);
        assertEq(finishedAt, 1_762_950_000);
        assertEq(areaLat, 1078);
        assertEq(areaLng, 10_670);
        assertEq(name, unicode"Vòng Tao Đàn");
        assertEq(nft.routeOf(id), route);

        assertEq(_mint(route), 2);
        assertEq(nft.totalSupply(), 2);
    }

    function test_StatsPackIntoTwoSlots() public {
        uint256 id = _mint(route);
        // _runs nằm ở slot 7 (sau 6 slot của ERC721 và totalSupply); slot thứ 3 của struct phải trống
        bytes32 base = keccak256(abi.encode(id, uint256(7)));
        assertTrue(vm.load(address(nft), base) != bytes32(0));
        assertTrue(vm.load(address(nft), bytes32(uint256(base) + 1)) != bytes32(0));
        assertEq(vm.load(address(nft), bytes32(uint256(base) + 2)), bytes32(0));
    }

    function test_TokenURIIsOnChainJSONWithSVG() public {
        vm.prank(alice);
        uint256 id = nft.mintRun(3210, 4173, 1192, -5, -18_000, 'Run "fast"', route);

        string memory svg = string.concat(
            SVG_HEAD,
            "0,16 32,48 64,80 96,112",
            SVG_LINE_TAIL,
            '<circle cx="0" cy="16" r="5" fill="#FFFFFF" stroke="#F2690D" stroke-width="3"/></svg>'
        );
        string memory expectedJSON = string.concat(
            '{"name":"Run \\"fast\\"","description":"3210 m run, 4173 steps in 1192 s - route shape only, no GPS coordinates. Minted with PawRun on Avalanche.",',
            '"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '","attributes":[{"trait_type":"Distance (m)","value":3210},{"trait_type":"Steps","value":4173},',
            '{"trait_type":"Duration (s)","value":1192},{"trait_type":"Area","value":"-0.05, -180.00"}]}'
        );
        string memory uri = nft.tokenURI(id);
        assertEq(uri, string.concat("data:application/json;base64,", Base64.encode(bytes(expectedJSON))));

        // Giải mã ngược như ví/marketplace sẽ làm
        string memory json = _decodeJSON(uri);
        assertEq(vm.parseJsonString(json, ".name"), 'Run "fast"');
        assertEq(vm.parseJsonString(json, ".attributes[0].trait_type"), "Distance (m)");
        assertEq(vm.parseJsonUint(json, ".attributes[0].value"), 3210);
        assertEq(vm.parseJsonString(json, ".attributes[1].trait_type"), "Steps");
        assertEq(vm.parseJsonUint(json, ".attributes[1].value"), 4173);
        assertEq(vm.parseJsonString(json, ".attributes[2].trait_type"), "Duration (s)");
        assertEq(vm.parseJsonUint(json, ".attributes[2].value"), 1192);
        assertEq(vm.parseJsonString(json, ".attributes[3].trait_type"), "Area");
        assertEq(vm.parseJsonString(json, ".attributes[3].value"), "-0.05, -180.00");
        assertEq(_decodeSVG(json), svg);
    }

    function test_TokenURIUnicodeNameAndArea() public {
        uint256 id = _mint(hex"ff00090a6364");
        string memory json = _decodeJSON(nft.tokenURI(id));
        assertEq(vm.parseJsonString(json, ".name"), unicode"Vòng Tao Đàn");
        assertEq(vm.parseJsonString(json, ".attributes[3].value"), "10.78, 106.70");
        assertTrue(vm.contains(_decodeSVG(json), '<polyline points="255,0 9,10 99,100"'));
        assertTrue(vm.contains(_decodeSVG(json), '<circle cx="255" cy="0"'));
    }

    /// @dev Route tối đa 1000 điểm, toàn số 3 chữ số (SVG dài nhất có thể): mint + tokenURI phải dư sức trong 30M gas.
    function test_MaxSizeRoute() public {
        bytes memory big = new bytes(nft.MAX_ROUTE_BYTES());
        for (uint256 i; i < big.length; ++i) {
            big[i] = bytes1(uint8(100 + (i * 37) % 156));
        }

        vm.prank(alice);
        uint256 gasBefore = gasleft();
        uint256 id = nft.mintRun(42_195, 52_000, 10_800, 1078, 10_670, "Marathon", big);
        uint256 mintGas = gasBefore - gasleft();
        assertEq(keccak256(nft.routeOf(id)), keccak256(big));

        gasBefore = gasleft();
        string memory uri = nft.tokenURI(id);
        uint256 uriGas = gasBefore - gasleft();

        console.log("mintRun gas (1000 points):", mintGas);
        console.log("tokenURI gas (1000 points):", uriGas);
        console.log("tokenURI length (bytes):", bytes(uri).length);
        assertLt(mintGas, 1_000_000);
        assertLt(uriGas, 5_000_000);

        string memory svg = _decodeSVG(_decodeJSON(uri));
        assertEq(svg, _referenceSVG(big));
    }

    function testFuzz_RouteRoundTripsAndRendersLikeReference(bytes memory r) public {
        if (r.length > 400) {
            assembly { mstore(r, 400) } // giữ fuzz nhanh; case 2000 byte đã có test riêng
        }
        if (r.length % 2 == 1) {
            assembly { mstore(r, sub(mload(r), 1)) }
        }
        vm.assume(r.length >= 4);

        uint256 id = _mint(r);
        assertEq(nft.routeOf(id), r);
        assertEq(_decodeSVG(_decodeJSON(nft.tokenURI(id))), _referenceSVG(r));
    }

    function testFuzz_AreaFormatting(int16 lat, int16 lng) public {
        lat = int16(bound(lat, -9000, 9000));
        lng = int16(bound(lng, -18_000, 18_000));
        vm.prank(alice);
        uint256 id = nft.mintRun(1000, 1200, 600, lat, lng, "x", route);
        string memory json = _decodeJSON(nft.tokenURI(id));
        assertEq(
            vm.parseJsonString(json, ".attributes[3].value"),
            string.concat(_referenceDecimal(lat), ", ", _referenceDecimal(lng))
        );
    }

    function test_BoundaryValuesAccepted() public {
        vm.startPrank(alice);
        nft.mintRun(100, 0, 9, 9000, 18_000, string(new bytes(64)), new bytes(4)); // 100 m / 9 s = 11.1 m/s
        nft.mintRun(100_000, 0, 8334, -9000, -18_000, "x", new bytes(2000)); // đúng 12 m/s * 8334 s ≥ 100_000
        nft.mintRun(1200, 0, 100, 0, 0, "x", route); // đúng 12 m/s
        nft.mintRun(100, type(uint32).max, type(uint32).max, 0, 0, "x", route); // không tràn số khi nhân
        vm.stopPrank();
        assertEq(nft.totalSupply(), 4);
    }

    function test_RevertWhen_InputsInvalid() public {
        vm.expectRevert(RunNFT.InvalidName.selector);
        nft.mintRun(3210, 4173, 1192, 0, 0, "", route);

        vm.expectRevert(RunNFT.InvalidName.selector);
        nft.mintRun(3210, 4173, 1192, 0, 0, string(new bytes(65)), route);

        vm.expectRevert(RunNFT.InvalidRoute.selector);
        nft.mintRun(3210, 4173, 1192, 0, 0, "x", "");

        vm.expectRevert(RunNFT.InvalidRoute.selector);
        nft.mintRun(3210, 4173, 1192, 0, 0, "x", hex"0102"); // 1 điểm

        vm.expectRevert(RunNFT.InvalidRoute.selector);
        nft.mintRun(3210, 4173, 1192, 0, 0, "x", hex"0102030405"); // lẻ

        vm.expectRevert(RunNFT.InvalidRoute.selector);
        nft.mintRun(3210, 4173, 1192, 0, 0, "x", new bytes(2002));

        vm.expectRevert(RunNFT.InvalidRoute.selector);
        nft.mintRun(3210, 4173, 1192, 0, 0, "x", new bytes(2001));

        vm.expectRevert(RunNFT.InvalidDistance.selector);
        nft.mintRun(99, 4173, 1192, 0, 0, "x", route);

        vm.expectRevert(RunNFT.InvalidDistance.selector);
        nft.mintRun(100_001, 4173, 100_000, 0, 0, "x", route);

        vm.expectRevert(RunNFT.InvalidDuration.selector);
        nft.mintRun(3210, 4173, 0, 0, 0, "x", route);

        vm.expectRevert(RunNFT.ImplausibleRun.selector);
        nft.mintRun(1201, 4173, 100, 0, 0, "x", route); // 12.01 m/s

        vm.expectRevert(RunNFT.InvalidArea.selector);
        nft.mintRun(3210, 4173, 1192, 9001, 0, "x", route);

        vm.expectRevert(RunNFT.InvalidArea.selector);
        nft.mintRun(3210, 4173, 1192, -9001, 0, "x", route);

        vm.expectRevert(RunNFT.InvalidArea.selector);
        nft.mintRun(3210, 4173, 1192, 0, 18_001, "x", route);

        vm.expectRevert(RunNFT.InvalidArea.selector);
        nft.mintRun(3210, 4173, 1192, 0, -18_001, "x", route);

        assertEq(nft.totalSupply(), 0);
    }

    function test_RevertWhen_ReadingNonexistentToken() public {
        bytes memory err = abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 42);
        vm.expectRevert(err);
        nft.runOf(42);
        vm.expectRevert(err);
        nft.routeOf(42);
        vm.expectRevert(err);
        nft.tokenURI(42);
    }

    // ---- helpers ----

    function _decodeJSON(string memory uri) internal pure returns (string memory) {
        string memory prefix = "data:application/json;base64,";
        return string(Base64.decode(_stripPrefix(uri, prefix)));
    }

    function _decodeSVG(string memory json) internal pure returns (string memory) {
        string memory image = vm.parseJsonString(json, ".image");
        return string(Base64.decode(_stripPrefix(image, "data:image/svg+xml;base64,")));
    }

    function _stripPrefix(string memory s, string memory prefix) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory p = bytes(prefix);
        require(b.length >= p.length, "short");
        for (uint256 i; i < p.length; ++i) {
            require(b[i] == p[i], "bad prefix");
        }
        bytes memory rest = new bytes(b.length - p.length);
        for (uint256 i; i < rest.length; ++i) {
            rest[i] = b[i + p.length];
        }
        return string(rest);
    }

    /// @dev Bản dựng SVG viết kiểu "ngây thơ" để đối chiếu với vòng lặp assembly trong contract.
    function _referenceSVG(bytes memory r) internal pure returns (string memory) {
        string memory points;
        for (uint256 i; i < r.length; i += 2) {
            points = string.concat(
                points, i == 0 ? "" : " ", Strings.toString(uint8(r[i])), ",", Strings.toString(uint8(r[i + 1]))
            );
        }
        return string.concat(
            SVG_HEAD,
            points,
            SVG_LINE_TAIL,
            '<circle cx="',
            Strings.toString(uint8(r[0])),
            '" cy="',
            Strings.toString(uint8(r[1])),
            '" r="5" fill="#FFFFFF" stroke="#F2690D" stroke-width="3"/></svg>'
        );
    }

    function _referenceDecimal(int16 v) internal pure returns (string memory) {
        uint256 abs = v < 0 ? uint256(-int256(v)) : uint256(int256(v));
        string memory frac = Strings.toString(abs % 100);
        return string.concat(v < 0 ? "-" : "", Strings.toString(abs / 100), abs % 100 < 10 ? ".0" : ".", frac);
    }
}
