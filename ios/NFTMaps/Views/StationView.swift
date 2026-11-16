import CoreLocation
import SwiftUI

/// Trạm đối tác / điểm cho ăn (Partner.dc.html): mặt tiền quán minh hoạ, thẻ trắng kéo lên với check-in tại chỗ
/// (trong 60 m), góp bữa bằng xu, các bé quanh trạm; dưới cùng Dẫn đường + Check-in.
struct StationView: View {
    let station: Station
    let onGuide: () -> Void

    @Environment(GameStore.self) private var game
    @Environment(MapViewModel.self) private var chain
    @Environment(\.dismiss) private var dismiss
    @State private var here: CLLocationCoordinate2D?
    @State private var located = false
    @State private var notEnoughCoins = false

    private var distance: Double? { here.map { $0.distance(to: station.coordinate) } }
    private var isNear: Bool { (distance ?? .infinity) <= Station.checkInRadius }
    private var feedings: Int { game.feedings(at: station) }
    private var isPartner: Bool { station.kind == .partner }

    /// Bé trên bản đồ trong ~300 m quanh trạm, gần nhất trước.
    private var nearbyPets: [MapToken] {
        chain.visibleTokens
            .map { ($0, $0.coordinate.distance(to: station.coordinate)) }
            .filter { $0.1 < 300 }
            .sorted { $0.1 < $1.1 }
            .prefix(4)
            .map(\.0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                StorefrontScene(name: station.name, partner: isPartner)
                    .frame(height: 300)
                    .accessibilityLabel(isPartner ? "Mặt tiền quán \(station.name)" : "Điểm cho ăn \(station.name)")
                card
                    .padding(.top, -38)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(alignment: .top) { Color(hex: 0xFFE3C8).frame(height: 400) }
        .background(Theme.paper)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
                    .shadow(color: Theme.ink.opacity(0.12), radius: 5, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Xong")
            .padding(.leading, 16)
            .padding(.top, 10)
        }
        .foregroundStyle(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle(station.name)
        .safeAreaInset(edge: .bottom) { actions }
        .task {
            here = await LocationOnce.current()
            located = true
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(station.name)
                .font(.game(30))
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                tag(isPartner ? "Trạm đối tác" : "Điểm cho ăn", foreground: Theme.tealText, background: Theme.tealSoft, weight: .heavy)
                if let distance { tag(GameRules.metersText(distance)) }
                if let hours = station.hours { tag(hours) }
            }
            .padding(.horizontal, 4)

            HStack(spacing: 12) {
                icon("sparkles", Theme.goldText, Theme.goldSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check-in").font(.vn(15, .bold))
                    Text(isNear || here == nil ? "Mỗi ngày 1 lần" : "Lại gần trong \(Int(Station.checkInRadius)) m")
                        .font(.vn(12)).foregroundStyle(Theme.ink2)
                }
                Spacer()
                Text("+\(GameRules.checkInXP) XP")
                    .font(.game(14))
                    .foregroundStyle(Theme.orangeText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Theme.orangeSoft, in: Capsule())
            }
            .padding(12)
            .background(.white, in: .rect(cornerRadius: 20))
            .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    icon("pawprint.fill", Theme.orangeText, Theme.orangeSoft)
                    Text("Góp bữa cho bé").font(.vn(15, .bold))
                    Spacer()
                    Button {
                        notEnoughCoins = !game.feed(at: station)
                        if !notEnoughCoins { Haptics.notify(.success) }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Góp")
                            CoinGlyph().frame(width: 18, height: 18)
                            Text("\(GameRules.feedCost)")
                        }
                        .font(.game(14))
                        .foregroundStyle(Theme.goldText)
                        .padding(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                        .frame(minHeight: 32)
                        .background(Theme.goldSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Góp 1 bữa, \(GameRules.feedCost) xu")
                }
                HStack(spacing: 10) {
                    ProgressBar(value: Double(feedings) / Double(station.feedingGoal), tint: Theme.teal, height: 8)
                    Text(notEnoughCoins ? "Chưa đủ xu" : "\(feedings)/\(station.feedingGoal) bữa")
                        .font(.vn(12, .semibold))
                        .foregroundStyle(notEnoughCoins ? Theme.orangeText : Theme.ink2)
                        .monospacedDigit()
                }
            }
            .padding(12)
            .background(.white, in: .rect(cornerRadius: 20))
            .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)

            if !nearbyPets.isEmpty {
                HStack(spacing: 10) {
                    Text("Bé quanh đây").font(.vn(13, .bold)).foregroundStyle(Theme.ink2)
                    ForEach(nearbyPets) { token in
                        Color.clear
                            .frame(width: 48, height: 48)
                            .overlay { OnChainPhoto(token: token, model: chain) }
                            .clipShape(.rect(cornerRadius: 14))
                            .overlay(alignment: .bottom) {
                                UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                                    .fill(Theme.rarity(chain.rarity(of: token))).frame(height: 4)
                            }
                            .accessibilityLabel(token.name)
                    }
                }
                .padding(.horizontal, 4)
            }

            Text("Bữa góp được tính trên máy bạn. Trạm và số liệu hiện là dữ liệu mẫu.")
                .font(.vn(12)).foregroundStyle(Theme.ink2)
                .padding(.horizontal, 4)
        }
        .padding(EdgeInsets(top: 22, leading: 16, bottom: 20, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Dẫn đường") { onGuide() }.buttonStyle(OutlineButtonStyle())
            if game.hasCheckedIn(station) {
                Label("Đã check-in", systemImage: "checkmark")
                    .font(.game(17))
                    .foregroundStyle(Theme.tealText)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.tealSoft, in: .rect(cornerRadius: 18))
                    .padding(.bottom, 6)
            } else {
                Button("Check-in") {
                    game.checkIn(station)
                    Haptics.notify(.success)
                }
                .buttonStyle(ChunkyButtonStyle(fill: isNear ? Theme.orange : Theme.line,
                                               shadow: isNear ? Theme.orangeDeep : Theme.line,
                                               foreground: isNear ? .white : Theme.ink2))
                .disabled(!isNear)
                .accessibilityHint(isNear ? "" : "Lại gần trong \(Int(Station.checkInRadius)) mét để check-in")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Theme.paper)
    }

    private func tag(_ text: String, foreground: Color = Theme.ink, background: Color = Theme.line,
                     weight: Font.Weight = .bold) -> some View {
        Text(text)
            .font(.vn(12, weight))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }

    private func icon(_ symbol: String, _ foreground: Color, _ background: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: 44, height: 44)
            .background(background, in: .rect(cornerRadius: 14))
    }
}

/// Mặt tiền quán (bản vẽ 390×300 trong Partner.dc.html): mái hiên sọc, biển tên, cửa sổ có bé mèo, cửa, chậu cây.
/// Điểm cho ăn dùng mái xanh ngọc và bé chó.
private struct StorefrontScene: View {
    let name: String
    let partner: Bool

    var body: some View {
        Canvas { context, size in
            let s = size.width / 390
            let dy = size.height - 300 * s  // neo đáy cảnh vào đáy khung
            func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
                CGRect(x: x * s, y: y * s + dy, width: w * s, height: h * s)
            }
            func fill(_ rect: CGRect, _ hex: UInt32, radius: Double = 0) {
                context.fill(Path(roundedRect: rect, cornerRadius: radius * s), with: .color(Color(hex: hex)))
            }
            let accent: UInt32 = partner ? 0xF2690D : 0x0E9F8E
            fill(CGRect(origin: .zero, size: size), 0xFFE3C8)
            fill(r(0, 250, 390, 50 + 40), 0xD8CBB4)
            // Tường quán
            let wall = Path(roundedRect: r(70, 72, 250, 180), cornerRadius: 6 * s)
            context.fill(wall, with: .color(Color(hex: 0xFBF6EA)))
            context.stroke(wall, with: .color(Theme.ink.opacity(0.12)), lineWidth: 3 * s)
            fill(r(60, 62, 270, 18), partner ? 0x0E9F8E : 0xF2690D, radius: 6)
            // Biển tên
            fill(r(110, 88, 170, 30), 0x1E1A4D, radius: 8)
            let sign = r(110, 88, 170, 30)
            context.draw(Text(name).font(.game(17 * s)).foregroundStyle(.white),
                         at: CGPoint(x: sign.midX, y: sign.midY + 1.5 * s), anchor: .center)
            // Mái hiên sọc + diềm tròn
            for index in 0..<10 {
                let color: UInt32 = index.isMultiple(of: 2) ? accent : 0xFFFFFF
                fill(r(70 + Double(index) * 25, 126, 25, 22), color)
                context.fill(Path(ellipseIn: r(70 + Double(index) * 25, 135.5, 25, 25)), with: .color(Color(hex: color)))
            }
            // Cửa sổ có bé
            let window = Path(roundedRect: r(92, 172, 114, 68), cornerRadius: 6 * s)
            context.fill(window, with: .color(Color(hex: 0xA6E8EE)))
            context.draw(Image(partner ? "pet-cat" : "pet-dog"), in: r(120, 182, 56, 56))
            context.stroke(Path { $0.move(to: r(149, 172, 0, 0).origin); $0.addLine(to: r(149, 240, 0, 0).origin) },
                           with: .color(.white.opacity(0.7)), lineWidth: 3 * s)
            context.stroke(window, with: .color(Theme.ink.opacity(0.15)), lineWidth: 3 * s)
            // Cửa ra vào
            fill(r(226, 172, 66, 80), 0xB8692E, radius: 6)
            fill(r(236, 182, 46, 24), 0xA6E8EE, radius: 4)
            context.fill(Path(ellipseIn: r(276.5, 212.5, 7, 7)), with: .color(Color(hex: 0xF7C948)))
            // Chậu cây
            for x in [70.0, 298] {
                fill(r(x, 236, 24, 16), 0xB8692E, radius: 3)
                context.fill(Path(ellipseIn: r(x - 1, 215, 26, 26)), with: .color(Color(hex: 0x4FB043)))
            }
        }
    }
}
