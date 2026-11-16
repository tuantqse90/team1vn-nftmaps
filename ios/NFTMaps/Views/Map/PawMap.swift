@preconcurrency import MapLibre
import SwiftUI

/// Điều khiển camera + chiếu toạ độ ra điểm trên màn hình cho lớp ghim SwiftUI.
@MainActor
@Observable
final class PawMapController {
    @ObservationIgnored fileprivate weak var mapView: MLNMapView?
    /// Tăng mỗi khi camera đổi → lớp ghim vẽ lại đúng chỗ.
    private(set) var revision = 0
    private(set) var isStyleLoaded = false
    @ObservationIgnored private var pending: (() -> Void)?

    var zoom: Double = 17.0
    var pitch: CGFloat = 56

    func point(for coordinate: CLLocationCoordinate2D) -> CGPoint? {
        guard let mapView else { return nil }
        let point = mapView.convert(coordinate, toPointTo: mapView)
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return point
    }

    var center: CLLocationCoordinate2D? { mapView?.centerCoordinate }

    /// Đưa camera tới một điểm, giữ góc nghiêng kiểu game.
    func look(at coordinate: CLLocationCoordinate2D, zoom: Double? = nil, heading: CLLocationDirection? = nil,
              duration: TimeInterval = 0.8) {
        guard let mapView else {
            pending = { [weak self] in self?.look(at: coordinate, zoom: zoom, heading: heading, duration: 0) }
            return
        }
        let size = mapView.bounds.size == .zero ? CGSize(width: 390, height: 844) : mapView.bounds.size
        let altitude = MLNAltitudeForZoomLevel(zoom ?? self.zoom, pitch, coordinate.latitude, size)
        let camera = MLNMapCamera(lookingAtCenter: coordinate, altitude: altitude, pitch: pitch,
                                  heading: heading ?? mapView.direction)
        if duration > 0 {
            mapView.setCamera(camera, withDuration: duration,
                              animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            mapView.setCamera(camera, animated: false)
        }
    }

    /// Khung vừa các điểm (tuyến dẫn đường, vòng chạy).
    func fit(_ coordinates: [CLLocationCoordinate2D], padding: UIEdgeInsets = UIEdgeInsets(top: 80, left: 50, bottom: 80, right: 50)) {
        guard let mapView, coordinates.count > 1 else { return }
        var bounds = MLNCoordinateBounds(sw: coordinates[0], ne: coordinates[0])
        for c in coordinates {
            bounds.sw.latitude = min(bounds.sw.latitude, c.latitude)
            bounds.sw.longitude = min(bounds.sw.longitude, c.longitude)
            bounds.ne.latitude = max(bounds.ne.latitude, c.latitude)
            bounds.ne.longitude = max(bounds.ne.longitude, c.longitude)
        }
        let flat = mapView.cameraThatFitsCoordinateBounds(bounds, edgePadding: padding)
        flat.pitch = pitch
        mapView.setCamera(flat, withDuration: 0.8, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
    }

    fileprivate func attach(_ mapView: MLNMapView) {
        self.mapView = mapView
        pending?()
        pending = nil
    }

    fileprivate func cameraChanged() { revision &+= 1 }
    fileprivate func styleLoaded() { isStyleLoaded = true; revision &+= 1 }
}

/// Các lớp vẽ thẳng trên bản đồ (nằm dưới nhà 3D / ghim).
struct PawMapLayers {
    var suggested: [CLLocationCoordinate2D] = []
    var track: [CLLocationCoordinate2D] = []
    var me: CLLocationCoordinate2D?
    /// Vòng tròn đứt nét quanh người chơi (mét); 0 = ẩn.
    var rangeMeters: Double = 0
    /// Vòng màu độ hiếm in trên mặt đất dưới mỗi ghim.
    var rings: [(CLLocationCoordinate2D, Color)] = []

    fileprivate var signature: String {
        func key(_ c: CLLocationCoordinate2D?) -> String { c.map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) } ?? "-" }
        return [String(suggested.count), key(suggested.last), String(track.count), key(track.last), key(me),
                String(rangeMeters), String(rings.count), key(rings.first?.0)].joined(separator: "|")
    }
}

/// Bản đồ PawRun: MapLibre + style design, lớp ghim SwiftUI đặt theo toạ độ.
struct PawMap<Markers: View>: View {
    let controller: PawMapController
    var layers = PawMapLayers()
    /// Khoảng chừa trên/dưới để tâm camera (vị trí người chơi) nằm giữa phần bản đồ còn thấy.
    var insets = UIEdgeInsets.zero
    var interactive = true
    @ViewBuilder var markers: () -> Markers

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapLibreView(controller: controller, layers: layers, insets: insets, interactive: interactive)
            MarkerLayer(controller: controller, content: markers)
            // Ghi công OSM (bắt buộc) — nhỏ, nằm ngay dưới dải trời thay cho nút (i) của MapLibre.
            Link(PawMapStyle.source.attribution, destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                .font(.vn(9, .medium))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.6), in: Capsule())
                .padding(.leading, 8)
                .padding(.top, insets.top + 118)
        }
        .ignoresSafeArea()
    }
}

/// Đặt một ghim tại toạ độ, neo ở đáy (mũi ghim / chân nhân vật).
struct MapPinned<Content: View>: View {
    @Environment(PawMapController.self) private var controller
    let coordinate: CLLocationCoordinate2D
    var anchor: UnitPoint = .bottom
    let size: CGSize
    @ViewBuilder var content: () -> Content

    var body: some View {
        let _ = controller.revision
        if let point = controller.point(for: coordinate), point.y > -40, point.x > -60, point.x < 2000 {
            content()
                .frame(width: size.width, height: size.height)
                .position(x: point.x + (0.5 - anchor.x) * size.width, y: point.y + (0.5 - anchor.y) * size.height)
        }
    }
}

private struct MarkerLayer<Content: View>: View {
    let controller: PawMapController
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(controller)
    }
}

private struct MapLibreView: UIViewRepresentable {
    let controller: PawMapController
    let layers: PawMapLayers
    let insets: UIEdgeInsets
    let interactive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> MLNMapView {
        let url = URL.cachesDirectory.appending(path: "pawrun-style.json")
        try? PawMapStyle.json().write(to: url, options: .atomic)
        let view = MLNMapView(frame: .zero, styleURL: url)
        view.delegate = context.coordinator
        view.logoView.isHidden = true
        view.compassView.isHidden = true
        view.attributionButton.isHidden = true
        view.allowsTilting = false
        view.allowsRotating = interactive
        view.allowsScrolling = interactive
        view.allowsZooming = interactive
        view.minimumZoomLevel = 12
        view.maximumZoomLevel = 19
        view.maximumPitch = 60
        view.automaticallyAdjustsContentInset = false
        view.contentInset = insets
        view.backgroundColor = UIColor(red: 0.765, green: 0.918, blue: 0.588, alpha: 1)
        controller.attach(view)
        context.coordinator.pending = layers
        return view
    }

    func updateUIView(_ view: MLNMapView, context: Context) {
        if view.contentInset != insets { view.setContentInset(insets, animated: false, completionHandler: nil) }
        context.coordinator.apply(layers, to: view)
    }

    @MainActor
    final class Coordinator: NSObject {
        let controller: PawMapController
        var pending: PawMapLayers?
        private var applied = ""
        private var style: MLNStyle?

        init(controller: PawMapController) { self.controller = controller }

        func apply(_ layers: PawMapLayers, to view: MLNMapView) {
            guard let style else { pending = layers; return }
            let signature = layers.signature
            guard signature != applied else { return }
            applied = signature
            set("suggested", in: style, line(layers.suggested))
            set("track", in: style, line(layers.track))
            set("me", in: style, layers.me.map { point($0) } ?? empty)
            set("range", in: style, layers.me.flatMap { layers.rangeMeters > 0 ? circle($0, layers.rangeMeters) : nil } ?? empty)
            let rings: [MLNShape & MLNFeature] = layers.rings.map { coordinate, color in
                let feature = MLNPointFeature()
                feature.coordinate = coordinate
                feature.attributes = ["color": color.hexString]
                return feature
            }
            set("rings", in: style, MLNShapeCollectionFeature(shapes: rings))
        }

        private var empty: MLNShape { MLNShapeCollectionFeature(shapes: []) }

        private func set(_ id: String, in style: MLNStyle, _ shape: MLNShape) {
            (style.source(withIdentifier: id) as? MLNShapeSource)?.shape = shape
        }

        private func line(_ coordinates: [CLLocationCoordinate2D]) -> MLNShape {
            guard coordinates.count > 1 else { return empty }
            var copy = coordinates
            return MLNPolylineFeature(coordinates: &copy, count: UInt(copy.count))
        }

        private func point(_ coordinate: CLLocationCoordinate2D) -> MLNShape {
            let feature = MLNPointFeature()
            feature.coordinate = coordinate
            return feature
        }

        private func circle(_ center: CLLocationCoordinate2D, _ meters: Double) -> MLNShape {
            var ring = (0...64).map { center.offset(meters: meters, bearing: Double($0) * 360 / 64) }
            return MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count))
        }

        fileprivate func loaded(_ style: MLNStyle, view: MLNMapView) {
            self.style = style
            applied = ""
            if let pending { apply(pending, to: view) }
            pending = nil
            controller.styleLoaded()
        }
    }
}

extension MapLibreView.Coordinator: @preconcurrency MLNMapViewDelegate {
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) { loaded(style, view: mapView) }
    func mapViewRegionIsChanging(_ mapView: MLNMapView) { controller.cameraChanged() }
    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) { controller.cameraChanged() }
    func mapViewDidFinishRenderingFrame(_ mapView: MLNMapView, fullyRendered: Bool) {
        // Lần đầu dựng (chưa có sự kiện camera) cũng phải đặt ghim.
        if controller.revision < 3 { controller.cameraChanged() }
    }
}

extension Color {
    /// "#RRGGBB" cho style MapLibre.
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Trời hoàng hôn phía trên bản đồ (artboard Bản đồ, dải 390×330)

struct SkyBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 390
            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
                CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
            }
            context.fill(Path(rect(0, 0, 390, 236)), with: .linearGradient(
                Gradient(stops: [.init(color: Color(hex: 0xFFB98C), location: 0),
                                 .init(color: Color(hex: 0xFFDDBA), location: 0.55),
                                 .init(color: Color(hex: 0xFFF0DC), location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: 236 * s)))
            context.fill(Path(ellipseIn: rect(270, 166, 60, 60)), with: .color(Color(hex: 0xFFF3D6).opacity(0.9)))
            for (x, y, w, h) in [(30.0, 190.0, 80.0, 20.0), (72, 183, 44, 20), (206, 178, 60, 16), (238, 173, 32, 16)] {
                context.fill(Path(ellipseIn: rect(x, y, w, h)), with: .color(.white.opacity(0.85)))
            }
            for (x, y, w, h) in [(10.0, 200.0, 22.0, 36.0), (36, 190, 16, 46), (58, 208, 28, 28), (196, 186, 14, 50),
                                 (214, 198, 26, 38), (246, 208, 20, 28), (326, 194, 18, 42), (348, 204, 30, 32)] {
                context.fill(Path(rect(x, y, w, h)), with: .color(Color(hex: 0xF3C3A6)))
            }
            var hill = Path()
            hill.move(to: CGPoint(x: 0, y: 226 * s))
            hill.addCurve(to: CGPoint(x: 170 * s, y: 216 * s), control1: CGPoint(x: 60 * s, y: 208 * s), control2: CGPoint(x: 120 * s, y: 222 * s))
            hill.addCurve(to: CGPoint(x: 390 * s, y: 212 * s), control1: CGPoint(x: 230 * s, y: 208 * s), control2: CGPoint(x: 300 * s, y: 224 * s))
            hill.addLine(to: CGPoint(x: 390 * s, y: 252 * s))
            hill.addLine(to: CGPoint(x: 0, y: 252 * s))
            hill.closeSubpath()
            context.fill(hill, with: .color(Color(hex: 0xA9DC8A)))
            context.fill(Path(rect(0, 236, 390, 94)), with: .linearGradient(
                Gradient(colors: [Color(hex: 0xFFF0DC), Color(hex: 0xFFF0DC).opacity(0)]),
                startPoint: CGPoint(x: 0, y: 236 * s), endPoint: CGPoint(x: 0, y: 330 * s)))
        }
        .aspectRatio(390 / 330, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
