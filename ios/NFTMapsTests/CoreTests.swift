import XCTest
@testable import NFTMaps

/// Vector kỳ vọng lấy từ nguồn độc lập: `cast` (Foundry), Python hashlib, và EntryPoint v0.8 thật trên Fuji.
final class CoreTests: XCTestCase {
    func testKeccak256() {
        XCTAssertEqual(Keccak256.hash(Data()).hex, "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        XCTAssertEqual(Keccak256.hash("abc").hex, "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
    }

    func testKeyDerivationAndAddress() throws {
        // python: hashlib.pbkdf2_hmac('sha256', b'password123', b'nftmaps-v1:alice', 600000, 32)
        let key = try KeyDerivation.privateKey(username: "  Alice ", password: "password123")
        XCTAssertEqual(key.hex, "0xc74446e109d4fb0134b956b52e2d5212b49010995aeff63c1240a8574db4a557")
        // cast wallet address --private-key <key>
        XCTAssertEqual(try EthereumSigner(privateKey: key).address, try Address("0x0DaD94C5Aa4cad9099e99bdfb3ae9A9f2437f8AB"))
    }

    func testSignatureMatchesCast() throws {
        let key = try Data(hex: "0xc74446e109d4fb0134b956b52e2d5212b49010995aeff63c1240a8574db4a557")
        let signature = try EthereumSigner(privateKey: key).sign(digest: Keccak256.hash("hello"))
        // cast wallet sign --no-hash --private-key <key> $(cast keccak hello)
        XCTAssertEqual(signature.hex, "0xc0eaa7dd988190279fb9450b01aa2803770a6df91d1cdc3a063e8e95ae58aa7507067efa05483d8fc5fc5889c470ee8fd865b34b06d0f626aae6acea35a2954d1b")
    }

    func testMintCalldataMatchesCast() {
        let detection = PetDetection(species: .cat, confidence: 0.934, boundingBox: .zero)
        let call = MapNFTCall.mint(latitude: -33.856784, longitude: 151.215297, detection: detection,
                                   name: "Mướp", photo: Data([0xff, 0xd8, 0xff, 0xd9]))
        // cast calldata "mint(int32,int32,uint8,uint8,string,bytes)" -- -33856784 151215297 1 93 "Mướp" 0xffd8ffd9
        XCTAssertEqual(call.hex, "0x3cedcfedfffffffffffffffffffffffffffffffffffffffffffffffffffffffffdfb62f00000000000000000000000000000000000000000000000000000000009035cc10000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000005d00000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000074dc6b0e1bb9b70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004ffd8ffd900000000000000000000000000000000000000000000000000000000")
    }

    func testUserOperationHashMatchesEntryPoint() throws {
        let owner = try Address("0x0DaD94C5Aa4cad9099e99bdfb3ae9A9f2437f8AB")
        var operation = UserOperation(sender: try Address("0x7a42a205e329b83fec4786761203cb3e06823239"),
                                      nonce: 5, callData: Data([0xde, 0xad, 0xbe, 0xef]))
        operation.factory = try Address("0x7aCee4c6041a75518b21209Cb90BeE88F35CABbA")
        operation.factoryData = ABI.call(ABI.Selector.createAccount, [.address(owner)])
        operation.callGasLimit = 300_000
        operation.verificationGasLimit = 500_000
        operation.preVerificationGas = 60_000
        operation.maxFeePerGas = 50_000_000_000
        operation.maxPriorityFeePerGas = 1_000_000_000
        operation.paymaster = try Address("0x1111111111111111111111111111111111111111")
        operation.paymasterVerificationGasLimit = 100_000
        operation.paymasterPostOpGasLimit = 50_000
        operation.paymasterData = Data([0xab, 0xcd])

        let hash = operation.hash(chainID: 43113, entryPoint: try Address("0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108"))
        // cast call <EntryPoint v0.8> "getUserOpHash((...))(bytes32)" <cùng op> --rpc-url fuji
        XCTAssertEqual(hash.hex, "0x6ce1e5f5268204032b04ede6cf7c6a40bc114463da84cb1e24736c10bbe7a5ca")
    }

    func testPackedFieldLayout() throws {
        var operation = UserOperation(sender: try Address("0x7a42a205e329b83fec4786761203cb3e06823239"),
                                      nonce: 0, callData: Data())
        operation.verificationGasLimit = 1
        operation.callGasLimit = 2
        operation.maxPriorityFeePerGas = 3
        operation.maxFeePerGas = 4
        XCTAssertEqual(operation.accountGasLimits.hex, "0x" + String(repeating: "0", count: 31) + "1" + String(repeating: "0", count: 31) + "2")
        XCTAssertEqual(operation.gasFees.hex, "0x" + String(repeating: "0", count: 31) + "3" + String(repeating: "0", count: 31) + "4")
        XCTAssertTrue(operation.initCode.isEmpty)
        XCTAssertTrue(operation.paymasterAndData.isEmpty)
        XCTAssertEqual(UserOperation.dummySignature.count, 65)
    }

    func testABIDecoderRoundTrip() throws {
        let encoded = ABI.encode([.uint(7), .string("Mướp \"mèo\""), .bytes(Data([1, 2, 3])), .int(-5)])
        let decoder = ABIDecoder(data: encoded)
        XCTAssertEqual(try decoder.uint64(at: 0), 7)
        XCTAssertEqual(try decoder.string(at: 1), "Mướp \"mèo\"")
        XCTAssertEqual(try decoder.bytes(at: 2), Data([1, 2, 3]))
        XCTAssertEqual(try decoder.int32(at: 3), -5)
        XCTAssertThrowsError(try ABIDecoder(data: Data([0x01])).uint64(at: 0))
    }

    func testConfidencePercentIsClamped() {
        XCTAssertEqual(PetDetection(species: .dog, confidence: 0.934, boundingBox: .zero).confidencePercent, 93)
        XCTAssertEqual(PetDetection(species: .dog, confidence: 1.2, boundingBox: .zero).confidencePercent, 100)
        XCTAssertEqual(PetDetection(species: .dog, confidence: -0.1, boundingBox: .zero).confidencePercent, 0)
    }

    func testSpeciesRawValuesMatchContract() {
        // enum Species { None, Cat, Dog } trong MapNFT.sol
        XCTAssertEqual(PetSpecies.cat.rawValue, 1)
        XCTAssertEqual(PetSpecies.dog.rawValue, 2)
        XCTAssertNil(PetSpecies(rawValue: 0))
    }
}
