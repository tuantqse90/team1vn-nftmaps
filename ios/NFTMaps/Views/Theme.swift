import SwiftUI

/// Bảng màu và thành phần dùng chung, theo design PawRun (cam + mực tím đậm + nền giấy).
enum Theme {
    static let orange = Color(hex: 0xF2690D)
    static let orangeDeep = Color(hex: 0xB9480A)
    static let orangeText = Color(hex: 0xC2410C)
    static let orangeSoft = Color(hex: 0xFFEDE0)
    static let ink = Color(hex: 0x1E1A4D)
    static let ink2 = Color(hex: 0x5F5A84)
    static let paper = Color(hex: 0xFBF7F0)
    static let line = Color(hex: 0xECE7F7)
    static let teal = Color(hex: 0x0E9F8E)
    static let tealText = Color(hex: 0x0B7A6E)
    static let tealSoft = Color(hex: 0xDDF5F1)
    static let purple = Color(hex: 0x8B3FE0)
    static let purpleText = Color(hex: 0x7C34D1)
    static let purpleSoft = Color(hex: 0xF1E8FD)
    static let blue = Color(hex: 0x2F6FEB)
    static let blueSoft = Color(hex: 0xE6EEFF)
    static let gold = Color(hex: 0xF7C948)
    static let goldDeep = Color(hex: 0xC99A12)
    static let goldText = Color(hex: 0x8A5A00)
    static let goldSoft = Color(hex: 0xFFF3CF)
    static let night = Color(hex: 0x15122E)
    static let onDark = Color(hex: 0xC9C6E0)

    static func rarity(_ rarity: Rarity) -> Color {
        switch rarity {
        case .common: Color(hex: 0x8C93A8)
        case .rare: blue
        case .epic: purple
        case .legend: Color(hex: 0xF0A818)
        }
    }

    static func rarityText(_ rarity: Rarity) -> Color {
        switch rarity {
        case .common: Color(hex: 0x5F667A)
        case .rare: Color(hex: 0x2563D9)
        case .epic: purpleText
        case .legend: Color(hex: 0x946200)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

extension Font {
    /// Chữ tiêu đề / con số kiểu game: Baloo 2 (đúng design PawRun).
    static func game(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        let name = switch weight {
        case .heavy, .black: "Baloo2-ExtraBold"
        case .bold: "Baloo2-Bold"
        default: "Baloo2-SemiBold"
        }
        return .custom(name, size: size)
    }

    /// Chữ thân bài: Be Vietnam Pro (đủ dấu tiếng Việt).
    static func vn(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = switch weight {
        case .heavy, .black: "BeVietnamPro-ExtraBold"
        case .bold: "BeVietnamPro-Bold"
        case .semibold: "BeVietnamPro-SemiBold"
        case .medium: "BeVietnamPro-Medium"
        default: "BeVietnamPro-Regular"
        }
        return .custom(name, size: size)
    }
}

/// Nút "nổi" có bóng đáy, nhấn thì lún xuống.
struct ChunkyButtonStyle: ButtonStyle {
    var fill: Color = Theme.orange
    var shadow: Color = Theme.orangeDeep
    var foreground: Color = .white
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.game(19))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill, in: .rect(cornerRadius: 18))
            .background(shadow, in: .rect(cornerRadius: 18).offset(y: configuration.isPressed ? 2 : 6))
            .offset(y: configuration.isPressed ? 4 : 0)
            .padding(.bottom, 6)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// Nút viền mực, nền trắng.
struct OutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.game(18))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(.white, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.ink, lineWidth: 3))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .padding(.bottom, 6)
    }
}

struct GameCard: ViewModifier {
    var padding: CGFloat = 14
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.white, in: .rect(cornerRadius: radius))
            .shadow(color: Theme.ink.opacity(0.07), radius: 6, y: 3)
    }
}

extension View {
    func gameCard(padding: CGFloat = 14, radius: CGFloat = 20) -> some View {
        modifier(GameCard(padding: padding, radius: radius))
    }
}

struct Chip: View {
    let text: String
    var symbol: String?
    var foreground: Color = Theme.ink
    var background: Color = Theme.line

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
            Text(text).font(.vn(12, .bold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(background, in: Capsule())
    }
}

struct RarityChip: View {
    let rarity: Rarity

    var body: some View {
        HStack(spacing: 3) {
            Text(rarity.title)
            ForEach(0..<rarity.stars, id: \.self) { _ in Image(systemName: "star.fill").font(.system(size: 8)) }
        }
        .font(.game(13))
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.rarity(rarity), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Độ hiếm \(rarity.title.lowercased())")
    }
}

/// Thanh tiến độ bo tròn.
struct ProgressBar: View {
    let value: Double
    var tint: Color = Theme.orange
    var track: Color = Theme.line
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint).frame(width: max(proxy.size.width * min(max(value, 0), 1), value > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) phần trăm")
    }
}

/// Đồng xu trong game.
struct CoinBadge: View {
    let amount: Int

    var body: some View {
        HStack(spacing: 4) {
            CoinGlyph().frame(width: 18, height: 18)
            Text(GameRules.number(amount)).monospacedDigit()
        }
        .font(.game(14))
        .foregroundStyle(Theme.goldText)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.goldSoft, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(amount) xu")
    }
}

/// Nút tròn 44pt có nền trắng (đóng, quay lại…).
struct CircleIconButton: View {
    let symbol: String
    let label: String
    var dark = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(dark ? .white : Theme.ink)
                .frame(width: 44, height: 44)
                .background(dark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.white), in: Circle())
                .shadow(color: Theme.ink.opacity(dark ? 0 : 0.1), radius: 5, y: 2)
        }
        .accessibilityLabel(label)
    }
}

/// Vẽ hình vòng chạy từ các cặp byte (x, y) trên lưới 256×256 (đúng dữ liệu lưu trong RunNFT).
struct RouteShapeView: View {
    let shape: Data
    var color: Color = Theme.orange
    var lineWidth: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            let bytes = [UInt8](shape)
            guard bytes.count >= 4 else { return }
            let scale = min(size.width, size.height) / 256
            var path = Path()
            for index in stride(from: 0, to: bytes.count - 1, by: 2) {
                let point = CGPoint(x: CGFloat(bytes[index]) * scale, y: CGFloat(bytes[index + 1]) * scale)
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            let start = CGPoint(x: CGFloat(bytes[0]) * scale, y: CGFloat(bytes[1]) * scale)
            context.fill(Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)), with: .color(.white))
            context.stroke(Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)),
                           with: .color(color), lineWidth: 3)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Hình vòng chạy")
    }
}

/// Chia sẻ văn bản + ảnh qua bảng chia sẻ của iOS (Zalo, Messenger, Mail…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
