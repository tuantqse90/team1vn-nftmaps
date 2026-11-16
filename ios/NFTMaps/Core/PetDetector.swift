import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision

/// Loài mà contract MapNFT chấp nhận — rawValue khớp `enum Species` trong Solidity.
enum PetSpecies: UInt8, Sendable, Hashable, Codable {
    case cat = 1
    case dog = 2

    var displayName: String {
        switch self {
        case .cat: "Mèo"
        case .dog: "Chó"
        }
    }

    var symbolName: String {
        switch self {
        case .cat: "cat.fill"
        case .dog: "dog.fill"
        }
    }
}

struct PetDetection: Sendable, Equatable {
    let species: PetSpecies
    /// 0...1
    let confidence: Float
    /// Khung chứa con vật, toạ độ chuẩn hoá của Vision (gốc ở góc dưới-trái).
    let boundingBox: CGRect

    var confidencePercent: UInt8 {
        UInt8(min(max((confidence * 100).rounded(), 0), 100))
    }
}

/// Nhận diện chó/mèo bằng model có sẵn trong iOS (Vision `VNRecognizeAnimalsRequest`): chạy offline, không cần tải model.
enum PetDetector {
    /// Dưới ngưỡng này coi như không thấy. Ảnh chó/mèo rõ thường đạt 0.7–0.9.
    static let minimumConfidence: Float = 0.5

    /// Con chó/mèo rõ nhất trong ảnh (đã xoay đúng chiều), hoặc nil. Chạy đồng bộ — gọi ngoài main thread.
    static func detect(in image: CGImage) throws -> PetDetection? {
        try detect(with: VNImageRequestHandler(cgImage: image))
    }

    /// Như trên, cho khung hình camera (đã xoay dọc).
    static func detect(in pixelBuffer: CVPixelBuffer) throws -> PetDetection? {
        try detect(with: VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]))
    }

    private static func detect(with handler: VNImageRequestHandler) throws -> PetDetection? {
        let request = VNRecognizeAnimalsRequest()
        #if targetEnvironment(simulator)
        // Simulator không có Neural Engine/GPU cho Vision — ép chạy CPU để tránh lỗi tạo inference context.
        if let cpu = MLComputeDevice.allComputeDevices.first(where: { if case .cpu = $0 { true } else { false } }) {
            request.setComputeDevice(cpu, for: .main)
        }
        #endif
        try handler.perform([request])

        let detections = (request.results ?? []).compactMap { observation -> PetDetection? in
            guard let label = observation.labels.first, label.confidence >= minimumConfidence else { return nil }
            let species: PetSpecies
            switch VNAnimalIdentifier(rawValue: label.identifier) {
            case .cat: species = .cat
            case .dog: species = .dog
            default: return nil
            }
            return PetDetection(species: species, confidence: label.confidence, boundingBox: observation.boundingBox)
        }
        return detections.max { $0.confidence < $1.confidence }
    }
}

/// Một bé đã "bắt" được: kết quả model trên đúng khung hình lúc bắt + JPEG sẽ lưu on-chain.
struct CaughtPet: Sendable, Equatable, Identifiable {
    let id = UUID()
    let detection: PetDetection
    let thumbnail: Data

    /// Nhận diện lại trên ảnh chụp lúc bắt rồi cắt thumbnail. nil nếu trong ảnh không còn chó/mèo.
    static func make(from image: CGImage) throws -> CaughtPet? {
        guard let detection = try PetDetector.detect(in: image),
              let thumbnail = PetPhoto.thumbnail(of: image, focus: detection.boundingBox)
        else { return nil }
        return CaughtPet(detection: detection, thumbnail: thumbnail)
    }
}
