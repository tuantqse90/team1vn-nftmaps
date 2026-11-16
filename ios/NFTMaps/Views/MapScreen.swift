import MapKit
import SwiftUI

/// Bản đồ chính (artboard "Bản đồ"): bản đồ minh hoạ nghiêng, trời hoàng hôn, nhân vật ở vị trí người chơi,
/// bé lạ là bong bóng "?" theo độ hiếm, trạm đối tác / điểm cho ăn, gợi ý vòng chạy ở dưới.
struct MapScreen: View {
    let session: WalletSession
    let account: SmartAccount
    let startRun: () -> Void
    var openQuests: () -> Void = {}

    private enum Selection: Hashable {
        case token(UInt64)
        case station(String)
    }

    private struct LoopSuggestion {
        let plan: RoutePlan
        let place: String?
        let pets: Int
    }

    @Environment(GameStore.self) private var game
    @Environment(MapViewModel.self) private var chain
    @State private var map = PawMapController()
    @State private var selection: Selection?
    @State private var detailToken: MapToken?
    @State private var detailStation: Station?
    @State private var isCatching = false
    @State private var isShowingPending = false
    @State private var route: RoutePlan?
    @State private var isRouting = false
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var loop: LoopSuggestion?
    @State private var loopBearing = 20.0
    @State private var isFlat = false

    /// Trung tâm TP.HCM khi chưa có vị trí.
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009)

    var body: some View {
        ZStack(alignment: .top) {
            PawMap(controller: map, layers: layers, insets: UIEdgeInsets(top: 230, left: 0, bottom: 150, right: 0)) {
                markers
            }
            SkyBackdrop()
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
                .opacity(isFlat ? 0 : 1)
            VStack(spacing: 10) {
                topBar
                HStack {
                    Spacer()
                    sideButtons
                }
                Spacer(minLength: 0)
                bottomArea
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .foregroundStyle(Theme.ink)
        .sheet(item: $detailToken) { token in
            NavigationStack {
                TokenDetailView(token: token, account: account)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Xong") { detailToken = nil } }
                    }
            }
        }
        .sheet(item: $detailStation) { station in
            NavigationStack { StationView(station: station) { guide(to: station.coordinate) } }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isShowingPending) {
            NavigationStack { PendingMintsView(account: account) }
        }
        .captureFlow(isPresented: $isCatching, account: account)
        .task {
            map.look(at: Self.defaultCenter, duration: 0)
            await followLocation()
        }
        .task(id: loopBearing) { await suggestLoop() }
    }

    // MARK: Bản đồ

    private var layers: PawMapLayers {
        var layers = PawMapLayers()
        layers.me = userLocation
        layers.rangeMeters = userLocation == nil ? 0 : 140
        layers.suggested = route?.coordinates ?? loop?.plan.coordinates ?? []
        layers.rings = chain.visibleTokens.map { ($0.coordinate, Theme.rarity(chain.rarity(of: $0))) }
        return layers
    }

    @ViewBuilder
    private var markers: some View {
        // Vẽ điểm xa (phía bắc, cao trên màn hình) trước để điểm gần đè lên.
        ForEach(StationDirectory.all.sorted { $0.latitude > $1.latitude }) { station in
            MapPinned(coordinate: station.coordinate, size: StationMarker.size) {
                Button { select(.station(station.id)) } label: {
                    StationMarker(station: station, count: station.kind == .feeding ? petsNear(station.coordinate) : nil)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(station.name)
            }
        }
        ForEach(chain.visibleTokens.sorted { $0.latitude > $1.latitude }) { token in
            MapPinned(coordinate: token.coordinate, size: PetMarker.size) {
                Button { select(.token(token.id)) } label: {
                    PetMarker(token: token, rarity: chain.rarity(of: token), isMine: token.owner == account.address,
                              model: chain, isSelected: selection == .token(token.id))
                }
                .buttonStyle(.plain)
            }
        }
        if let userLocation {
            MapPinned(coordinate: userLocation, size: HeroMarker.size) { HeroMarker() }
        }
    }

    private func petsNear(_ coordinate: CLLocationCoordinate2D) -> Int {
        chain.visibleTokens.filter { $0.coordinate.distance(to: coordinate) < 400 }.count
    }

    // MARK: Thanh trên

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button(action: {}) {
                    HStack(spacing: 10) {
                        Text(initials)
                            .font(.game(15))
                            .foregroundStyle(Theme.orangeText)
                            .frame(width: 42, height: 42)
                            .background(Color(hex: 0xFFD9BF), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Lv \(game.level)").font(.game(17)).lineLimit(1)
                            ProgressBar(value: game.levelProgress, tint: Theme.purple, height: 8)
                                .frame(width: 96)
                        }
                    }
                    .padding(EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 14))
                    .background(.white, in: Capsule())
                    .shadow(color: Theme.ink.opacity(0.14), radius: 7, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Cấp \(game.level)")
                Spacer(minLength: 4)
                pill {
                    CoinGlyph().frame(width: 22, height: 22)
                    Text(GameRules.number(game.progress.coins)).font(.game(16)).monospacedDigit()
                }
                .accessibilityLabel("\(game.progress.coins) xu")
                pill {
                    FlameGlyph().frame(width: 22, height: 22)
                    Text("\(game.streak)").font(.game(16))
                }
                .accessibilityLabel("Chuỗi \(game.streak) ngày")
            }
            if chain.isOffline {
                offlineBanner
            } else {
                questBar
            }
        }
    }

    private var initials: String {
        let name = session.username.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "BẠN" : String(name.prefix(2)).uppercased()
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 5) { content() }
            .padding(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 12))
            .background(.white, in: Capsule())
            .shadow(color: Theme.ink.opacity(0.14), radius: 7, y: 4)
            .accessibilityElement(children: .combine)
    }

    private var questBar: some View {
        Button(action: openQuests) {
            HStack(spacing: 12) {
                Image(systemName: "flag")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.orangeText)
                    .frame(width: 40, height: 40)
                    .background(Theme.orangeSoft, in: .rect(cornerRadius: 12))
                Text("\(GameRules.number(game.stepsToday)) / \(GameRules.number(DailyQuest.steps.goal)) bước")
                    .font(.vn(14, .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(game.claimedCount)/\(DailyQuest.allCases.count)")
                    .font(.game(15))
                    .foregroundStyle(Theme.orangeText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(Theme.orangeSoft, in: Capsule())
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink2)
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .background(.white, in: .rect(cornerRadius: 20))
            .shadow(color: Theme.ink.opacity(0.14), radius: 7, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Mở nhiệm vụ")
    }

    private var offlineBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.12), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 1) {
                Text("Ngoại tuyến").font(.vn(14, .bold))
                Text("Bản đồ đã lưu").font(.vn(12)).foregroundStyle(Theme.onDark)
            }
            Spacer()
            if !game.progress.pendingMints.isEmpty {
                Text("\(game.progress.pendingMints.count) chờ mint")
                    .font(.game(14)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 2)
                    .background(Theme.gold, in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(Theme.ink, in: .rect(cornerRadius: 20))
    }

    private var sideButtons: some View {
        VStack(spacing: 12) {
            MapRoundButton(symbol: "scope", label: "Về vị trí của tôi") {
                if let userLocation { map.look(at: userLocation) }
            }
            MapRoundButton(symbol: isFlat ? "view.3d" : "square.2.layers.3d", label: isFlat ? "Bản đồ 3D" : "Bản đồ 2D") {
                isFlat.toggle()
                map.pitch = isFlat ? 0 : 56
                map.look(at: map.center ?? userLocation ?? Self.defaultCenter, duration: 0.6)
            }
            Button { isCatching = true } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Theme.orange, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white, lineWidth: 3))
                    .background(Theme.orangeDeep, in: .rect(cornerRadius: 16).offset(y: 4))
            }
            .accessibilityLabel("Chụp bé")
            .accessibilityIdentifier("startCatch")
        }
    }

    // MARK: Phía dưới

    @ViewBuilder
    private var bottomArea: some View {
        VStack(spacing: 10) {
            if !chain.isOffline, !game.progress.pendingMints.isEmpty {
                Button { isShowingPending = true } label: {
                    Label("\(game.progress.pendingMints.count) bé chờ mint · Mint ngay", systemImage: "tray.and.arrow.up.fill")
                        .font(.vn(15, .bold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.gold, in: .rect(cornerRadius: 16))
                        .foregroundStyle(Theme.ink)
                }
            }
            if let selection {
                quickCard(selection)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let route {
                routeCard(route)
            } else if let loop {
                loopCard(loop)
            }
        }
    }

    private func loopCard(_ loop: LoopSuggestion) -> some View {
        HStack(spacing: 14) {
            Button(action: startRun) {
                HStack(spacing: 14) {
                    LoopGlyph()
                        .frame(width: 56, height: 56)
                        .background(Color(hex: 0xC3EA96), in: .rect(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text([loop.place, GameRules.metersText(loop.plan.meters)].compactMap { $0 }.joined(separator: " · "))
                            .font(.game(19)).lineLimit(1).minimumScaleFactor(0.8)
                        Text("~\(max(1, Int(loop.plan.meters / 1000 * 6.5))) phút · \(loop.pets) bé")
                            .font(.vn(13)).foregroundStyle(Theme.ink2)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Chạy vòng này")
            Button { loopBearing += 120 } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 2))
            }
            .accessibilityLabel("Đổi vòng khác")
        }
        .padding(12)
        .background(.white, in: .rect(cornerRadius: 24))
        .shadow(color: Theme.ink.opacity(0.16), radius: 12, y: 4)
    }

    @ViewBuilder
    private func quickCard(_ selection: Selection) -> some View {
        switch selection {
        case .token(let id):
            if let token = chain.tokens.first(where: { $0.id == id }) {
                let rarity = chain.rarity(of: token)
                let mine = token.owner == account.address
                card(title: mine ? token.name : "Bé lạ",
                     chips: AnyView(HStack(spacing: 6) {
                         Text(mine ? rarity.title.uppercased() : "\(rarity.title.uppercased())?")
                             .font(.game(13)).foregroundStyle(.white)
                             .padding(.horizontal, 9).padding(.vertical, 1)
                             .background(Theme.rarity(rarity), in: Capsule())
                         Text(distanceText(to: token.coordinate)).font(.vn(13)).foregroundStyle(Theme.ink2)
                     }),
                     leading: AnyView(PetMarker(token: token, rarity: rarity, isMine: mine, model: chain)
                        .accessibilityHidden(true)),
                     primary: ("Dẫn đường", { guide(to: token.coordinate) }),
                     secondary: mine ? ("Xem bé", { detailToken = token }) : nil)
            }
        case .station(let id):
            if let station = StationDirectory.all.first(where: { $0.id == id }) {
                card(title: station.name,
                     chips: AnyView(HStack(spacing: 6) {
                         Text(station.kind == .partner ? "Trạm đối tác" : "Điểm cho ăn")
                             .font(.vn(12, .bold)).foregroundStyle(Theme.tealText)
                             .lineLimit(1).fixedSize()
                             .padding(.horizontal, 9).padding(.vertical, 2)
                             .background(Theme.tealSoft, in: Capsule())
                         Text(distanceText(to: station.coordinate)).font(.vn(13)).foregroundStyle(Theme.ink2)
                             .lineLimit(1).minimumScaleFactor(0.7)
                     }),
                     leading: AnyView(StationMarker(station: station).accessibilityHidden(true)),
                     primary: ("Dẫn đường", { guide(to: station.coordinate) }),
                     secondary: ("Xem trạm", { detailStation = station }))
            }
        }
    }

    private func card(title: String, chips: AnyView, leading: AnyView,
                      primary: (String, () -> Void), secondary: (String, () -> Void)?) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                leading.frame(width: 58, height: 66)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.game(22)).lineLimit(1)
                    chips
                }
                Spacer()
                Button { withAnimation(.snappy) { selection = nil } } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink2)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Đóng")
            }
            HStack(spacing: 10) {
                if let secondary {
                    Button(secondary.0, action: secondary.1).buttonStyle(OutlineButtonStyle(height: 52))
                }
                Button(action: primary.1) {
                    Label(isRouting ? "Đang tìm…" : primary.0, systemImage: "location.north.fill")
                }
                .buttonStyle(ChunkyButtonStyle(height: 52))
                .disabled(isRouting)
            }
        }
        .padding(14)
        .background(.white, in: .rect(cornerRadius: 26))
        .shadow(color: Theme.ink.opacity(0.2), radius: 14, y: 4)
    }

    private func routeCard(_ route: RoutePlan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.orangeText)
                .frame(width: 52, height: 52)
                .background(Theme.orangeSoft, in: .rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(GameRules.metersText(route.meters)).font(.game(20))
                Text("~\(max(1, Int(route.seconds / 60))) phút đi bộ").font(.vn(13)).foregroundStyle(Theme.ink2)
            }
            Spacer()
            Button("Chạy luôn", action: startRun).buttonStyle(ChunkyButtonStyle(height: 44)).frame(width: 118)
            Button { self.route = nil } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Bỏ tuyến")
        }
        .padding(12)
        .background(.white, in: .rect(cornerRadius: 24))
        .shadow(color: Theme.ink.opacity(0.16), radius: 12, y: 4)
    }

    // MARK: Hành động

    private func select(_ newSelection: Selection) {
        Haptics.impact(.light)
        withAnimation(.snappy) { selection = newSelection }
    }

    private func distanceText(to coordinate: CLLocationCoordinate2D) -> String {
        guard let userLocation else { return "" }
        let meters = userLocation.distance(to: coordinate)
        return "\(GameRules.metersText(meters)) · ~\(max(1, Int(meters / 80))) phút"
    }

    private func guide(to destination: CLLocationCoordinate2D) {
        detailStation = nil
        guard let userLocation else { return }
        isRouting = true
        Task {
            defer { isRouting = false }
            guard let plan = try? await RouteService.walkingRoute(from: userLocation, to: destination) else { return }
            withAnimation(.snappy) {
                route = plan
                selection = nil
            }
            map.fit(plan.coordinates, padding: UIEdgeInsets(top: 60, left: 60, bottom: 60, right: 60))
        }
    }

    private func suggestLoop() async {
        guard let start = await waitForLocation() else { return }
        guard let plan = try? await RouteService.loop(from: start, targetMeters: 3_000, bearing: loopBearing) else { return }
        let pets = chain.visibleTokens.filter { token in
            plan.coordinates.contains { $0.distance(to: token.coordinate) < 80 }
        }.count
        let place = await RouteService.placeName(start)
        withAnimation(.snappy) { loop = LoopSuggestion(plan: plan, place: place, pets: pets) }
    }

    private func waitForLocation() async -> CLLocationCoordinate2D? {
        for _ in 0..<40 {
            if let userLocation { return userLocation }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    /// Lần đầu có vị trí thì bay tới đó, sau đó nhân vật đi theo vị trí thật.
    private func followLocation() async {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard let location = update.location else { continue }
                if userLocation == nil { map.look(at: location.coordinate, duration: 1.0) }
                userLocation = location.coordinate
            }
        } catch {}
    }
}

/// Đồng xu vàng có dấu chân (đơn vị "xu").
struct CoinGlyph: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0xF5B82E))
            Circle().strokeBorder(Color(hex: 0xB37B00), lineWidth: 1.5)
            PawGlyph().fill(Color(hex: 0x8A5A00)).padding(4.5)
        }
        .accessibilityHidden(true)
    }
}

/// Ngọn lửa chuỗi ngày (cam + lõi vàng).
struct FlameGlyph: View {
    var body: some View {
        ZStack {
            Image(systemName: "flame.fill").resizable().scaledToFit().foregroundStyle(Theme.orange)
            Image(systemName: "flame.fill").resizable().scaledToFit().foregroundStyle(Color(hex: 0xFFC14D))
                .scaleEffect(0.45, anchor: .bottom)
        }
        .accessibilityHidden(true)
    }
}

/// Biểu tượng vòng chạy chấm cam (thẻ gợi ý vòng).
struct LoopGlyph: View {
    var body: some View {
        Canvas { context, size in
            let r = CGRect(x: size.width * 0.24, y: size.height * 0.24, width: size.width * 0.52, height: size.height * 0.52)
            context.stroke(Path(roundedRect: r, cornerRadius: 6), with: .color(Theme.orange),
                           style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [0.1, 6.5]))
            let dot = CGRect(x: r.minX - 5, y: r.maxY - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: dot), with: .color(Theme.orange))
            context.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}

extension MKMapRect {
    /// Khung bao các toạ độ (dùng để đặt camera vừa tuyến).
    init(coordinates: [CLLocationCoordinate2D]) {
        let points = coordinates.map(MKMapPoint.init)
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
        self.init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
