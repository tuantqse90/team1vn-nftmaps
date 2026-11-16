import CoreML
import Foundation
import Vision

/// Nhận ra bé quen: so "dấu vân ảnh" (Vision feature print) của ảnh vừa bắt với ảnh các bé mình đã mint gần đó.
/// Không chắc chắn 100% nên app luôn hỏi lại người dùng trước khi tính là gặp lại.
enum PetMatcher {
    /// Khoảng cách feature print nhỏ hơn mức này thì coi là có thể cùng một bé.
    static let threshold: Float = 0.6

    /// Bé giống nhất trong `candidates` (id, JPEG), hoặc nil. Chạy đồng bộ — gọi ngoài main thread.
    static func bestMatch(for photo: Data, among candidates: [(id: UInt64, photo: Data)]) -> (id: UInt64, distance: Float)? {
        guard !candidates.isEmpty, let target = featurePrint(photo) else { return nil }
        var best: (id: UInt64, distance: Float)?
        for candidate in candidates {
            guard let other = featurePrint(candidate.photo) else { continue }
            var distance: Float = .infinity
            guard (try? target.computeDistance(&distance, to: other)) != nil else { continue }
            if distance < threshold, distance < (best?.distance ?? .infinity) {
                best = (candidate.id, distance)
            }
        }
        return best
    }

    private static func featurePrint(_ jpeg: Data) -> VNFeaturePrintObservation? {
        guard let image = PetPhoto.uprightImage(from: jpeg, maxPixelSize: 512) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        #if targetEnvironment(simulator)
        if let cpu = MLComputeDevice.allComputeDevices.first(where: { if case .cpu = $0 { true } else { false } }) {
            request.setComputeDevice(cpu, for: .main)
        }
        #endif
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.first
    }
}
