// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/// @notice Lưu dữ liệu lớn (ảnh) làm bytecode của một contract con — rẻ hơn SSTORE ~3 lần.
/// @dev Bytecode = 0x00 (STOP, để không ai gọi được) ‖ data. Giới hạn EIP-170: data ≤ 24575 byte.
library SSTORE2 {
    error DeploymentFailed();

    function write(bytes memory data) internal returns (address pointer) {
        bytes memory runtime = abi.encodePacked(hex"00", data);
        // PUSH4 len | DUP1 | PUSH1 0x0e | PUSH1 0 | CODECOPY | PUSH1 0 | RETURN  (14 byte), theo sau là runtime
        bytes memory creation = abi.encodePacked(hex"63", uint32(runtime.length), hex"80600e6000396000f3", runtime);
        assembly ("memory-safe") {
            pointer := create(0, add(creation, 0x20), mload(creation))
        }
        if (pointer == address(0)) revert DeploymentFailed();
    }

    function read(address pointer) internal view returns (bytes memory data) {
        uint256 size = pointer.code.length - 1;
        data = new bytes(size);
        assembly ("memory-safe") {
            extcodecopy(pointer, add(data, 0x20), 1, size)
        }
    }
}
