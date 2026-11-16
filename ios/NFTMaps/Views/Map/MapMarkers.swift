import SwiftUI

/// Nhân vật chạy bộ đứng ở vị trí người chơi (Hero.dc.html: stand / run / cheer).
struct HeroMarker: View {
    enum Pose: String { case stand, run, cheer }
    var pose: Pose = .stand
    @State private var bob = false

    var body: some View {
        Image("hero-\(pose.rawValue)")
            .resizable()
            .scaledToFit()
            .offset(y: bob ? -3 : 0)
            .animation(.easeInOut(duration: pose == .run ? 0.32 : 1.1).repeatForever(autoreverses: true), value: bob)
            .onAppear { bob = true }
            .allowsHitTesting(false)
            .accessibilityLabel("Bạn đang ở đây")
    }

    static let size = CGSize(width: 76, height: 124)
}

/// Mũi ghim tam giác dưới bong bóng.
struct PinTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// Ghim bé trên bản đồ: bé lạ là bong bóng "?" viền màu độ hiếm, bé của mình thì hiện ảnh thật.
struct PetMarker: View {
    let token: MapToken
    let rarity: Rarity
    let isMine: Bool
    let model: MapViewModel
    var isSelected = false

    static let size = CGSize(width: 48, height: 58)

    var body: some View {
        let tint = Theme.rarity(rarity)
        let diameter: CGFloat = rarity == .common ? 36 : 42
        VStack(spacing: -1) {
            ZStack {
                Circle().fill(.white)
                if isMine {
                    OnChainPhoto(token: token, model: model).clipShape(Circle()).padding(3)
                } else {
                    Text("?").font(.game(diameter * 0.52)).foregroundStyle(Theme.rarityText(rarity))
                }
                Circle().strokeBorder(tint, lineWidth: 4)
            }
            .frame(width: diameter, height: diameter)
            .background {
                if rarity != .common { Circle().fill(tint.opacity(0.2)).padding(-6) }
            }
            PinTail().fill(tint).frame(width: 12, height: 10)
        }
        .scaleEffect(isSelected ? 1.18 : 1, anchor: .bottom)
        .shadow(color: Theme.ink.opacity(0.25), radius: 5, y: 4)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isMine ? "\(token.name), \(token.species.displayName), \(rarity.title.lowercased())"
                                   : "Bé lạ, \(rarity.title.lowercased())")
        .accessibilityIdentifier("pin-\(token.id)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Trạm đối tác (tim xanh ngọc) hoặc điểm cho ăn (chân cam bo góc + số bé quanh đó).
struct StationMarker: View {
    let station: Station
    var count: Int?

    static let size = CGSize(width: 58, height: 66)

    var body: some View {
        let partner = station.kind == .partner
        VStack(spacing: -1) {
            ZStack(alignment: .topTrailing) {
                if partner {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.teal, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                } else {
                    PawGlyph()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .frame(width: 50, height: 50)
                        .background(Theme.orange, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white, lineWidth: 4))
                        .background(Theme.orangeDeep, in: .rect(cornerRadius: 16).offset(y: 4))
                    if let count, count > 0 {
                        Text("\(count)")
                            .font(.game(12))
                            .foregroundStyle(.white)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Theme.ink, in: Capsule())
                            .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                            .offset(x: 9, y: -9)
                    }
                }
            }
            PinTail().fill(partner ? Theme.teal : Theme.orange).frame(width: 12, height: 10)
        }
        .shadow(color: Theme.ink.opacity(0.25), radius: 5, y: 4)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(partner ? "Trạm đối tác \(station.name)" : "Điểm cho ăn \(station.name)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Dấu chân PawRun (5 hình bầu dục như logo trong design).
struct PawGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func oval(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> CGRect {
            CGRect(x: rect.minX + (cx - rx) * s, y: rect.minY + (cy - ry) * s, width: rx * 2 * s, height: ry * 2 * s)
        }
        var path = Path()
        path.addEllipse(in: oval(12, 16, 5.2, 4.4))
        path.addEllipse(in: oval(5.5, 10.5, 2.2, 2.8))
        path.addEllipse(in: oval(9.5, 6, 2.2, 2.8))
        path.addEllipse(in: oval(14.5, 6, 2.2, 2.8))
        path.addEllipse(in: oval(18.5, 10.5, 2.2, 2.8))
        return path
    }
}

/// Nút tròn trắng bên phải bản đồ (định vị, lớp…).
struct MapRoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(.white, in: Circle())
                .shadow(color: Theme.ink.opacity(0.14), radius: 7, y: 4)
        }
        .accessibilityLabel(label)
    }
}
