import CoreLocation
import SwiftUI

/// Màn đang chạy (artboard "Đang chạy"): bản đồ minh hoạ, nhân vật dáng chạy, HUD số mét to, bé ở gần,
/// thẻ thử thách đếm ngược, thanh dưới có nút CHỤP lớn.
struct RunView: View {
    let tracker: RunTracker
    let suggestedRoute: RoutePlan?
    let account: SmartAccount
    let onFinish: () -> Void
    let onCancel: () -> Void

    @Environment(MapViewModel.self) private var chain
    @State private var map = PawMapController()
    @State private var here: CLLocationCoordinate2D?
    @State private var isCatching = false
    @State private var confirmFinish = false
    @State private var done: (title: String, reward: String)?

    private var position: CLLocationCoordinate2D? { tracker.route.last ?? here }

    var body: some View {
        ZStack(alignment: .top) {
            PawMap(controller: map, layers: layers, insets: UIEdgeInsets(top: 300, left: 0, bottom: 200, right: 0)) {
                ForEach(nearbyTokens) { token in
                    MapPinned(coordinate: token.coordinate, size: PetMarker.size) {
                        Button { isCatching = true } label: {
                            PetMarker(token: token, rarity: chain.rarity(of: token),
                                      isMine: token.owner == account.address, model: chain)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let position {
                    MapPinned(coordinate: position, size: CGSize(width: 80, height: 131)) {
                        HeroMarker(pose: tracker.phase == .paused ? .stand : .run)
                    }
                }
            }
            SkyBackdrop()
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
            VStack(spacing: 10) {
                hud
                if let near = nearestPet { nearbyPill(near) }
                chips
                Spacer(minLength: 0)
                challengeArea
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 18)
        }
        .foregroundStyle(Theme.ink)
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .captureFlow(isPresented: $isCatching, account: account) { tracker.petMet() }
        .confirmationDialog("Kết thúc vòng chạy?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Kết thúc", action: onFinish)
            Button("Bỏ vòng này", role: .destructive, action: onCancel)
            Button("Chạy tiếp", role: .cancel) {}
        }
        .onChange(of: tracker.eventSerial) { show(tracker.lastEvent) }
        // Bám người chạy (camera nghiêng, nhân vật ở giữa phần bản đồ còn trống).
        .onChange(of: tracker.route.count) {
            if let last = tracker.route.last { follow(last) }
        }
        .task {
            map.zoom = 17.4
            if let start = suggestedRoute?.coordinates.first { follow(start, animated: false) }
            if tracker.route.isEmpty, let location = await LocationOnce.current(timeout: .seconds(8)) {
                here = location
                follow(location)
            }
        }
        .preferredColorScheme(.light)
    }

    private func follow(_ coordinate: CLLocationCoordinate2D, animated: Bool = true) {
        map.look(at: coordinate, duration: animated ? 0.6 : 0)
    }

    private var layers: PawMapLayers {
        var layers = PawMapLayers()
        layers.suggested = suggestedRoute?.coordinates ?? []
        layers.track = tracker.route
        layers.me = position
        layers.rings = nearbyTokens.map { ($0.coordinate, Theme.rarity(chain.rarity(of: $0))) }
        return layers
    }

    /// Bé trên bản đồ trong ~600 m quanh người chạy.
    private var nearbyTokens: [MapToken] {
        guard let position else { return [] }
        return chain.visibleTokens.filter { $0.coordinate.distance(to: position) < 600 }
            .sorted { $0.latitude > $1.latitude }
    }

    /// Bé lạ gần nhất trong 300 m (gợi ý dừng lại chụp).
    private var nearestPet: (token: MapToken, meters: Double)? {
        guard let position else { return nil }
        return chain.visibleTokens
            .filter { $0.owner != account.address }
            .map { (token: $0, meters: $0.coordinate.distance(to: position)) }
            .filter { $0.meters < 300 }
            .min { $0.meters < $1.meters }
    }

    // MARK: HUD

    private var hud: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(GameRules.number(Int(tracker.meters)))
                        .font(.game(52))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("m").font(.game(20, .bold)).foregroundStyle(Theme.onDark)
                    if tracker.phase == .paused {
                        Text("TẠM DỪNG")
                            .font(.vn(10, .heavy)).tracking(0.8)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.orange, in: Capsule())
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Image(systemName: "shoeprints.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.gold)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(GameRules.number(tracker.steps)).font(.game(24)).monospacedDigit()
                        Text("bước").font(.vn(11)).foregroundStyle(Theme.onDark)
                    }
                }
                .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 12))
                .background(.white.opacity(0.10), in: .rect(cornerRadius: 16))
            }
            milestoneBar
            HStack(alignment: .firstTextBaseline) {
                stat(GameRules.paceText(secondsPerKm: tracker.secondsPerKm), unit: "/km")
                Spacer()
                stat(GameRules.durationText(tracker.elapsed), unit: "phút")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("còn").font(.vn(11)).foregroundStyle(Theme.onDark)
                    Text(tracker.remainingText).font(.game(20)).monospacedDigit()
                }
            }
        }
        .foregroundStyle(.white)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(Theme.ink, in: .rect(cornerRadius: 26))
        .shadow(color: Theme.ink.opacity(0.35), radius: 12, y: 8)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.game(20)).monospacedDigit()
            Text(unit).font(.vn(11)).foregroundStyle(Theme.onDark)
        }
    }

    /// Thanh tiến độ có 2 mốc (1/3, 2/3 mục tiêu) và cờ đích như design.
    private var milestoneBar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let progress = min(max(tracker.goalProgress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14)).frame(height: 8)
                Capsule().fill(Theme.orange).frame(width: max(width * progress, progress > 0 ? 8 : 0), height: 8)
                ForEach([1.0 / 3, 2.0 / 3], id: \.self) { mark in
                    let passed = progress >= mark
                    Circle()
                        .fill(passed ? Theme.orange : Theme.ink)
                        .overlay(Circle().strokeBorder(passed ? Color.white : Color.white.opacity(0.35), lineWidth: 2))
                        .overlay {
                            if passed {
                                Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 18, height: 18)
                        .offset(x: width * mark - 9)
                }
                Image(systemName: "flag.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 20, height: 20)
                    .background(Theme.ink, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 2))
                    .offset(x: width - 20)
            }
        }
        .frame(height: 20)
    }

    private func nearbyPill(_ near: (token: MapToken, meters: Double)) -> some View {
        let rarity = chain.rarity(of: near.token)
        return Button { isCatching = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.rarity(rarity))
                    .frame(width: 32, height: 32)
                    .background(Theme.rarity(rarity).opacity(0.14), in: Circle())
                Text("Bé ở gần · \(GameRules.metersText(near.meters))")
                    .font(.game(17))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(rarity.title.uppercased())?")
                    .font(.vn(11, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Theme.rarity(rarity), in: Capsule())
            }
            .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 10))
            .background(.white, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.rarity(rarity), lineWidth: 3))
            .shadow(color: Theme.ink.opacity(0.16), radius: 9, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Mở camera để bắt bé")
    }

    private var chips: some View {
        HStack(spacing: 8) {
            if tracker.combo > 1 {
                chip(background: Theme.ink, foreground: .white) {
                    Image(systemName: "flame.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.orange)
                    Text(String(format: "x%.2g", tracker.combo))
                }
                .accessibilityLabel(String(format: "Combo x%.2g", tracker.combo))
            }
            chip {
                PawGlyph().fill(Theme.orange).frame(width: 15, height: 15)
                Text("\(tracker.petsMet)")
            }
            .accessibilityLabel("\(tracker.petsMet) bé đã gặp")
            chip(foreground: Theme.purpleText) { Text("+\(tracker.xp) XP") }
            if tracker.doubleXP {
                chip(background: Theme.purple, foreground: .white) {
                    Image(systemName: "ticket.fill").font(.system(size: 11, weight: .bold))
                    Text("x2")
                }
            }
            Spacer()
        }
    }

    private func chip<Content: View>(background: Color = .white, foreground: Color = Theme.ink,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 5) { content() }
            .font(.game(15))
            .foregroundStyle(foreground)
            .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 12))
            .background(background, in: Capsule())
            .shadow(color: Theme.ink.opacity(0.14), radius: 6, y: 3)
            .accessibilityElement(children: .combine)
    }

    // MARK: Thử thách

    @ViewBuilder
    private var challengeArea: some View {
        if let done {
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 42, height: 42)
                    .background(Theme.ink, in: Circle())
                Text(done.title).font(.game(21)).frame(maxWidth: .infinity, alignment: .leading)
                Text(done.reward)
                    .font(.game(15)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Theme.ink, in: Capsule())
            }
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 14))
            .background(Theme.gold, in: .rect(cornerRadius: 20))
            .background(Theme.goldDeep, in: .rect(cornerRadius: 20).offset(y: 5))
            .accessibilityElement(children: .combine)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else if let challenge = tracker.challenge {
            challengeCard(challenge)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func challengeCard(_ challenge: RunChallenge) -> some View {
        let sprint = challenge.kind == .sprint
        let tint = sprint ? Theme.orange : Theme.teal
        let secondsLeft = challenge.secondsLeft(at: tracker.elapsed)
        return HStack(spacing: 12) {
            if sprint {
                ZStack {
                    Circle().fill(Theme.orangeSoft)
                    Circle().trim(from: 0, to: secondsLeft / max(challenge.timeLimit, 1))
                        .stroke(Theme.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2.5)
                    Text("\(Int(secondsLeft.rounded(.up)))")
                        .font(.game(17)).foregroundStyle(Theme.orangeText).monospacedDigit()
                }
                .frame(width: 44, height: 44)
            } else {
                VStack(spacing: -2) {
                    Text(GameRules.paceText(secondsPerKm: challenge.timeLimit / challenge.targetMeters * 1000))
                        .font(.game(13))
                    Text("/km").font(.vn(9, .semibold))
                }
                .foregroundStyle(Theme.tealText)
                .frame(width: 44, height: 44)
                .background(Theme.tealSoft, in: Circle())
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(challenge.kind.title).font(.game(17)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(Int(challenge.covered(at: tracker.meters)))/\(Int(challenge.targetMeters))")
                        .font(.vn(12, .semibold)).foregroundStyle(Theme.ink2).monospacedDigit()
                }
                ProgressBar(value: challenge.progress(at: tracker.meters), tint: tint, height: 8)
                    .frame(height: 8)
            }
            Text("+\(GameRules.challengeXP(challenge.kind)) XP")
                .font(.game(14)).foregroundStyle(Theme.purpleText)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Theme.purpleSoft, in: Capsule())
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .background(.white, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(tint, lineWidth: 3))
        .overlay(alignment: .topLeading) {
            Text("THỬ THÁCH")
                .font(.vn(10, .heavy)).tracking(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.ink, in: Capsule())
                .offset(x: 14, y: -11)
        }
        .shadow(color: Theme.ink.opacity(0.16), radius: 9, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thử thách \(challenge.kind.title), \(Int(challenge.covered(at: tracker.meters))) trên \(Int(challenge.targetMeters)) mét")
    }

    // MARK: Điều khiển

    private var controls: some View {
        HStack(alignment: .top) {
            Button {
                tracker.phase == .paused ? tracker.resume() : tracker.pause()
            } label: {
                Image(systemName: tracker.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 64, height: 64)
                    .background(Theme.line, in: Circle())
            }
            .accessibilityLabel(tracker.phase == .paused ? "Chạy tiếp" : "Tạm dừng")
            Spacer()
            Button { isCatching = true } label: {
                VStack(spacing: 0) {
                    Image(systemName: "camera.fill").font(.system(size: 28, weight: .bold))
                    Text("CHỤP").font(.game(15))
                }
                .foregroundStyle(.white)
                .frame(width: 100, height: 100)
                .background(Theme.orange, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 6))
                .background(Theme.orangeDeep, in: Circle().offset(y: 6))
                .shadow(color: Theme.orange.opacity(0.35), radius: 12, y: 10)
            }
            .buttonStyle(.plain)
            .offset(y: -50)
            .accessibilityLabel("Chụp bé")
            Spacer()
            Button { confirmFinish = true } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .frame(width: 64, height: 64)
                    .background(Theme.ink, in: Circle())
            }
            .accessibilityLabel("Về đích")
            .accessibilityIdentifier("finishRun")
        }
        .padding(EdgeInsets(top: 20, leading: 36, bottom: 6, trailing: 36))
        .frame(height: 100, alignment: .top)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                .fill(.white)
                .shadow(color: Theme.ink.opacity(0.12), radius: 12, y: -6)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func show(_ event: RunChallengeEngine.Event?) {
        guard let event else { return }
        switch event {
        case .completed(let kind):
            withAnimation(.spring(duration: 0.45, bounce: 0.4)) {
                done = ("Hoàn thành!", "+\(GameRules.challengeXP(kind)) XP")
            }
        case .failed:
            withAnimation(.spring) { done = ("Hụt rồi, lần sau nhé", "0 XP") }
        case .started:
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation { done = nil }
        }
    }
}
