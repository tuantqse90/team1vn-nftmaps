// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {MapNFT} from "../src/MapNFT.sol";

contract MapNFTTest is Test {
    MapNFT nft;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    bytes photo = hex"ffd8ffe000104a46494600010100000100010000ffd9"; // JPEG giả, đủ để test lưu/đọc

    function setUp() public {
        nft = new MapNFT();
    }

    function test_MintStoresPin() public {
        vm.prank(alice);
        uint256 id = nft.mint(10_776_889, 106_700_806, MapNFT.Species.Cat, 93, unicode"Mướp", photo);

        assertEq(id, 1);
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.ownerOf(id), alice);

        (int32 lat, int32 lng, MapNFT.Species species, uint8 confidence, string memory name) = nft.pinOf(id);
        assertEq(lat, 10_776_889);
        assertEq(lng, 106_700_806);
        assertEq(uint8(species), uint8(MapNFT.Species.Cat));
        assertEq(confidence, 93);
        assertEq(name, unicode"Mướp");
        assertEq(nft.photoOf(id), photo);
    }

    function test_PhotoRoundTripsAtMaxSize() public {
        bytes memory big = new bytes(nft.MAX_PHOTO_BYTES());
        big[0] = 0xff;
        big[big.length - 1] = 0xd9;

        vm.prank(alice);
        uint256 id = nft.mint(0, 0, MapNFT.Species.Dog, 80, "Lu", big);
        assertEq(keccak256(nft.photoOf(id)), keccak256(big));
    }

    function test_TokenURIIsOnChainJSONWithImage() public {
        vm.prank(alice);
        uint256 id = nft.mint(-33_856_784, 151_215_297, MapNFT.Species.Dog, 88, 'Bo "the dog"', photo);

        string memory expectedJSON = string.concat(
            '{"name":"Bo \\"the dog\\"","description":"Dog spotted at -33.856784, 151.215297 - minted with NFT Maps on Avalanche.",',
            '"image":"data:image/jpeg;base64,',
            Base64.encode(photo),
            '","attributes":[{"trait_type":"Species","value":"Dog"},{"trait_type":"Confidence","value":88,"max_value":100},',
            '{"trait_type":"Location","value":"-33.856784, 151.215297"}]}'
        );
        assertEq(nft.tokenURI(id), string.concat("data:application/json;base64,", Base64.encode(bytes(expectedJSON))));
    }

    function test_DecimalPadsSmallCoordinates() public {
        vm.prank(alice);
        uint256 id = nft.mint(-500, 7, MapNFT.Species.Cat, 50, "x", photo);
        string memory uri = nft.tokenURI(id);
        string memory expectedJSON = string.concat(
            '{"name":"x","description":"Cat spotted at -0.000500, 0.000007 - minted with NFT Maps on Avalanche.",',
            '"image":"data:image/jpeg;base64,',
            Base64.encode(photo),
            '","attributes":[{"trait_type":"Species","value":"Cat"},{"trait_type":"Confidence","value":50,"max_value":100},',
            '{"trait_type":"Location","value":"-0.000500, 0.000007"}]}'
        );
        assertEq(uri, string.concat("data:application/json;base64,", Base64.encode(bytes(expectedJSON))));
    }

    function test_RevertWhen_InputsInvalid() public {
        vm.expectRevert(MapNFT.InvalidCoordinates.selector);
        nft.mint(90_000_001, 0, MapNFT.Species.Cat, 90, "x", photo);

        vm.expectRevert(MapNFT.InvalidCoordinates.selector);
        nft.mint(0, -180_000_001, MapNFT.Species.Cat, 90, "x", photo);

        vm.expectRevert(MapNFT.InvalidSpecies.selector);
        nft.mint(0, 0, MapNFT.Species.None, 90, "x", photo);

        vm.expectRevert(MapNFT.InvalidConfidence.selector);
        nft.mint(0, 0, MapNFT.Species.Cat, 101, "x", photo);

        vm.expectRevert(MapNFT.InvalidName.selector);
        nft.mint(0, 0, MapNFT.Species.Cat, 90, "", photo);

        vm.expectRevert(MapNFT.InvalidName.selector);
        nft.mint(0, 0, MapNFT.Species.Cat, 90, string(new bytes(65)), photo);

        vm.expectRevert(MapNFT.InvalidPhoto.selector);
        nft.mint(0, 0, MapNFT.Species.Cat, 90, "x", "");

        uint256 tooBig = nft.MAX_PHOTO_BYTES() + 1;
        vm.expectRevert(MapNFT.InvalidPhoto.selector);
        nft.mint(0, 0, MapNFT.Species.Cat, 90, "x", new bytes(tooBig));
    }

    function test_RevertWhen_SpeciesOutOfEnumRange() public {
        (bool ok,) = address(nft)
            .call(abi.encodeWithSignature("mint(int32,int32,uint8,uint8,string,bytes)", 0, 0, 3, 90, "x", photo));
        assertFalse(ok);
    }

    function test_RevertWhen_ReadingNonexistentToken() public {
        bytes memory err = abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 42);
        vm.expectRevert(err);
        nft.pinOf(42);
        vm.expectRevert(err);
        nft.photoOf(42);
        vm.expectRevert(err);
        nft.tokenURI(42);
    }

    function test_DeployerIsModerator() public view {
        assertEq(nft.owner(), address(this));
    }

    function test_ModeratorHidesAndUnhidesPet() public {
        vm.prank(alice);
        uint256 id = nft.mint(10_776_889, 106_700_806, MapNFT.Species.Cat, 93, unicode"Mướp", photo);
        assertFalse(nft.isHidden(id));
        string memory uriBefore = nft.tokenURI(id);

        vm.expectEmit(address(nft));
        emit MapNFT.PetHiddenChanged(id, true);
        nft.setHidden(id, true);
        assertTrue(nft.isHidden(id));

        // Chỉ là cờ: dữ liệu ghim, ảnh, tokenURI và quyền chuyển nhượng không đổi
        (int32 lat, int32 lng, MapNFT.Species species, uint8 confidence, string memory name) = nft.pinOf(id);
        assertEq(lat, 10_776_889);
        assertEq(lng, 106_700_806);
        assertEq(uint8(species), uint8(MapNFT.Species.Cat));
        assertEq(confidence, 93);
        assertEq(name, unicode"Mướp");
        assertEq(nft.photoOf(id), photo);
        assertEq(nft.tokenURI(id), uriBefore);
        vm.prank(alice);
        nft.transferFrom(alice, bob, id);
        assertEq(nft.ownerOf(id), bob);
        assertTrue(nft.isHidden(id));

        vm.expectEmit(address(nft));
        emit MapNFT.PetHiddenChanged(id, false);
        nft.setHidden(id, false);
        assertFalse(nft.isHidden(id));
    }

    function test_RevertWhen_NonOwnerSetsHidden() public {
        vm.prank(alice);
        uint256 id = nft.mint(0, 0, MapNFT.Species.Dog, 80, "Lu", photo);

        // Kể cả chủ NFT cũng không tự ẩn được — chỉ moderator
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nft.setHidden(id, true);
        assertFalse(nft.isHidden(id));
    }

    function test_RevertWhen_HidingNonexistentToken() public {
        bytes memory err = abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 42);
        vm.expectRevert(err);
        nft.setHidden(42, true);
        vm.expectRevert(err);
        nft.isHidden(42);
    }

    function testFuzz_MintValidCoordinates(int32 lat, int32 lng) public {
        lat = int32(bound(lat, -90e6, 90e6));
        lng = int32(bound(lng, -180e6, 180e6));

        vm.prank(alice);
        uint256 id = nft.mint(lat, lng, MapNFT.Species.Dog, 70, "x", photo);
        (int32 gotLat, int32 gotLng,,,) = nft.pinOf(id);
        assertEq(gotLat, lat);
        assertEq(gotLng, lng);
    }
}
