import CoreLocation
import PhotosUI
import SwiftUI

/// Màn "bắt" chó/mèo kiểu game (artboard Capture): camera trực tiếp, model khoanh 4 góc quanh con vật,
/// vuốt quả bóng dấu chân từ thanh dưới để bắt. Không có camera (Simulator) hoặc muốn dùng ảnh cũ thì chọn ảnh.
struct CatchScreen: View {
    /// Gọi khi bắt được và bấm "Đặt tên & mint". Màn hình tự đóng ngay sau đó.
    let onCaught: (CaughtPet) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(MapViewModel.self) private var chain
    @AppStorage("fuzzLocation") private var fuzzLocation = true
    @State private var camera = CatchCamera()
    @State private var source: Source = .starting
    @State private var pickerItem: PhotosPickerItem?
    @State private var location: CLLocationCoordinate2D?
    @State private var locating = true
    @State private var torch = false

    private enum Source {
        case starting
        case camera
        case photo(CGImage, id: UUID)
        case unavailable(String)
    }

    private var isCamera: Bool { if case .camera = source { true } else { false } }

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()

            switch source {
            case .starting:
                ProgressView().tint(.white)
            case .camera:
                CatchGameView(scene: .camera(camera), rarity: rarity, pickerItem: $pickerItem, onUseCamera: nil,
                              onCaught: finish)
            case .photo(let image, let id):
                CatchGameView(scene: .photo(image), rarity: rarity, pickerItem: $pickerItem,
                              onUseCamera: CatchCamera.isAvailable ? { Task { await startCamera() } } : nil,
                              onCaught: finish)
                    .id(id)
            case .unavailable(let message):
                unavailable(message)
            }
        }
        .overlay(alignment: .top) { topBar }
        .preferredColorScheme(.dark)
        .task {
            #if DEBUG
            // Cho UI test / Simulator: NFTMAPS_CATCH_PHOTO=/đường/dẫn/ảnh.jpg → chơi luôn trên ảnh đó.
            if let path = Config.override("NFTMAPS_CATCH_PHOTO"),
               let data = FileManager.default.contents(atPath: path),
               let image = PetPhoto.uprightImage(from: data) {
                source = .photo(image, id: UUID())
                return
            }
            #endif
            await startCamera()
        }
        .task {
            location = await LocationOnce.current(timeout: .seconds(12))
            locating = false
        }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                pickerItem = nil
                guard let data, let image = PetPhoto.uprightImage(from: data) else { return }
                camera.stop()
                torch = false
                source = .photo(image, id: UUID())
            }
        }
    }

    /// Độ hiếm nếu mint ở đây (cùng cách tính với màn mint: theo toạ độ sẽ lên chain).
    private func rarity(_ species: PetSpecies) -> Rarity? {
        guard let location else { return nil }
        return chain.rarityForNewPet(species: species, at: fuzzLocation ? LocationPrivacy.fuzz(location) : location)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark").modifier(CaptureRoundButton())
            }
            .accessibilityLabel("Đóng")
            Spacer()
            GPSChip(locating: locating, located: location != nil)
            Spacer()
            if isCamera, CatchCamera.hasTorch {
                Button {
                    torch.toggle()
                    camera.setTorch(torch)
                } label: {
                    Image(systemName: torch ? "bolt.fill" : "bolt").modifier(CaptureRoundButton(active: torch))
                }
                .accessibilityLabel(torch ? "Tắt đèn" : "Bật đèn")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func unavailable(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 72, height: 72)
                .background(Theme.line, in: Circle())
            Text("Không mở được camera").font(.game(26)).foregroundStyle(.white)
            Text(message)
                .font(.vn(14))
                .foregroundStyle(Theme.onDark)
                .multilineTextAlignment(.center)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Chọn ảnh để chơi", systemImage: "photo.on.rectangle").font(.game(19))
            }
            .buttonStyle(ChunkyButtonStyle())
            .padding(.top, 6)
        }
        .padding(28)
    }

    private func startCamera() async {
        do {
            try await camera.start()
            source = .camera
        } catch {
            source = .unavailable(error.localizedDescription)
        }
    }

    private func finish(_ pet: CaughtPet) {
        onCaught(pet)
        dismiss()
    }
}

/// Nút tròn tối trên nền camera (đóng, đèn, chọn ảnh…).
private struct CaptureRoundButton: ViewModifier {
    var active = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(active ? Theme.ink : .white)
            .frame(width: 44, height: 44)
            .background(active ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(.black.opacity(0.38)), in: Circle())
    }
}

/// Chip "GPS khớp": có toạ độ hiện tại thì bé sẽ được mint đúng chỗ đang đứng.
private struct GPSChip: View {
    let locating: Bool
    let located: Bool

    var body: some View {
        HStack(spacing: 6) {
            if located {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(Color(hex: 0x3DD6C3))
                Text("GPS khớp")
            } else if locating {
                ProgressView().controlSize(.mini).tint(.white)
                Text("Đang dò GPS…")
            } else {
                Image(systemName: "location.slash.fill").foregroundStyle(Color(hex: 0xFF9A5A))
                Text("Chưa có GPS")
            }
        }
        .font(.vn(12, .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.black.opacity(0.38), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Vùng con vật quy ra toạ độ màn hình (nền camera/ảnh hiển thị kiểu aspect fill).
struct CatchTarget: Equatable {
    let center: CGPoint
    let radius: CGFloat
    let species: PetSpecies
    let confidence: UInt8

    init(_ detection: PetDetection, imageSize: CGSize, in view: CGSize) {
        let scale = max(view.width / imageSize.width, view.height / imageSize.height)
        let offsetX = (view.width - imageSize.width * scale) / 2
        let offsetY = (view.height - imageSize.height * scale) / 2
        let box = detection.boundingBox  // Vision: chuẩn hoá, gốc dưới-trái
        let shownWidth: CGFloat = imageSize.width * scale
        let shownHeight: CGFloat = imageSize.height * scale
        let fullRect = CGRect(x: box.minX * shownWidth + offsetX,
                              y: (1 - box.maxY) * shownHeight + offsetY,
                              width: box.width * shownWidth,
                              height: box.height * shownHeight)
        // Aspect fill cắt bớt mép ảnh — chỉ tính phần con vật đang hiện trên màn hình.
        let visible = fullRect.intersection(CGRect(origin: .zero, size: view))
        let rect = visible.isNull ? fullRect : visible
        radius = min(max(min(rect.width, rect.height) * 0.42, 56), 130)
        // Giữ vòng ngắm trong vùng ném được: dưới dòng gợi ý, trên quả bóng.
        center = CGPoint(x: min(max(rect.midX, radius), view.width - radius),
                         y: min(max(rect.midY, 200), view.height - 330))
        species = detection.species
        confidence = detection.confidencePercent
    }
}

/// Ném càng gần tâm càng dễ bắt.
enum ThrowQuality {
    case bullseye
    case great
    case hit

    init?(distance: CGFloat, radius: CGFloat) {
        switch distance / radius {
        case ..<0.35: self = .bullseye
        case ..<0.7: self = .great
        case ...1: self = .hit
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .bullseye: "Trúng tâm!"
        case .great: "Ném đẹp!"
        case .hit: "Trúng rồi!"
        }
    }

    var color: Color {
        switch self {
        case .bullseye: Theme.purple
        case .great: Theme.orange
        case .hit: Theme.blue
        }
    }

    /// Xác suất bé ở lại trong bóng sau 3 lần lắc.
    var catchChance: Double {
        switch self {
        case .bullseye: 1
        case .great: 0.9
        case .hit: 0.75
        }
    }
}

struct CatchGameView: View {
    enum Scene {
        case camera(CatchCamera)
        case photo(CGImage)
    }

    let scene: Scene
    /// Độ hiếm nếu mint ở vị trí hiện tại (nil khi chưa có GPS).
    var rarity: (PetSpecies) -> Rarity? = { _ in nil }
    @Binding var pickerItem: PhotosPickerItem?
    /// Có khi đang chơi trên ảnh và máy có camera: nút quay lại camera ở thanh dưới.
    var onUseCamera: (() -> Void)?
    let onCaught: (CaughtPet) -> Void

    /// Thanh tối dưới đáy (artboard Capture), bóng nằm giữa như nút chụp.
    private static let panelHeight: CGFloat = 184

    private enum Phase {
        case aiming
        case flying
        case capturing
        case caught
    }

    /// Lần model thấy con vật gần nhất + kích thước ảnh gốc (để quy ra toạ độ màn hình).
    private struct Sighting: Equatable {
        let detection: PetDetection
        let imageSize: CGSize
    }

    @State private var size: CGSize = .zero
    @State private var sighting: Sighting?
    @State private var lastSeen = Date.distantPast
    @State private var photoHasNoPet = false
    /// Ném mà chưa thấy bé nào (camera): hiện mẹo chụp.
    @State private var noPetTips = false
    @State private var phase: Phase = .aiming

    @State private var drag: CGSize = .zero
    @State private var flight: Flight?
    @State private var progress: CGFloat = 0
    @State private var orbScale: CGFloat = 1
    @State private var orbOpacity: Double = 1
    @State private var orbSpin: Double = 0
    @State private var orbWobble: Double = 0
    @State private var orbDrop: CGFloat = 0
    @State private var orbGlowing = false
    /// Số lần bóng đã lắc (0...3) — hiện thành 3 chấm dưới bóng.
    @State private var wobbles = 0

    @State private var effectPoint: CGPoint = .zero
    @State private var flashID: UUID?
    @State private var burstID: UUID?
    @State private var banner: CatchBanner?
    @State private var caught: CaughtPet?

    private var rest: CGPoint {
        CGPoint(x: size.width / 2, y: size.height - 96)
    }

    private var target: CatchTarget? {
        guard let sighting, size != .zero else { return nil }
        return CatchTarget(sighting.detection, imageSize: sighting.imageSize, in: size)
    }

    var body: some View {
        ZStack {
            game
            if showNoPet {
                Color.black.opacity(0.4).ignoresSafeArea().transition(.opacity)
                noPetSheet
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.move(edge: .bottom))
            }
            // Lớp chữ gợi ý nằm trong vùng an toàn, ngay dưới thanh nút của CatchScreen.
            if let hint {
                hintView(hint)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 60)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: sighting)
        .animation(.easeOut(duration: 0.25), value: hint)
        .animation(.spring(duration: 0.4), value: showNoPet)
        .animation(.spring(duration: 0.4, bounce: 0.5), value: banner)
        .task { await watchForPets() }
        .task(id: banner?.id) {
            guard banner != nil else { return }
            try? await Task.sleep(for: .milliseconds(1300))
            banner = nil
        }
    }

    private var game: some View {
        GeometryReader { proxy in
            ZStack {
                background(proxy.size)
                capturePanel(proxy.size)

                if let target, phase == .aiming || phase == .flying {
                    TargetReticle(target: target, rarity: rarity(target.species))
                        .position(target.center)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }

                if let flashID {
                    CatchFlash().id(flashID).position(effectPoint)
                }

                orb

                if phase == .capturing {
                    wobbleDots
                        .position(x: effectPoint.x, y: effectPoint.y + 90)
                        .transition(.opacity)
                }

                if let burstID {
                    CatchBurst().id(burstID).position(effectPoint)
                }

                if let banner {
                    CatchBannerView(banner: banner)
                        .id(banner.id)
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.27)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }

                if let caught {
                    Color.black.opacity(0.5)
                        .transition(.opacity)
                    CaughtCard(pet: caught) {
                        onCaught(caught)
                    } onRelease: {
                        withAnimation { self.caught = nil }
                        resetOrb()
                    }
                    .transition(.identity)
                }
            }
            .onAppear { size = proxy.size }
            .onChange(of: proxy.size) { _, newSize in size = newSize }
        }
        .ignoresSafeArea()
    }

    // MARK: - Lớp hiển thị

    @ViewBuilder
    private func background(_ size: CGSize) -> some View {
        switch scene {
        case .camera(let camera):
            CameraPreview(session: camera.session)
        case .photo(let image):
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }

    private var orb: some View {
        PawOrb(glowing: orbGlowing)
            .scaleEffect(orbScale)
            .rotationEffect(.degrees(orbSpin))
            .rotationEffect(.degrees(orbWobble), anchor: .bottom)
            .opacity(orbOpacity)
            .offset(y: orbDrop)
            .offset(drag)
            .modifier(ArcEffect(progress: progress, flight: flight))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bóng — vuốt lên để ném")
            .accessibilityIdentifier("pawOrb")
            .gesture(throwGesture)
            .allowsHitTesting(phase == .aiming && caught == nil)
            .position(rest)
    }

    private var wobbleDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < wobbles ? Theme.gold : Color.white.opacity(0.35))
                    .frame(width: 12, height: 12)
                    .scaleEffect(index < wobbles ? 1.25 : 1)
                    .shadow(color: index < wobbles ? Theme.gold : .clear, radius: 6)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.6), value: wobbles)
        .allowsHitTesting(false)
    }

    private var hint: String? {
        guard phase == .aiming, caught == nil, banner == nil, !showNoPet else { return nil }
        if let target {
            return "Ơ kìa, một bé \(target.species.displayName.lowercased())! Vuốt bóng về phía bé để bắt"
        }
        return "Đưa camera về phía một bé chó hoặc mèo…"
    }

    private func hintView(_ text: String) -> some View {
        Text(text)
            .font(.vn(15, .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.42), in: Capsule())
            .padding(.horizontal, 24)
            .allowsHitTesting(false)
    }

    private var showNoPet: Bool { (photoHasNoPet || noPetTips) && caught == nil }

    /// Thanh tối dưới đáy: chọn ảnh · khe bóng · quay lại camera.
    private func capturePanel(_ size: CGSize) -> some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(Theme.ink)
                .frame(height: Self.panelHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
            Circle()
                .strokeBorder(.white.opacity(0.9), lineWidth: 4)
                .frame(width: 96, height: 96)
                .position(rest)
                .allowsHitTesting(false)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle").modifier(PanelButton())
            }
            .accessibilityLabel("Chọn ảnh")
            .position(x: 74, y: rest.y)
            if let onUseCamera {
                Button(action: onUseCamera) {
                    Image(systemName: "camera.fill").modifier(PanelButton())
                }
                .accessibilityLabel("Dùng camera")
                .position(x: size.width - 74, y: rest.y)
            }
        }
    }

    /// Mẹo khi chưa thấy bé (artboard CaptureNoPet).
    private var noPetSheet: some View {
        VStack(spacing: 14) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 52, height: 52)
                .background(Theme.line, in: Circle())
            Text("Chưa thấy bé").font(.game(26)).foregroundStyle(Theme.ink)
            if photoHasNoPet {
                Text("Ảnh này không có chó hay mèo.").font(.vn(14)).foregroundStyle(Theme.ink2)
            }
            HStack(spacing: 8) {
                tip("viewfinder", "Lại gần")
                tip("sun.max", "Đủ sáng")
                tip("scope", "Giữ yên")
            }
            if photoHasNoPet {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text("Chọn ảnh khác").font(.game(19))
                }
                .buttonStyle(ChunkyButtonStyle())
                if let onUseCamera {
                    Button(action: onUseCamera) { Text("Dùng camera").font(.vn(15, .bold)).underline() }
                        .foregroundStyle(Theme.ink2)
                        .frame(minHeight: 44)
                }
            } else {
                Button { noPetTips = false } label: { Text("Chụp lại").font(.game(19)) }
                    .buttonStyle(ChunkyButtonStyle())
            }
        }
        .padding(EdgeInsets(top: 22, leading: 16, bottom: 40, trailing: 16))
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).fill(.white)
        }
        .environment(\.colorScheme, .light)
    }

    private func tip(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            Text(title).font(.vn(12, .semibold))
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(Color(hex: 0xF4F1FB), in: .rect(cornerRadius: 14))
    }

    // MARK: - Nhận diện

    private func watchForPets() async {
        switch scene {
        case .camera(let camera):
            for await frame in camera.frames() {
                if let detection = frame.detection {
                    lastSeen = .now
                    sighting = Sighting(detection: detection, imageSize: frame.imageSize)
                } else if sighting != nil, Date.now.timeIntervalSince(lastSeen) > 0.8 {
                    sighting = nil
                }
            }
        case .photo(let image):
            let detection = await Task.detached(priority: .userInitiated) {
                try? PetDetector.detect(in: image)
            }.value
            if let detection {
                sighting = Sighting(detection: detection, imageSize: CGSize(width: image.width, height: image.height))
            } else {
                photoHasNoPet = true
            }
        }
    }

    // MARK: - Ném bóng

    private var throwGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                // Bóng chỉ nhích theo tay một đoạn ngắn — muốn bắt phải vuốt/ném thật.
                let dx = value.translation.width * 0.5
                let dy = value.translation.height * 0.5
                let length = max(hypot(dx, dy), 1)
                let limit = min(length, 90) / length
                drag = CGSize(width: dx * limit, height: dy * limit)
            }
            .onEnded(release)
    }

    private func release(_ value: DragGesture.Value) {
        let vx = value.velocity.width
        let vy = -value.velocity.height  // dương = vuốt lên
        guard vy > 400 else {
            withAnimation(.spring(duration: 0.35, bounce: 0.45)) { drag = .zero }
            return
        }

        let start = CGPoint(x: rest.x + drag.width, y: rest.y + drag.height)
        let aimY = target?.center.y ?? size.height * 0.3
        // Lực vuốt quyết định độ xa: yếu thì rơi giữa đường, quá mạnh thì bay vọt qua.
        let landingY: CGFloat = switch vy {
        case ..<1000: start.y - (start.y - aimY) * vy / 1000
        case 4500...: max(aimY - (vy - 4500) * 0.06, 40)
        default: aimY
        }
        // Hướng vuốt quyết định lệch trái/phải.
        let landingX = start.x + vx / vy * (start.y - landingY)
        Task { await throwOrb(from: start, to: CGPoint(x: landingX, y: landingY)) }
    }

    private func throwOrb(from start: CGPoint, to landing: CGPoint) async {
        phase = .flying
        Haptics.impact(.medium)
        withoutAnimation {
            flight = Flight(rest: rest, start: start, end: landing, apex: max(70, (start.y - landing.y) * 0.3))
            progress = 0
            drag = .zero
        }
        withAnimation(.easeOut(duration: 0.6)) {
            progress = 1
            orbScale = 0.55
            orbSpin += 720
        }
        try? await Task.sleep(for: .milliseconds(600))

        guard let target,
              let quality = ThrowQuality(distance: hypot(landing.x - target.center.x, landing.y - target.center.y),
                                         radius: target.radius)
        else {
            await miss(hadTarget: target != nil)
            return
        }
        await capture(at: landing, quality: quality)
    }

    private func miss(hadTarget: Bool) async {
        Haptics.impact(.light)
        withAnimation(.easeIn(duration: 0.45)) {
            orbDrop = size.height * 0.5
            orbOpacity = 0
        }
        banner = CatchBanner(text: hadTarget ? "Trượt rồi!" : "Chưa thấy bé nào!", color: Theme.ink2)
        if !hadTarget, case .camera = scene { noPetTips = true }
        try? await Task.sleep(for: .milliseconds(900))
        resetOrb()
    }

    private func capture(at point: CGPoint, quality: ThrowQuality) async {
        phase = .capturing
        effectPoint = point
        flashID = UUID()
        banner = CatchBanner(text: quality.title, color: quality.color)
        Haptics.impact(.heavy)

        // Lấy đúng khung hình lúc trúng; model chạy lại trên ảnh đó song song với hiệu ứng lắc.
        let snapshot: CGImage? = switch scene {
        case .camera(let camera): camera.snapshot()
        case .photo(let image): image
        }
        let analysis = Task.detached(priority: .userInitiated) { () -> CaughtPet? in
            guard let snapshot else { return nil }
            return try? CaughtPet.make(from: snapshot)
        }

        withAnimation(.spring(duration: 0.4, bounce: 0.6)) {
            orbDrop = 34
            orbScale = 0.7
            orbGlowing = true
        }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.easeOut(duration: 0.3)) { orbGlowing = false }

        for wobble in 1...3 {
            try? await Task.sleep(for: .milliseconds(350))
            Haptics.impact(.light)
            wobbles = wobble
            withAnimation(.easeInOut(duration: 0.12)) { orbWobble = -24 }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeInOut(duration: 0.14)) { orbWobble = 24 }
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(duration: 0.3, bounce: 0.5)) { orbWobble = 0 }
            try? await Task.sleep(for: .milliseconds(250))
        }

        let pet = await analysis.value
        if let pet, Double.random(in: 0..<1) < quality.catchChance {
            Haptics.notify(.success)
            effectPoint = CGPoint(x: point.x, y: point.y + 34)
            burstID = UUID()
            withAnimation(.spring(duration: 0.3, bounce: 0.6)) {
                orbScale = 0.9
                orbGlowing = true
            }
            try? await Task.sleep(for: .milliseconds(900))
            phase = .caught
            withAnimation(.easeOut(duration: 0.25)) {
                orbOpacity = 0
                caught = pet
            }
        } else {
            Haptics.notify(.warning)
            withAnimation(.easeOut(duration: 0.25)) {
                orbScale = 1.5
                orbOpacity = 0
            }
            banner = CatchBanner(text: pet == nil ? "Bé chạy khỏi khung hình rồi!" : "Ơ, bé thoát ra rồi!",
                                 color: Theme.purple)
            try? await Task.sleep(for: .milliseconds(1000))
            resetOrb()
        }
    }

    private func resetOrb() {
        withoutAnimation {
            flight = nil
            progress = 0
            drag = .zero
            orbDrop = 0
            orbWobble = 0
            orbSpin = 0
            orbScale = 0.2
            orbOpacity = 0
            orbGlowing = false
            wobbles = 0
            burstID = nil
            flashID = nil
        }
        withAnimation(.spring(duration: 0.45, bounce: 0.55)) {
            orbScale = 1
            orbOpacity = 1
        }
        phase = .aiming
    }

    private func withoutAnimation(_ changes: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, changes)
    }
}

/// Nút tròn mờ hai bên quả bóng trên thanh dưới.
private struct PanelButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(.white.opacity(0.12), in: Circle())
    }
}
