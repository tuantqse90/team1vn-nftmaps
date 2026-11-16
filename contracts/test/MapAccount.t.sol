// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {Account as OZAccount} from "@openzeppelin/contracts/account/Account.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {MapAccount} from "../src/MapAccount.sol";
import {MapAccountFactory} from "../src/MapAccountFactory.sol";
import {MapNFT} from "../src/MapNFT.sol";

contract MapAccountTest is Test {
    address constant ENTRYPOINT = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

    MapNFT nft;
    MapAccountFactory factory;
    address owner;
    uint256 ownerKey;

    function setUp() public {
        nft = new MapNFT();
        factory = new MapAccountFactory();
        (owner, ownerKey) = makeAddrAndKey("owner");
    }

    function test_FactoryCreatesAccountAtPredictedAddress() public {
        address predicted = factory.getAddress(owner);
        assertEq(predicted.code.length, 0);

        address account = factory.createAccount(owner);
        assertEq(account, predicted);
        assertGt(account.code.length, 0);
        assertEq(MapAccount(payable(account)).signer(), owner);
        assertEq(address(MapAccount(payable(account)).entryPoint()), ENTRYPOINT);

        // Gọi lại không tạo mới, trả về đúng địa chỉ cũ
        assertEq(factory.createAccount(owner), account);
    }

    function test_RevertWhen_InitializingTwice() public {
        MapAccount account = MapAccount(payable(factory.createAccount(owner)));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        account.initialize(makeAddr("attacker"));

        MapAccount implementation = MapAccount(payable(factory.implementation()));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(owner);
    }

    function test_ValidateUserOpAcceptsOnlyOwnerSignature() public {
        MapAccount account = MapAccount(payable(factory.createAccount(owner)));
        bytes32 userOpHash = keccak256("user op");
        PackedUserOperation memory op;
        op.sender = address(account);

        op.signature = _sign(ownerKey, userOpHash);
        vm.prank(ENTRYPOINT);
        assertEq(account.validateUserOp(op, userOpHash, 0), ERC4337Utils.SIG_VALIDATION_SUCCESS);

        (, uint256 strangerKey) = makeAddrAndKey("stranger");
        op.signature = _sign(strangerKey, userOpHash);
        vm.prank(ENTRYPOINT);
        assertEq(account.validateUserOp(op, userOpHash, 0), ERC4337Utils.SIG_VALIDATION_FAILED);
    }

    function test_ExecuteMintsNftIntoAccount() public {
        MapAccount account = MapAccount(payable(factory.createAccount(owner)));

        vm.prank(ENTRYPOINT);
        account.execute(
            address(nft),
            0,
            abi.encodeCall(MapNFT.mint, (10_776_889, 106_700_806, MapNFT.Species.Cat, 90, "Muop", hex"ffd8ffd9"))
        );

        assertEq(nft.ownerOf(1), address(account));
    }

    function test_RevertWhen_StrangerCallsExecute() public {
        MapAccount account = MapAccount(payable(factory.createAccount(owner)));
        address stranger = makeAddr("stranger");

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(OZAccount.AccountUnauthorized.selector, stranger));
        account.execute(
            address(nft), 0, abi.encodeCall(MapNFT.mint, (0, 0, MapNFT.Species.Dog, 90, "x", hex"ffd8ffd9"))
        );
    }

    function _sign(uint256 key, bytes32 hash) private pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, hash);
        return abi.encodePacked(r, s, v);
    }
}
