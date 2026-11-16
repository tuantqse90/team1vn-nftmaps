import AVFoundation
import CoreImage
import os
import QuartzCore
import SwiftUI

/// Camera sau cho màn bắt: xem trực tiếp + nhận diện chó/mèo ~6 lần/giây trên khung hình.
/// Mọi trạng thái nội bộ chỉ được chạm trên `queue`, trừ khung hình mới nhất (có khoá riêng).
final class CatchCamera: NSObject, @unchecked Sendable {
    struct Frame: Sendable {
        let detection: PetDetection?
        /// Kích thước khung hình đã xoay dọc, theo pixel.
        let imageSize: CGSize
    }

    enum CameraError: LocalizedError {
        case unavailable
        case denied

        var errorDescription: String? {
            switch self {
            case .unavailable: "Máy này không có camera sau (Simulator?). Chọn một ảnh chó/mèo để chơi nhé."
            case .denied: "Bạn chưa cho phép dùng camera. Bật trong Cài đặt › NFT Maps, hoặc chọn ảnh để chơi."
            }
        }
    }

    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    /// Camera sau có đèn (nút đèn flash trên màn bắt).
    static var hasTorch: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)?.hasTorch ?? false
    }

    let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "com.hackbuilder.nftmaps.camera")
    private let latestBuffer = OSAllocatedUnfairLock<CVPixelBuffer?>(uncheckedState: nil)
    private let ciContext = CIContext()
    private var isConfigured = false
    private var device: AVCaptureDevice?
    private var lastDetection: CFTimeInterval = 0
    private var continuation: AsyncStream<Frame>.Continuation?

    func start() async throws {
        guard Self.isAvailable else { throw CameraError.unavailable }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw CameraError.denied }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async {
                do {
                    if !self.isConfigured {
                        try self.configure()
                        self.isConfigured = true
                    }
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    /// Bật/tắt đèn camera sau (tự tắt khi dừng session).
    func setTorch(_ on: Bool) {
        queue.async {
            guard let device = self.device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    /// Luồng kết quả nhận diện. Mỗi lần gọi tạo luồng mới, thay luồng cũ.
    func frames() -> AsyncStream<Frame> {
        let (stream, continuation) = AsyncStream.makeStream(of: Frame.self, bufferingPolicy: .bufferingNewest(1))
        queue.async { self.continuation = continuation }
        return stream
    }

    /// Khung hình mới nhất (đã dựng đứng) — thành ảnh NFT nếu bắt trúng.
    func snapshot() -> CGImage? {
        guard let buffer = latestBuffer.withLockUnchecked({ $0 }) else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        return ciContext.createCGImage(image, from: image.extent)
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.unavailable
        }
        self.device = device
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CameraError.unavailable }
        session.addInput(input)
        session.addOutput(output)
        // App chỉ chạy dọc: xoay khung hình 90° để toạ độ của model khớp màn hình.
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

extension CatchCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestBuffer.withLockUnchecked { $0 = buffer }

        let now = CACurrentMediaTime()
        guard now - lastDetection >= 0.15, let continuation else { return }
        lastDetection = now
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        continuation.yield(Frame(detection: try? PetDetector.detect(in: buffer), imageSize: size))
    }
}

/// Lớp xem trước camera, lấp đầy màn hình (aspect fill — cùng phép quy đổi với `CatchTarget`).
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90),
               connection.videoRotationAngle != 90 {
                connection.videoRotationAngle = 90
            }
        }
    }
}
