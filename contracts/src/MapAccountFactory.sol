// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MapAccount} from "./MapAccount.sol";

/// @title MapAccountFactory — tạo MapAccount (clone ERC-1167) tại địa chỉ xác định theo owner
/// @notice Địa chỉ account biết trước khi deploy (counterfactual). EntryPoint gọi `createAccount`
///         qua `initCode` ở UserOperation đầu tiên.
contract MapAccountFactory {
    address public immutable implementation;

    constructor() {
        implementation = address(new MapAccount());
    }

    function createAccount(address owner) external returns (address account) {
        bytes32 salt = _salt(owner);
        account = Clones.predictDeterministicAddress(implementation, salt);
        if (account.code.length == 0) {
            Clones.cloneDeterministic(implementation, salt);
            MapAccount(payable(account)).initialize(owner);
        }
    }

    function getAddress(address owner) external view returns (address) {
        return Clones.predictDeterministicAddress(implementation, _salt(owner));
    }

    function _salt(address owner) private pure returns (bytes32) {
        return bytes32(uint256(uint160(owner)));
    }
}
