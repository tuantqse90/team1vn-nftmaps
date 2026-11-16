import SwiftUI
import UIKit

/// Bóng ném PawRun: quả cầu cam viền trắng có dấu chân (như nút chụp của design).
struct PawOrb: View {
    var size: CGFloat = 78
    var glowing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: 0xFFA25C), Theme.orange, Color(hex: 0xC2410C)],
                    center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.8
                ))
            Circle()
                .strokeBorder(.white, lineWidth: size * 0.075)
            PawGlyph()
                .fill(.white)
                .frame(width: size * 0.42, height: size * 0.42)
                .shadow(color: Color(hex: 0x8A2C07).opacity(0.35), radius: 1.5, y: 1)
            Ellipse()
                .fill(.white.opacity(0.55))
                .frame(width: size * 0.3, height: size * 0.13)
                .rotationEffect(.degrees(-30))
                .offset(x: -size * 0.19, y: -size * 0.26)
                .blur(radius: 1.5)
        }
        .frame(width: size, height: size)
        .shadow(color: glowing ? .white : Theme.orange.opacity(0.6), radius: glowing ? 28 : 12)
    }
}

/// Khung ngắm 4 góc quanh con vật model đang thấy + nhãn loài, độ chắc chắn và độ hiếm (artboard Capture).
struct TargetReticle: View {
    let target: CatchTarget
    var rarity: Rarity?

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let breathe = 1 + 0.035 * sin(time * 3.2)
            let side = target.radius * 2
            ZStack {
                CornerBrackets()
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .frame(width: side, height: side)
                    .scaleEffect(breathe)
                speciesTag
                    .offset(y: -target.radius - 26 + 3 * sin(time * 2.4))
            }
            .frame(width: side, height: side)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(target.species.displayName) \(target.confidence)%" + (rarity.map { ", \($0.title.lowercased())" } ?? ""))
        .accessibilityIdentifier("catchTarget")
    }

    private var speciesTag: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(target.species.displayName).font(.vn(13, .bold)).foregroundStyle(Theme.ink)
                Text("\(target.confidence)%").font(.vn(13, .semibold)).foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white, in: Capsule())
            if let rarity {
                Text(rarity.title.uppercased())
                    .font(.vn(11, .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.rarity(rarity), in: Capsule())
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .fixedSize()
    }
}

/// 4 góc khung ngắm (mỗi cạnh dài ~22% khung, bo góc).
private struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.22
        let r: CGFloat = 8
        var path = Path()
        // trên-trái
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        // trên-phải
        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
        // dưới-phải
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        // dưới-trái
        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        return path
    }
}

/// Đường bay vòng cung của bóng (Bézier bậc 2). SwiftUI nội suy `progress` 0 → 1.
struct ArcEffect: GeometryEffect {
    var progress: CGFloat
    let flight: Flight?

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard let flight else { return ProjectionTransform() }
        let point = flight.point(at: progress)
        return ProjectionTransform(CGAffineTransform(translationX: point.x - flight.rest.x,
                                                     y: point.y - flight.rest.y))
    }
}

struct Flight: Equatable {
    /// Chỗ bóng nằm chờ — gốc của phép dịch.
    let rest: CGPoint
    let start: CGPoint
    let end: CGPoint
    /// Độ vồng của đường bay so với điểm cao hơn trong hai đầu.
    let apex: CGFloat

    func point(at t: CGFloat) -> CGPoint {
        let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - apex)
        let u = 1 - t
        return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                       y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
    }
}

/// Chớp sáng lúc bóng trúng.
struct CatchFlash: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: 90))
            .frame(width: 180, height: 180)
            .scaleEffect(expanded ? 2.6 : 0.3)
            .opacity(expanded ? 0 : 1)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { expanded = true }
            }
    }
}

/// Pháo hoa dấu chân + lấp lánh khi bắt được.
struct CatchBurst: View {
    @State private var expanded = false
    @State private var faded = false

    private static let symbols = ["pawprint.fill", "sparkle", "star.fill", "heart.fill"]
    private static let colors: [Color] = [Theme.gold, Theme.orange, .white, Color(hex: 0xFF8FB1)]

    var body: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { index in
                let angle = Double(index) / 18 * 2 * .pi
                let distance: CGFloat = index.isMultiple(of: 2) ? 160 : 110
                Image(systemName: Self.symbols[index % 4])
                    .font(.system(size: index.isMultiple(of: 2) ? 28 : 18, weight: .bold))
                    .foregroundStyle(Self.colors[index % 4])
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .offset(x: expanded ? cos(angle) * distance : 0, y: expanded ? sin(angle) * distance : 0)
                    .scaleEffect(expanded ? 1 : 0.1)
                    .rotationEffect(.degrees(expanded ? Double(index * 25) : 0))
            }
        }
        .opacity(faded ? 0 : 1)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.35)) { expanded = true }
            withAnimation(.easeIn(duration: 0.5).delay(0.9)) { faded = true }
        }
    }
}

struct CatchBanner: Equatable {
    let text: String
    let color: Color
    let id = UUID()
}

struct CatchBannerView: View {
    let banner: CatchBanner

    var body: some View {
        Text(banner.text)
            .font(.game(30))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.top, 9)
            .padding(.bottom, 5)
            .background(banner.color, in: Capsule())
            .overlay(Capsule().strokeBorder(.white, lineWidth: 4))
            .background(Theme.ink.opacity(0.35), in: Capsule().offset(y: 5))
            .rotationEffect(.degrees(-4))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            .fixedSize()
            .allowsHitTesting(false)
    }
}

/// Thẻ "Bắt được rồi!" — ảnh đúng như sẽ lưu on-chain.
struct CaughtCard: View {
    let pet: CaughtPet
    let onMint: () -> Void
    let onRelease: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            Text("BẮT ĐƯỢC RỒI!")
                .font(.vn(12, .heavy)).tracking(1.2)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Theme.gold, in: Capsule())

            if let image = UIImage(data: pet.thumbnail) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 230, height: 230)
                    .clipShape(.rect(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.orange, lineWidth: 5))
                    .accessibilityLabel("Ảnh bé vừa bắt")
            }

            HStack(spacing: 6) {
                Image(systemName: pet.detection.species.symbolName).foregroundStyle(Theme.orange)
                Text(pet.detection.species.displayName).font(.game(20))
                Text("\(pet.detection.confidencePercent)% chắc chắn").font(.vn(13, .semibold)).foregroundStyle(Theme.ink2)
            }

            Button(action: onMint) {
                Label("Đặt tên & mint NFT", systemImage: "sparkles").font(.game(19))
            }
            .buttonStyle(ChunkyButtonStyle())
            .accessibilityIdentifier("mintCaught")

            Button(action: onRelease) {
                Text("Thả bé đi").font(.vn(15, .bold)).underline().foregroundStyle(Theme.ink2)
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("releaseCaught")
        }
        .foregroundStyle(Theme.ink)
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 10, trailing: 20))
        .frame(maxWidth: 330)
        .background(.white, in: .rect(cornerRadius: 30))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .rotation3DEffect(.degrees(appeared ? 0 : 75), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(appeared ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.45)) { appeared = true }
        }
    }
}

@MainActor
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
