import SwiftUI

/// Màn chào (artboard Onboarding): cảnh trời chiều + nhân vật và hai bé, tấm trắng có logo PawRun,
/// đăng nhập bằng username + mật khẩu (ví tạo ngay trên máy, không popup).
struct LoginView: View {
    let session: WalletSession

    @State private var username = ""
    @State private var password = ""
    @State private var showHelp = false
    @FocusState private var focused: Field?

    private enum Field {
        case username
        case password
    }

    private var canSubmit: Bool {
        !session.isSigningIn && !KeyDerivation.normalizedUsername(username).isEmpty && password.count >= 8
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingScene()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .clipped()
                .ignoresSafeArea(edges: .top)
            sheet
                .padding(.top, -32)
        }
        .background(Color(hex: 0xC3EA96))
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showHelp) { help }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PawGlyph()
                    .fill(.white)
                    .frame(width: 30, height: 30)
                    .frame(width: 54, height: 54)
                    .background(Theme.orange, in: .rect(cornerRadius: 18))
                    .background(Theme.orangeDeep, in: .rect(cornerRadius: 18).offset(y: 4))
                    .accessibilityHidden(true)
                Text("PawRun").font(.game(42)).padding(.top, 6)
            }
            Text("Chạy bộ. Gặp bé. Sưu tầm.")
                .font(.vn(17, .semibold))
                .foregroundStyle(Theme.ink2)
                .padding(.bottom, 8)

            TextField("Username", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .username)
                .submitLabel(.next)
                .onSubmit { focused = .password }
                .modifier(LoginField(symbol: "person.fill", isFocused: focused == .username))
                .accessibilityIdentifier("username")

            SecureField("Mật khẩu (tối thiểu 8 ký tự)", text: $password)
                .textContentType(.password)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit(submit)
                .modifier(LoginField(symbol: "lock.fill", isFocused: focused == .password))
                .accessibilityIdentifier("password")

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.vn(13, .medium))
                    .foregroundStyle(Theme.orangeText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if session.isSigningIn {
                        ProgressView().tint(.white)
                        Text("Đang tạo ví…")
                    } else {
                        Text("Đăng nhập / Tạo ví")
                    }
                }
                .font(.vn(17, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(.black.opacity(canSubmit || session.isSigningIn ? 1 : 0.35), in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .padding(.top, 6)
            .accessibilityIdentifier("signIn")

            Button { showHelp = true } label: {
                Text("Ví hoạt động thế nào?")
                    .font(.vn(17, .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.white, in: .rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 30, leading: 24, bottom: 16, trailing: 24))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32)
                .fill(.white)
                .shadow(color: Theme.ink.opacity(0.12), radius: 15, y: -8)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ví PawRun").font(.game(28))
            helpRow("sparkles", Theme.orange, "Không cần ví ngoài, không popup ký, không cần AVAX — phí mint được tài trợ.")
            helpRow("key.fill", Theme.purple,
                    "Nhập đúng username + mật khẩu trên máy khác sẽ ra đúng ví cũ. Quên mật khẩu là mất ví.")
            helpRow("testtube.2", Theme.teal, "Đang chạy trên Avalanche Fuji testnet, chỉ dùng để thử.")
            Spacer(minLength: 0)
        }
        .padding(24)
        .foregroundStyle(Theme.ink)
        .presentationDetents([.medium])
        .presentationBackground(Theme.paper)
    }

    private func helpRow(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))
            Text(text).font(.vn(15)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        Task { await session.signIn(username: username, password: password) }
    }
}

private struct LoginField: ViewModifier {
    let symbol: String
    let isFocused: Bool

    func body(content: Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isFocused ? Theme.orange : Theme.ink2)
                .frame(width: 20)
            content.font(.vn(16, .medium))
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Theme.paper, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isFocused ? Theme.orange : Theme.line, lineWidth: 2))
    }
}

/// Cảnh chào của design (390×560): trời cam, mặt trời, mây, phố xa, đồi, đường mòn, nhân vật cổ vũ giữa mèo và chó.
private struct OnboardingScene: View {
    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / 390
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    context.scaleBy(x: s, y: s)
                    context.fill(Path(CGRect(x: 0, y: 0, width: 390, height: 400)),
                                 with: .linearGradient(Gradient(stops: [
                                    .init(color: Color(hex: 0xFFB98C), location: 0),
                                    .init(color: Color(hex: 0xFFDDBA), location: 0.6),
                                    .init(color: Color(hex: 0xFFF0DC), location: 1),
                                 ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 400)))
                    context.fill(Path(ellipseIn: CGRect(x: 236, y: 196, width: 108, height: 108)),
                                 with: .color(Color(hex: 0xFFF3D6).opacity(0.9)))
                    var clouds = Path()
                    for (cx, cy, rx, ry) in [(80.0, 150.0, 50.0, 14.0), (110, 140, 28, 14), (300, 110, 40, 11), (322, 102, 22, 11)] {
                        clouds.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
                    }
                    context.fill(clouds, with: .color(.white.opacity(0.9)))
                    var skyline = Path()
                    for (x, y, w, h) in [(12.0, 300.0, 26.0, 60.0), (42, 282, 20, 78), (66, 312, 34, 48), (190, 290, 18, 70),
                                         (212, 306, 30, 54), (320, 296, 22, 64), (346, 316, 36, 44)] {
                        skyline.addRect(CGRect(x: x, y: y, width: w, height: h))
                    }
                    context.fill(skyline, with: .color(Color(hex: 0xF3C3A6)))
                    var hill = Path()
                    hill.move(to: CGPoint(x: 0, y: 352))
                    hill.addCurve(to: CGPoint(x: 200, y: 336), control1: CGPoint(x: 70, y: 326), control2: CGPoint(x: 140, y: 344))
                    hill.addCurve(to: CGPoint(x: 390, y: 330), control1: CGPoint(x: 270, y: 326), control2: CGPoint(x: 330, y: 344))
                    hill.addLine(to: CGPoint(x: 390, y: 400))
                    hill.addLine(to: CGPoint(x: 0, y: 400))
                    hill.closeSubpath()
                    context.fill(hill, with: .color(Color(hex: 0xA9DC8A)))
                    context.fill(Path(CGRect(x: 0, y: 380, width: 390, height: 180)), with: .color(Color(hex: 0xC3EA96)))
                    var trail = Path()
                    trail.move(to: CGPoint(x: 118, y: 560))
                    trail.addCurve(to: CGPoint(x: 188, y: 382), control1: CGPoint(x: 160, y: 480), control2: CGPoint(x: 212, y: 430))
                    trail.addLine(to: CGPoint(x: 204, y: 382))
                    trail.addCurve(to: CGPoint(x: 274, y: 560), control1: CGPoint(x: 244, y: 430), control2: CGPoint(x: 226, y: 486))
                    trail.closeSubpath()
                    context.fill(trail, with: .color(Color(hex: 0xFFF6DD)))
                    var dash = Path()
                    dash.move(to: CGPoint(x: 196, y: 392))
                    dash.addLine(to: CGPoint(x: 197, y: 560))
                    context.stroke(dash, with: .color(Color(hex: 0xF0DCA4)), style: StrokeStyle(lineWidth: 3, dash: [12, 12]))
                    for (cx, cy, r, color) in [(40.0, 420.0, 18.0, 0x4FB043), (34, 414, 8, 0x7CD25A), (350, 410, 20, 0x4FB043),
                                               (343, 403, 9, 0x7CD25A), (96, 396, 12, 0x4FB043), (300, 392, 12, 0x4FB043)] {
                        context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                                     with: .color(Color(hex: UInt32(color))))
                    }
                    var shadows = Path()
                    for (cx, cy, rx, ry) in [(95.0, 490.0, 50.0, 10.0), (297, 490, 50, 10), (196, 492, 36, 8)] {
                        shadows.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
                    }
                    context.fill(shadows, with: .color(Color(hex: 0x4E9A38).opacity(0.35)))
                    for (x, y, k) in [(150.0, 200.0, 1.0), (30, 240, 0.7), (350, 200, 0.8)] {
                        context.fill(sparkle(x: x, y: y, scale: k), with: .color(Theme.gold))
                    }
                }
                Image("pet-cat")
                    .resizable().scaledToFit()
                    .frame(width: 114 * s, height: 114 * s)
                    .offset(x: 38 * s, y: 376 * s)
                Image("pet-dog")
                    .resizable().scaledToFit()
                    .frame(width: 114 * s, height: 114 * s)
                    .offset(x: 240 * s, y: 376 * s)
                PhaseAnimator([false, true]) { up in
                    Image("hero-cheer")
                        .resizable().scaledToFit()
                        .frame(width: 110 * s, height: 180 * s)
                        .offset(y: up ? -4 * s : 0)
                } animation: { _ in .easeInOut(duration: 1.1) }
                    .offset(x: 141 * s, y: 314 * s)
            }
            .frame(width: proxy.size.width, height: 560 * s)
            // Đáy cảnh luôn chạm đáy vùng chứa (bàn phím bật lên thì cắt bớt trời, nhân vật vẫn đứng trên tấm trắng).
            .position(x: proxy.size.width / 2, y: proxy.size.height - 280 * s)
        }
        .accessibilityHidden(true)
    }

    private func sparkle(x: Double, y: Double, scale k: Double) -> Path {
        var path = Path()
        func p(_ px: Double, _ py: Double) -> CGPoint { CGPoint(x: x + px * k, y: y + py * k) }
        path.move(to: p(12, 2))
        path.addQuadCurve(to: p(20, 10), control: p(13, 9))
        path.addQuadCurve(to: p(12, 18), control: p(13, 11))
        path.addQuadCurve(to: p(4, 10), control: p(11, 11))
        path.addQuadCurve(to: p(12, 2), control: p(11, 9))
        path.closeSubpath()
        return path
    }
}

/// Nền thương hiệu: trời chiều cam nhạt của PawRun (màn khởi động).
struct BrandBackground: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: Color(hex: 0xFFB98C), location: 0),
            .init(color: Color(hex: 0xFFDDBA), location: 0.6),
            .init(color: Color(hex: 0xFFF0DC), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
    }
}
