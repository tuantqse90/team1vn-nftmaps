import AVFoundation
import CoreLocation
import CoreMotion
import SwiftUI

enum AppTab: Hashable {
    case map, quests, collection, profile
}

/// Khung app sau khi đăng nhập: xin quyền lần đầu, rồi 4 tab + nút CHẠY ở giữa.
struct AppShell: View {
    let session: WalletSession
    let account: SmartAccount

    @State private var game: GameStore
    @State private var chain = MapViewModel()
    @State private var tab: AppTab = .map
    @State private var isRunning = false
    /// Số màn đang đẩy vào NavigationStack muốn ẩn thanh tab (chi tiết bé, cài đặt…), như design.
    @State private var tabBarHiders = 0
    @AppStorage("permissionsDone") private var permissionsDone = false
    @Environment(\.scenePhase) private var scenePhase

    init(session: WalletSession, account: SmartAccount) {
        self.session = session
        self.account = account
        _game = State(initialValue: GameStore(owner: account.address))
    }

    var body: some View {
        Group {
            if permissionsDone {
                content
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if tabBarHiders == 0 {
                            AppTabBar(selection: $tab) { isRunning = true }
                                .transition(.move(edge: .bottom))
                        }
                    }
                    .animation(.snappy(duration: 0.25), value: tabBarHiders == 0)
                    .environment(\.tabBarHider) { tabBarHiders = max(0, tabBarHiders + $0) }
            } else {
                PermissionsView { permissionsDone = true }
            }
        }
        .environment(game)
        .environment(chain)
        .rewardOverlay(game)
        .fullScreenCover(isPresented: $isRunning) {
            RunFlowView(account: account)
                .environment(game)
                .environment(chain)
                .rewardOverlay(game)
        }
        .task { await chain.refresh() }
        .task(id: scenePhase) {
            if scenePhase == .active { await game.refreshSteps() }
        }
        .preferredColorScheme(.light)
        .tint(Theme.orange)
        .font(.vn(15))
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .map:
            MapScreen(session: session, account: account, startRun: { isRunning = true }, openQuests: { tab = .quests })
        case .quests:
            NavigationStack { QuestsView(account: account) }
        case .collection:
            NavigationStack { CollectionView(account: account) { isRunning = true } }
        case .profile:
            NavigationStack { ProfileView(session: session, account: account) }
        }
    }
}

/// Thanh tab (TabBar.dc.html): Bản đồ · Sưu tập · nút CHẠY nổi · Nhiệm vụ · Hồ sơ.
struct AppTabBar: View {
    @Binding var selection: AppTab
    let onRun: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            item(.map, "Bản đồ", "map")
            item(.collection, "Sưu tập", "rectangle.on.rectangle")
            Button(action: onRun) {
                VStack(spacing: 1) {
                    Image(systemName: "figure.run").font(.system(size: 25, weight: .bold))
                    Text("CHẠY").font(.game(14))
                }
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Theme.orange, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 5))
                .background(Theme.orangeDeep, in: Circle().offset(y: 5))
                .shadow(color: Theme.orange.opacity(0.35), radius: 11, y: 10)
                .offset(y: -38)
                .frame(maxWidth: .infinity, maxHeight: 48, alignment: .top)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bắt đầu chạy")
            .accessibilityIdentifier("startRun")
            item(.quests, "Nhiệm vụ", "flag")
            item(.profile, "Hồ sơ", "person")
        }
        .padding(.top, 10)
        .padding(.horizontal, 8)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(.white)
                .shadow(color: Theme.ink.opacity(0.10), radius: 12, y: -6)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ tab: AppTab, _ title: String, _ symbol: String) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 21, weight: .semibold))
                Text(title).font(.vn(11, selected ? .bold : .medium))
            }
            .foregroundStyle(selected ? Theme.orangeText : Color(hex: 0x6E6A8E))
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Xin quyền

struct PermissionsView: View {
    let onDone: () -> Void

    @State private var location = CLLocationManager()
    @State private var locationStatus = CLLocationManager().authorizationStatus
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var motionStatus = CMPedometer.authorizationStatus()

    private var asked: Int {
        [locationStatus != .notDetermined, cameraStatus != .notDetermined, motionStatus != .notDetermined]
            .filter { $0 }.count
    }

    private var granted: Int {
        [[.authorizedWhenInUse, .authorizedAlways].contains(locationStatus), cameraStatus == .authorized,
         motionStatus == .authorized].filter { $0 }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                PermissionsHeroCard()
                HStack {
                    Text("Bật quyền").font(.game(30))
                    Spacer()
                    Text("\(granted)/3")
                        .font(.game(16))
                        .foregroundStyle(Theme.orangeText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .background(Theme.orangeSoft, in: Capsule())
                        .accessibilityLabel("Đã bật \(granted) trên 3 quyền")
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)

                row("Vị trí", "Vẽ đường chạy, tìm bé", "mappin.and.ellipse", tint: Theme.orangeText, soft: Theme.orangeSoft,
                    granted: [.authorizedWhenInUse, .authorizedAlways].contains(locationStatus),
                    asked: locationStatus != .notDetermined) {
                    location.requestWhenInUseAuthorization()
                    await poll { locationStatus = location.authorizationStatus }
                }
                row("Camera", "Chụp bé", "camera", tint: Color(hex: 0x2563D9), soft: Theme.blueSoft,
                    granted: cameraStatus == .authorized, asked: cameraStatus != .notDetermined) {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                    cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                }
                row("Chuyển động", "Đếm bước chân", "shoeprints.fill", tint: Theme.purpleText, soft: Theme.purpleSoft,
                    granted: motionStatus == .authorized, asked: motionStatus != .notDetermined) {
                    await requestMotion()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            // Luôn bấm được (quyền là tuỳ chọn), sáng màu cam khi đã hỏi đủ 3 quyền như design.
            let ready = asked == 3
            Button(action: onDone) { Text("Vào bản đồ").font(.game(21)) }
                .buttonStyle(ChunkyButtonStyle(fill: ready ? Theme.orange : Theme.line,
                                               shadow: ready ? Theme.orangeDeep : .clear,
                                               foreground: ready ? .white : Theme.ink2, height: 58))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityIdentifier("permissionsDone")
        }
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
    }

    private func row(_ title: String, _ detail: String, _ symbol: String, tint: Color, soft: Color,
                     granted: Bool, asked: Bool, request: @escaping () async -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(soft, in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.vn(15, .bold))
                Text(detail).font(.vn(12)).foregroundStyle(Theme.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if granted {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.teal, in: Circle())
                    .accessibilityLabel("Đã bật")
            } else if asked {
                Button("Cài đặt") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.game(16))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 2))
                .accessibilityLabel("Mở Cài đặt để bật \(title.lowercased())")
            } else {
                Button("Bật") { Task { await request() } }
                    .font(.game(16))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Theme.ink, in: .rect(cornerRadius: 14))
                    .accessibilityLabel("Bật \(title.lowercased())")
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 10))
        .background(.white, in: .rect(cornerRadius: 20))
        .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
    }

    /// Chờ người dùng bấm hộp thoại hệ thống (không có callback async cho quyền vị trí).
    private func poll(_ update: @escaping () -> Void) async {
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(500))
            update()
            if locationStatus != .notDetermined { return }
        }
    }

    private func requestMotion() async {
        guard CMPedometer.isStepCountingAvailable() else {
            motionStatus = .restricted
            return
        }
        let pedometer = CMPedometer()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pedometer.queryPedometerData(from: .now.addingTimeInterval(-60), to: .now) { _, _ in
                continuation.resume()
            }
        }
        motionStatus = CMPedometer.authorizationStatus()
    }
}

/// Thẻ minh hoạ đầu màn xin quyền: đồi xanh, nhân vật cổ vũ, 3 huy hiệu vị trí / camera / bước chân.
private struct PermissionsHeroCard: View {
    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / 358
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    context.scaleBy(x: s, y: s)
                    var back = Path()
                    back.move(to: CGPoint(x: 0, y: 150))
                    back.addCurve(to: CGPoint(x: 190, y: 138), control1: CGPoint(x: 70, y: 128), control2: CGPoint(x: 140, y: 146))
                    back.addCurve(to: CGPoint(x: 358, y: 134), control1: CGPoint(x: 250, y: 128), control2: CGPoint(x: 300, y: 146))
                    back.addLine(to: CGPoint(x: 358, y: 206))
                    back.addLine(to: CGPoint(x: 0, y: 206))
                    back.closeSubpath()
                    context.fill(back, with: .color(Color(hex: 0xA9DC8A)))
                    var front = Path()
                    front.move(to: CGPoint(x: 0, y: 170))
                    front.addCurve(to: CGPoint(x: 358, y: 160), control1: CGPoint(x: 90, y: 158), control2: CGPoint(x: 200, y: 176))
                    front.addLine(to: CGPoint(x: 358, y: 206))
                    front.addLine(to: CGPoint(x: 0, y: 206))
                    front.closeSubpath()
                    context.fill(front, with: .color(Color(hex: 0xC3EA96)))
                    context.fill(Path(ellipseIn: CGRect(x: 139, y: 179, width: 80, height: 14)),
                                 with: .color(Color(hex: 0x4E9A38).opacity(0.35)))
                }
                Image("hero-cheer")
                    .resizable().scaledToFit()
                    .frame(width: 92 * s, height: 150 * s)
                    .offset(x: 133 * s, y: 32 * s)
                badge("mappin.and.ellipse", fill: Theme.orange, shadow: Theme.orangeDeep, size: 52 * s, angle: -8)
                    .offset(x: 36 * s, y: 46 * s)
                badge("camera", fill: Theme.blue, shadow: Color(hex: 0x1F4FB0), size: 52 * s, angle: 8)
                    .offset(x: 266 * s, y: 38 * s)
                badge("shoeprints.fill", fill: Theme.purple, shadow: Color(hex: 0x6A2BB0), size: 46 * s, angle: -6)
                    .offset(x: 278 * s, y: 108 * s)
            }
        }
        .aspectRatio(358 / 206, contentMode: .fit)
        .background(Color(hex: 0xFFE3C8))
        .clipShape(.rect(cornerRadius: 28))
        .accessibilityHidden(true)
    }

    private func badge(_ symbol: String, fill: Color, shadow: Color, size: CGFloat, angle: Double) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 4))
            .background(shadow, in: Circle().offset(y: 4))
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - Ăn mừng phần thưởng

extension View {
    func rewardOverlay(_ game: GameStore) -> some View {
        overlay {
            if let reward = game.rewards.first {
                RewardView(event: reward) { game.rewards.removeFirst() }
                    .transition(.opacity.combined(with: .scale(scale: 1.1)))
                    .id(reward.id)
            }
        }
        .animation(.spring(duration: 0.4), value: game.rewards.first?.id)
    }
}

struct RewardView: View {
    let event: RewardEvent
    let onClose: () -> Void

    @State private var appeared = false
    @State private var opened = false

    private var isChest: Bool { if case .chest = event { true } else { false } }
    private var chestClosed: Bool { isChest && !opened }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            RewardRays(spin: appeared)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text(chip)
                        .font(.vn(12, .heavy)).tracking(1.2)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Theme.gold, in: Capsule())
                    Text(title)
                        .font(.game(44))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .padding(.top, 30)
                .padding(.horizontal, 16)

                art
                    .frame(height: 262)
                    .padding(.top, 22)
                    .scaleEffect(appeared ? 1 : 0.4)
                    .animation(.spring(duration: 0.7, bounce: 0.5), value: appeared)

                tiles
                    .padding(.top, 24)
                    .padding(.horizontal, 16)
                Spacer(minLength: 16)
                buttons
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .foregroundStyle(.white)
        }
        .onAppear {
            appeared = true
            Haptics.notify(.success)
        }
    }

    private var chip: String {
        switch event {
        case .levelUp: "LÊN CẤP"
        case .medal: "HUY CHƯƠNG MỚI"
        case .chest: "4/4 NHIỆM VỤ"
        }
    }

    private var title: String {
        switch event {
        case .levelUp(let level): "Cấp \(level)!"
        case .medal(let medal): medal.title
        case .chest: "Rương ngày"
        }
    }

    // MARK: Hình giữa

    @ViewBuilder
    private var art: some View {
        switch event {
        case .levelUp(let level):
            HStack(alignment: .bottom, spacing: 10) {
                Image("hero-cheer").resizable().scaledToFit().frame(width: 106, height: 173)
                LevelShield(level: level).frame(width: 150, height: 170)
            }
            .accessibilityElement()
            .accessibilityLabel("Cấp \(level)")
        case .medal(let medal):
            VStack(spacing: 12) {
                MedalArt(symbol: medal.symbol).frame(width: 180, height: 207)
                Text(medal.detail)
                    .font(.game(15))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 3)
                    .background(Theme.gold, in: Capsule())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Huy chương \(medal.title), \(medal.detail)")
        case .chest:
            ChestArt(open: opened)
                .frame(width: 240, height: 207)
                .rotationEffect(.degrees(chestClosed && appeared ? 2.5 : 0))
                .animation(chestClosed ? .easeInOut(duration: 0.12).repeatCount(7, autoreverses: true).delay(0.6) : .default,
                           value: appeared)
                .accessibilityLabel(opened ? "Rương đã mở" : "Rương đang đóng")
        }
    }

    // MARK: Ô phần thưởng

    private struct Tile: Identifiable {
        enum Icon { case coin, xp, ticket }
        let icon: Icon
        let value: String
        let label: String
        var highlight = false
        var id: String { label }
    }

    private var tileItems: [Tile] {
        switch event {
        case .levelUp: [Tile(icon: .coin, value: "+\(GameRules.levelUpCoins)", label: "coin")]
        case .medal: [Tile(icon: .xp, value: "+\(GameRules.medalXP)", label: "XP"),
                      Tile(icon: .coin, value: "+\(GameRules.medalCoins)", label: "coin")]
        case .chest(let coins, let xp, let tickets):
            [Tile(icon: .coin, value: "+\(coins)", label: "coin"), Tile(icon: .xp, value: "+\(xp)", label: "XP"),
             Tile(icon: .ticket, value: "x2 XP", label: "\(tickets) vé", highlight: true)]
        }
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            ForEach(Array(tileItems.enumerated()), id: \.element.id) { index, tile in
                Group {
                    if chestClosed {
                        Text("?")
                            .font(.game(36))
                            .foregroundStyle(Theme.onDark)
                            .frame(maxWidth: .infinity, minHeight: 112)
                            .overlay(RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(.white.opacity(0.28), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                            .accessibilityLabel("Phần thưởng chưa mở")
                    } else {
                        tileView(tile)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                            .animation(.spring(duration: 0.5, bounce: 0.45).delay(Double(index) * 0.12), value: opened)
                    }
                }
                .frame(maxWidth: tileItems.count == 1 ? 116 : .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tileView(_ tile: Tile) -> some View {
        VStack(spacing: 5) {
            Group {
                switch tile.icon {
                case .coin:
                    CoinGlyph()
                case .xp:
                    Text("XP").font(.game(13)).foregroundStyle(Theme.purpleText)
                        .frame(width: 36, height: 36).background(Theme.purpleSoft, in: Circle())
                case .ticket:
                    Image(systemName: "ticket").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36).background(Theme.gold, in: Circle())
                }
            }
            .frame(width: 36, height: 36)
            Text(tile.value).font(.game(20)).lineLimit(1).minimumScaleFactor(0.7)
            Text(tile.label).font(.vn(11)).foregroundStyle(Theme.onDark)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(tile.highlight ? Theme.gold.opacity(0.14) : .white.opacity(0.08), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(tile.highlight ? Theme.gold : .white.opacity(0.14), lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.value) \(tile.label)")
    }

    // MARK: Nút

    @ViewBuilder
    private var buttons: some View {
        if chestClosed {
            Button {
                Haptics.impact(.medium)
                withAnimation(.spring(duration: 0.5, bounce: 0.4)) { opened = true }
            } label: { Text("Mở rương").font(.game(22)) }
                .buttonStyle(ChunkyButtonStyle(fill: Theme.gold, shadow: Theme.goldDeep, foreground: Theme.ink, height: 62))
                .accessibilityIdentifier("claimReward")
        } else if case .medal(let medal) = event {
            HStack(spacing: 10) {
                ShareLink(item: "Mình vừa nhận huy chương \(medal.title) (\(medal.detail)) trên PawRun!") {
                    Label("Khoe", systemImage: "square.and.arrow.up").font(.game(19))
                }
                .buttonStyle(RewardOutlineStyle())
                continueButton
            }
        } else {
            continueButton
        }
    }

    private var continueButton: some View {
        Button(action: onClose) { Text("Tiếp tục").font(.game(22)) }
            .buttonStyle(ChunkyButtonStyle(height: 62))
            .accessibilityIdentifier("claimReward")
    }
}

/// Nút viền trắng trên nền mực (nút "Khoe").
private struct RewardOutlineStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 62)
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white, lineWidth: 3))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .padding(.bottom, 6)
    }
}

/// Tia nắng vàng + giấy màu của màn thưởng (Reward.dc.html), tâm ở 345/844 chiều cao.
private struct RewardRays: View {
    let spin: Bool

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / 390
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 345 / 844)
            ZStack {
                Canvas { context, size in
                    let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                    for (r, alpha) in [(175.0, 0.07), (115.0, 0.08)] {
                        context.fill(Path(ellipseIn: CGRect(x: mid.x - r * s, y: mid.y - r * s, width: r * 2 * s, height: r * 2 * s)),
                                     with: .color(Theme.gold.opacity(alpha)))
                    }
                    var rays = Path()
                    let length = max(size.width, size.height) / 2
                    for k in 0..<12 {
                        var wedge = Path()
                        wedge.move(to: .zero)
                        wedge.addLine(to: CGPoint(x: -25 * s * length / (345 * s), y: -length))
                        wedge.addLine(to: CGPoint(x: 25 * s * length / (345 * s), y: -length))
                        wedge.closeSubpath()
                        let transform = CGAffineTransform(translationX: mid.x, y: mid.y).rotated(by: Double(k) * .pi / 6)
                        rays.addPath(wedge.applying(transform))
                    }
                    context.fill(rays, with: .color(Theme.gold.opacity(0.10)))
                }
                .frame(width: 900 * s, height: 900 * s)
                .rotationEffect(.degrees(spin ? 30 : 0))
                .animation(.linear(duration: 14).repeatForever(autoreverses: false), value: spin)
                .position(center)

                Canvas { context, _ in
                    context.scaleBy(x: s, y: s)
                    let confetti: [(Double, Double, Double, Double, Double, UInt32)] = [
                        (40, 150, 10, 16, 20, 0xF2690D), (334, 128, 10, 16, -25, 0x2F6FEB), (64, 270, 8, 14, 40, 0x0E9F8E),
                        (318, 262, 8, 14, -35, 0xF7C948), (104, 64, 8, 12, -15, 0x8B3FE0), (282, 58, 8, 12, 30, 0x0E9F8E),
                        (28, 410, 10, 14, 60, 0xF7C948), (352, 400, 10, 14, -50, 0xF2690D),
                    ]
                    for (x, y, w, h, angle, color) in confetti {
                        var piece = context
                        piece.translateBy(x: x + w / 2, y: y + h / 2)
                        piece.rotate(by: .degrees(angle))
                        piece.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 2),
                                   with: .color(Color(hex: color)))
                    }
                    for (x, y, r, color) in [(60.0, 214.0, 5.0, UInt32(0xF7C948)), (332, 200, 5, 0xF2690D), (96, 440, 4, 0x2F6FEB),
                                             (300, 452, 4, 0x8B3FE0)] {
                        context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(Color(hex: color)))
                    }
                }
                .frame(width: proxy.size.width, height: 844 * s)
                .position(x: proxy.size.width / 2, y: center.y - (345 - 422) * s)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Rương gỗ (đóng / mở) theo SVG 220×190 của design.
private struct ChestArt: View {
    let open: Bool
    private let outline = Color(hex: 0x120F2E)

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 220, y: size.height / 190)
            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ fill: UInt32, stroke: Double = 4, radius: Double = 0) {
                let path = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius)
                context.fill(path, with: .color(Color(hex: fill)))
                context.stroke(path, with: .color(outline), lineWidth: stroke)
            }
            context.fill(Path(ellipseIn: CGRect(x: 24, y: 169, width: 172, height: 18)), with: .color(.black.opacity(0.25)))
            if open {
                var glow = Path()
                for (a, b, c) in [(64.0, 24.0, 84.0), (104, 96, 132), (150, 148, 206)] {
                    glow.move(to: CGPoint(x: a, y: 94))
                    glow.addLine(to: CGPoint(x: b, y: 0))
                    glow.addLine(to: CGPoint(x: c, y: 0))
                    glow.closeSubpath()
                }
                context.fill(glow, with: .color(Color(hex: 0xFFE08A).opacity(0.5)))
                var lid = Path()
                lid.move(to: CGPoint(x: 34, y: 92))
                lid.addLine(to: CGPoint(x: 46, y: 30))
                lid.addCurve(to: CGPoint(x: 174, y: 30), control1: CGPoint(x: 70, y: 18), control2: CGPoint(x: 150, y: 18))
                lid.addLine(to: CGPoint(x: 186, y: 92))
                lid.closeSubpath()
                context.fill(lid, with: .color(Color(hex: 0xD07A38)))
                context.stroke(lid, with: .color(outline), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
                var inside = Path()
                inside.move(to: CGPoint(x: 50, y: 88))
                inside.addLine(to: CGPoint(x: 58, y: 42))
                inside.addCurve(to: CGPoint(x: 162, y: 42), control1: CGPoint(x: 80, y: 34), control2: CGPoint(x: 140, y: 34))
                inside.addLine(to: CGPoint(x: 170, y: 88))
                inside.closeSubpath()
                context.fill(inside, with: .color(Color(hex: 0x8E4E20)))
                rect(28, 88, 164, 16, 0x5A2D12, stroke: 5)
                for (cx, cy, r) in [(78.0, 88.0, 13.0), (140, 86, 12)] {
                    let coin = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                    context.fill(coin, with: .color(Color(hex: 0xF5B82E)))
                    context.stroke(coin, with: .color(Color(hex: 0xB37B00)), lineWidth: 3)
                }
                var gem = Path()
                gem.move(to: CGPoint(x: 108, y: 62))
                gem.addLine(to: CGPoint(x: 122, y: 76))
                gem.addLine(to: CGPoint(x: 108, y: 96))
                gem.addLine(to: CGPoint(x: 94, y: 76))
                gem.closeSubpath()
                context.fill(gem, with: .color(Color(hex: 0x5FCAD9)))
                context.stroke(gem, with: .color(outline), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                rect(28, 100, 164, 72, 0xB8692E, stroke: 5, radius: 12)
                var planks = Path()
                planks.move(to: CGPoint(x: 32, y: 128)); planks.addLine(to: CGPoint(x: 188, y: 128))
                planks.move(to: CGPoint(x: 32, y: 152)); planks.addLine(to: CGPoint(x: 188, y: 152))
                context.stroke(planks, with: .color(Color(hex: 0x8E4E20)), lineWidth: 4)
                rect(54, 102, 16, 68, 0xF7C948)
                rect(150, 102, 16, 68, 0xF7C948)
                rect(92, 104, 36, 30, 0xF7C948, radius: 7)
            } else {
                rect(28, 88, 164, 84, 0xB8692E, stroke: 5, radius: 12)
                var planks = Path()
                planks.move(to: CGPoint(x: 32, y: 118)); planks.addLine(to: CGPoint(x: 188, y: 118))
                planks.move(to: CGPoint(x: 32, y: 146)); planks.addLine(to: CGPoint(x: 188, y: 146))
                context.stroke(planks, with: .color(Color(hex: 0x8E4E20)), lineWidth: 4)
                rect(54, 90, 16, 80, 0xF7C948)
                rect(150, 90, 16, 80, 0xF7C948)
                var lid = Path()
                lid.move(to: CGPoint(x: 28, y: 92))
                lid.addLine(to: CGPoint(x: 28, y: 70))
                lid.addCurve(to: CGPoint(x: 192, y: 70), control1: CGPoint(x: 28, y: 34), control2: CGPoint(x: 192, y: 34))
                lid.addLine(to: CGPoint(x: 192, y: 92))
                lid.closeSubpath()
                context.fill(lid, with: .color(Color(hex: 0xD07A38)))
                context.stroke(lid, with: .color(outline), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
                rect(28, 82, 164, 12, 0xF7C948)
                var shine = Path()
                shine.move(to: CGPoint(x: 46, y: 64))
                shine.addCurve(to: CGPoint(x: 98, y: 46), control1: CGPoint(x: 62, y: 50), control2: CGPoint(x: 82, y: 46))
                context.stroke(shine, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                rect(92, 80, 36, 40, 0xF7C948, radius: 7)
                context.fill(Path(ellipseIn: CGRect(x: 105, y: 91, width: 10, height: 10)), with: .color(outline))
                var keyhole = Path()
                keyhole.move(to: CGPoint(x: 110, y: 99)); keyhole.addLine(to: CGPoint(x: 110, y: 110))
                context.stroke(keyhole, with: .color(outline), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        }
    }
}

/// Khiên cấp (150×170): tím viền vàng, số cấp to, ruy băng "CẤP".
private struct LevelShield: View {
    let level: Int

    var body: some View {
        ZStack {
            Canvas { context, size in
                context.scaleBy(x: size.width / 150, y: size.height / 170)
                func shield(_ top: Double, _ side: Double, _ shoulder: Double, _ bottom: Double) -> Path {
                    var path = Path()
                    path.move(to: CGPoint(x: 75, y: top))
                    path.addLine(to: CGPoint(x: 150 - side, y: shoulder))
                    path.addLine(to: CGPoint(x: 150 - side, y: 88))
                    path.addCurve(to: CGPoint(x: 75, y: bottom), control1: CGPoint(x: 150 - side, y: 130 - (side - 10)),
                                  control2: CGPoint(x: 112 - (side - 10) * 0.6, y: bottom - 10))
                    path.addCurve(to: CGPoint(x: side, y: 88), control1: CGPoint(x: 38 + (side - 10) * 0.6, y: bottom - 10),
                                  control2: CGPoint(x: side, y: 130 - (side - 10)))
                    path.addLine(to: CGPoint(x: side, y: shoulder))
                    path.closeSubpath()
                    return path
                }
                let outer = shield(6, 10, 30, 164)
                context.fill(outer, with: .color(Theme.purple))
                context.stroke(outer, with: .color(Theme.gold), style: StrokeStyle(lineWidth: 7, lineJoin: .round))
                context.fill(shield(22, 24, 41, 148), with: .color(Color(hex: 0xA35CF0)))
                var ribbon = Path()
                ribbon.move(to: CGPoint(x: 18, y: 124))
                ribbon.addLine(to: CGPoint(x: 132, y: 124))
                ribbon.addLine(to: CGPoint(x: 124, y: 138))
                ribbon.addLine(to: CGPoint(x: 132, y: 152))
                ribbon.addLine(to: CGPoint(x: 18, y: 152))
                ribbon.addLine(to: CGPoint(x: 26, y: 138))
                ribbon.closeSubpath()
                context.fill(ribbon, with: .color(Theme.gold))
                context.stroke(ribbon, with: .color(Color(hex: 0x120F2E)), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            }
            GeometryReader { proxy in
                let k = proxy.size.width / 150
                Text("\(level)")
                    .font(.game(66 * k))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(width: 104 * k)
                    .position(x: 75 * k, y: 86 * k)
                Text("CẤP")
                    .font(.vn(13 * k, .heavy)).tracking(2)
                    .foregroundStyle(Theme.ink)
                    .position(x: 75 * k, y: 139 * k)
            }
        }
    }
}

/// Huy chương vàng (viewBox 200×230): ruy băng cam/xanh, đĩa vàng, biểu tượng huy chương ở giữa.
private struct MedalArt: View {
    let symbol: String

    var body: some View {
        GeometryReader { proxy in
            let k = proxy.size.width / 200
            ZStack {
                Canvas { context, _ in
                    context.scaleBy(x: k, y: k)
                    var left = Path()
                    left.addLines([CGPoint(x: 62, y: 0), CGPoint(x: 98, y: 0), CGPoint(x: 118, y: 98), CGPoint(x: 82, y: 98)])
                    left.closeSubpath()
                    context.fill(left, with: .color(Theme.orange))
                    var right = Path()
                    right.addLines([CGPoint(x: 138, y: 0), CGPoint(x: 102, y: 0), CGPoint(x: 82, y: 98), CGPoint(x: 118, y: 98)])
                    right.closeSubpath()
                    context.fill(right, with: .color(Theme.blue))
                    let disc = Path(ellipseIn: CGRect(x: 30, y: 80, width: 140, height: 140))
                    context.fill(disc, with: .color(Color(hex: 0xF5B82E)))
                    context.stroke(disc, with: .color(Color(hex: 0xB37B00)), lineWidth: 6)
                    let inner = Path(ellipseIn: CGRect(x: 48, y: 98, width: 104, height: 104))
                    context.fill(inner, with: .color(Theme.gold))
                    context.stroke(inner, with: .color(Color(hex: 0xE0A21C)), lineWidth: 3)
                }
                Image(systemName: symbol)
                    .font(.system(size: 50 * k, weight: .bold))
                    .foregroundStyle(Theme.goldText)
                    .position(x: 100 * k, y: 150 * k)
                Image(systemName: "sparkle").font(.system(size: 16 * k)).foregroundStyle(.white)
                    .position(x: 20 * k, y: 102 * k)
                Image(systemName: "sparkle").font(.system(size: 11 * k)).foregroundStyle(.white)
                    .position(x: 172 * k, y: 183 * k)
            }
        }
    }
}


extension EnvironmentValues {
    /// +1 khi một màn muốn ẩn thanh tab hiện ra, −1 khi nó biến mất.
    @Entry var tabBarHider: (Int) -> Void = { _ in }
}

private struct HidesTabBar: ViewModifier {
    @Environment(\.tabBarHider) private var tabBarHider

    func body(content: Content) -> some View {
        content
            .onAppear { tabBarHider(1) }
            .onDisappear { tabBarHider(-1) }
    }
}

extension View {
    /// Màn đẩy vào từ tab (chi tiết bé, cài đặt…) không có thanh tab, nút cuối màn không bị che.
    func hidesTabBar() -> some View { modifier(HidesTabBar()) }
}
