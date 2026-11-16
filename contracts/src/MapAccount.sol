// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Account} from "@openzeppelin/contracts/account/Account.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SignerECDSA} from "@openzeppelin/contracts/utils/cryptography/signers/SignerECDSA.sol";

/// @title MapAccount — smart account ERC-4337 một chủ (khoá ECDSA sinh trong app)
/// @notice Triển khai dạng clone qua MapAccountFactory; nhận được NFT (ERC721Holder).
contract MapAccount is Account, SignerECDSA, ERC721Holder, Initializable {
    constructor() SignerECDSA(address(0)) {
        _disableInitializers();
    }

    function initialize(address owner) external initializer {
        _setSigner(owner);
    }

    /// @dev EntryPoint v0.8 — Pimlico hỗ trợ bundler + paymaster cho bản này trên Fuji.
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return ERC4337Utils.ENTRYPOINT_V08;
    }

    /// @notice Gọi một contract bất kỳ thay mặt account (chỉ EntryPoint hoặc chính account).
    function execute(address target, uint256 value, bytes calldata data)
        external
        onlyEntryPointOrSelf
        returns (bytes memory)
    {
        return Address.functionCallWithValue(target, data, value);
    }
}
