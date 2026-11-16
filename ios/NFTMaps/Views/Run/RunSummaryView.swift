import SwiftUI

private let muted = Color(hex: 0x6E6A8E)

/// Tổng kết sau khi chạy (artboard "Xong vòng!"): hình vòng trên bản đồ minh hoạ, số liệu, thử thách, thưởng, mint.
struct RunSummaryView: View {
    let account: SmartAccount
    let onDone: () -> Void

    @Environment(GameStore.self) private var game
    @State private var record: RunRecord
    @State private var isMinting = false

    init(record: RunRecord, account: SmartAccount, onDone: @escaping () -> Void) {
        _record = State(initialValue: record)
        self.account = account
        self.onDone = onDone
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .lastTextBaseline) {
                    Text("Xong vòng!").font(.game(36))
                    Spacer()
                    Text(Self.dateText(record.date))
                        .font(.vn(13, .semibold)).foregroundStyle(muted)
                }
                .padding(.horizontal, 4)

                routeCard
                distanceCard

                HStack(spacing: 10) {
                    statTile(GameRules.durationText(record.duration), "phút")
                    statTile(GameRules.paceText(secondsPerKm: record.secondsPerKm), "/km")
                    statTile("\(GameRules.kcal(meters: record.meters))", "kcal")
                }

                HStack(spacing: 8) {
                    challengeChip(RunChallenge.Kind.sprint.shortTitle, done: record.completedChallenges.contains(.sprint))
                    challengeChip(RunChallenge.Kind.hold.shortTitle, done: record.completedChallenges.contains(.hold))
                    challengeChip(DailyQuest.steps.title, done: game.isQuestDone(.steps))
                }

                petsCard

                HStack(spacing: 8) {
                    Text("+\(GameRules.number(record.xp)) XP")
                        .font(.game(16)).foregroundStyle(Theme.purpleText)
                        .padding(.horizontal, 14).padding(.vertical, 4)
                        .background(Theme.purpleSoft, in: Capsule())
                    if record.meters >= GameRules.streakMinimumMeters, game.streak > 0 {
                        HStack(spacing: 4) {
                            FlameGlyph().frame(width: 16, height: 18)
                            Text("\(game.streak)")
                        }
                        .font(.game(16)).foregroundStyle(Theme.orangeText)
                        .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 14))
                        .background(Theme.orangeSoft, in: Capsule())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Chuỗi \(game.streak) ngày")
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                mintSection
                Button("Xong", action: onDone)
                    .buttonStyle(ChunkyButtonStyle(height: 58))
                    .font(.game(21))
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .background(Theme.paper)
        }
        .fullScreenCover(isPresented: $isMinting) {
            RunMintSheet(record: record, account: account) { tokenID in record.mintedTokenID = tokenID }
        }
    }

    /// "11/11 · 06:00" như design.
    private static func dateText(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.day, .month, .hour, .minute], from: date)
        return String(format: "%d/%d · %02d:%02d", parts.day ?? 0, parts.month ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }

    // MARK: Thẻ

    private var routeCard: some View {
        ZStack {
            IllustratedBlock()
            if let shape = record.shape {
                RunTrace(shape: shape).padding(EdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24))
            } else {
                Text("Chạy từ \(Int(LocationPrivacy.minimumRunMetersToMint)) m để lưu hình vòng")
                    .font(.vn(12, .bold))
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.92), in: Capsule())
            }
        }
        .frame(height: 150)
        .clipShape(.rect(cornerRadius: 24))
        .shadow(color: Theme.ink.opacity(0.08), radius: 7, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.shape == nil ? "Vòng quá ngắn để lưu hình" : "Hình vòng chạy")
    }

    private var distanceCard: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(GameRules.number(Int(record.meters))).font(.game(48)).monospacedDigit()
                Text("m").font(.game(20, .bold)).foregroundStyle(Theme.onDark)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFFB27A))
                VStack(alignment: .leading, spacing: 2) {
                    Text(GameRules.number(record.steps)).font(.game(24)).monospacedDigit()
                    Text("bước").font(.vn(11)).foregroundStyle(Theme.onDark)
                }
            }
            .padding(EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 12))
            .background(.white.opacity(0.10), in: .rect(cornerRadius: 16))
        }
        .foregroundStyle(.white)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(Theme.ink, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.game(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.vn(12)).foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(.white, in: .rect(cornerRadius: 18))
        .shadow(color: Theme.ink.opacity(0.06), radius: 6, y: 3)
        .accessibilityElement(children: .combine)
    }

    private func challengeChip(_ title: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 20, height: 20)
                    .background(Color(hex: 0xF5B82E), in: Circle())
            } else {
                Circle().strokeBorder(Color(hex: 0xC9C4DE), lineWidth: 3).frame(width: 18, height: 18)
            }
            Text(title).font(.vn(12, .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(done ? Theme.ink : Theme.ink2)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(done ? Theme.goldSoft : .white, in: .rect(cornerRadius: 14))
        .overlay {
            if !done {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(hex: 0xC9C4DE), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(done ? "hoàn thành" : "chưa xong")")
    }

    private var petsCard: some View {
        HStack(spacing: 10) {
            PawGlyph()
                .fill(Theme.orange)
                .frame(width: 28, height: 28)
                .frame(width: 56, height: 56)
                .background(Theme.orangeSoft, in: .rect(cornerRadius: 14))
                .overlay(alignment: .bottom) {
                    UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                        .fill(Theme.orange).frame(height: 4)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(record.petsMet == 0 ? "Chưa gặp bé nào" : "\(record.petsMet) bé").font(.game(17))
                Text(record.petsMet == 0 ? "Lần sau thử ghé điểm cho ăn nhé" : "gặp trên đường")
                    .font(.vn(11, .bold)).foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: 0)
            if record.petsMet > 1 {
                Text(String(format: "Combo x%.2g", GameRules.comboMultiplier(petsMet: record.petsMet)))
                    .font(.game(14)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Theme.ink, in: Capsule())
            }
        }
        .padding(10)
        .background(.white, in: .rect(cornerRadius: 18))
        .shadow(color: Theme.ink.opacity(0.06), radius: 6, y: 3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mintSection: some View {
        if let tokenID = record.mintedTokenID {
            Label("Đã mint vòng chạy #\(tokenID)", systemImage: "checkmark.seal.fill")
                .font(.vn(15, .bold)).foregroundStyle(Theme.tealText)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else if record.canMint, !Config.runNFTAddress.isEmpty {
            Button { isMinting = true } label: {
                HStack(spacing: 8) {
                    SparkleShape().fill(Theme.ink).frame(width: 18, height: 18)
                    Text("Mint vòng chạy")
                }
            }
            .buttonStyle(OutlineButtonStyle(height: 56))
            .font(.game(19))
            .accessibilityLabel("Mint vòng chạy")
        } else if record.meters < LocationPrivacy.minimumRunMetersToMint {
            Text("Chạy từ \(Int(LocationPrivacy.minimumRunMetersToMint)) m để mint vòng chạy.")
                .font(.vn(13)).foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
    }
}

private extension RunChallenge.Kind {
    var shortTitle: String {
        switch self {
        case .sprint: "Bứt tốc"
        case .hold: "Giữ nhịp"
        }
    }
}

// MARK: - Mint vòng chạy

/// Mint vòng chạy thành NFT (artboard "Mint thẻ" bản vòng chạy). Lên chuỗi chỉ có hình vòng (đã bỏ 200 m đầu/cuối)
/// và khu vực ~1 km.
struct RunMintSheet: View {
    let record: RunRecord
    let account: SmartAccount
    let onMinted: (UInt64) -> Void

    @Environment(GameStore.self) private var game
    @Environment(MapViewModel.self) private var chain
    @Environment(\.dismiss) private var dismiss
    @State private var model = MintModel()
    @State private var name = ""
    @State private var tokenID: UInt64?
    @FocusState private var editingName: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
            Spacer(minLength: 12)
            if !editingName {
                card
                    .opacity(isFailed ? 0.45 : 1)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            Spacer(minLength: 12)
            panel
        }
        .background(Theme.ink.ignoresSafeArea())
        .foregroundStyle(.white)
        .animation(.snappy, value: editingName)
        .animation(.snappy, value: model.stage)
        .onAppear {
            if name.isEmpty {
                let parts = Calendar.current.dateComponents([.day, .month, .hour, .minute], from: record.date)
                name = String(format: "Vòng %d/%d %02d:%02d", parts.day ?? 0, parts.month ?? 0, parts.hour ?? 0, parts.minute ?? 0)
            }
        }
        .preferredColorScheme(.light)
    }

    private var isFailed: Bool {
        if case .failed = model.stage { true } else { false }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.stage.isBusy)
            .accessibilityLabel("Đóng")
            Spacer()
            Text("Mint thẻ").font(.game(20))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(Color(hex: 0x5EEAD4)).frame(width: 8, height: 8)
                Text("Fuji").font(.vn(12, .bold))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(.white.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Mạng Avalanche Fuji")
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                IllustratedBlock(compact: true)
                if let shape = record.shape {
                    RunTrace(shape: shape).padding(14)
                }
            }
            .frame(height: 196)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
            VStack(alignment: .leading, spacing: 3) {
                Text(trimmedName.isEmpty ? "Vòng chạy" : trimmedName)
                    .font(.game(22)).lineLimit(1).minimumScaleFactor(0.7)
                Text("VÒNG CHẠY · \(GameRules.metersText(record.meters).uppercased())")
                    .font(.vn(11, .heavy)).tracking(1)
            }
            .foregroundStyle(Theme.ink)
            .padding(EdgeInsets(top: 9, leading: 10, bottom: 11, trailing: 10))
        }
        .frame(width: 198)
        .padding(6)
        .background(Theme.orange, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 16)
        .accessibilityElement(children: .combine)
    }

    // MARK: Bảng dưới

    private var panel: some View {
        VStack(spacing: 0) {
            switch model.stage {
            case .idle:
                confirm
            case .preparing, .sponsoring, .sending, .confirming:
                progress
            case .done(let hash):
                success(hash)
            case .failed(let message):
                failure(message)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                .fill(.white)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var confirm: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Tên").font(.vn(13)).foregroundStyle(Theme.ink2)
                TextField("Tên vòng chạy", text: $name)
                    .font(.vn(15, .bold))
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
                    .focused($editingName)
                Image(systemName: "pencil").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.orangeText)
                    .accessibilityHidden(true)
            }
            .frame(height: 46)
            .overlay(alignment: .bottom) { divider }
            row("Mạng", "Avalanche Fuji")
            row("Ví", account.address.short)
            row("Ảnh", "Vết chạy")
            row("Vị trí", "Chỉ hình vòng · khu ~1 km")
            row("Phí", "Miễn phí", color: Theme.tealText, last: true)
            Button { Task { await mint() } } label: {
                HStack(spacing: 10) {
                    SparkleShape().fill(.white).frame(width: 20, height: 20)
                    Text("Mint").font(.game(22))
                }
            }
            .buttonStyle(ChunkyButtonStyle(height: 60))
            .disabled(trimmedName.isEmpty || trimmedName.utf8.count > 64)
            .accessibilityLabel("Mint")
            .padding(.top, 12)
        }
    }

    private var divider: some View { Rectangle().fill(Color(hex: 0xF0ECF8)).frame(height: 1) }

    private func row(_ label: String, _ value: String, color: Color = Theme.ink, last: Bool = false) -> some View {
        HStack {
            Text(label).font(.vn(13)).foregroundStyle(Theme.ink2)
            Spacer()
            Text(value).font(.vn(15, .bold)).foregroundStyle(color)
        }
        .frame(height: 46)
        .overlay(alignment: .bottom) { if !last { divider } }
        .accessibilityElement(children: .combine)
    }

    private var progress: some View {
        let labels = ["Lưu vết chạy", "Ký giao dịch", "Xác nhận trên chuỗi"]
        // preparing → 0, sponsoring/sending → 1, confirming → 2
        let active = switch model.stage.step {
        case ...0: 0
        case 1, 2: 1
        default: 2
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Đang mint…").font(.game(26)).padding(.top, 10)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    HStack(spacing: 12) {
                        if index < active {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Theme.teal, in: Circle())
                        } else if index == active {
                            ProgressView().tint(Theme.orange).frame(width: 28, height: 28)
                        } else {
                            Circle().strokeBorder(Color(hex: 0xD9D3EA), lineWidth: 3).frame(width: 28, height: 28)
                        }
                        Text(label).font(.vn(15, .bold)).foregroundStyle(index > active ? muted : Theme.ink)
                    }
                    .frame(height: 48)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(index < active ? "Xong" : index == active ? "Đang làm" : "Chờ")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
    }

    private func success(_ hash: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Đã mint!").font(.game(32))
                Spacer()
                if let tokenID {
                    Text("NFT #\(tokenID)")
                        .font(.game(15)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Theme.ink, in: Capsule())
                }
            }
            .padding(.top, 10)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Giao dịch").font(.vn(11)).foregroundStyle(Theme.ink2)
                    Text("\(hash.prefix(6))…\(hash.suffix(4))").font(.vn(14, .bold))
                }
                Spacer()
                Link(destination: Config.explorerURL.appending(path: "tx/\(hash)")) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .background(.white, in: .rect(cornerRadius: 12))
                }
                .accessibilityLabel("Xem giao dịch")
            }
            .padding(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 6))
            .frame(height: 56)
            .background(Theme.paper, in: .rect(cornerRadius: 16))
            HStack(spacing: 10) {
                ShareLink(item: Config.explorerURL.appending(path: "tx/\(hash)")) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .bold))
                        Text("Chia sẻ")
                    }
                }
                .buttonStyle(OutlineButtonStyle())
                .accessibilityLabel("Chia sẻ")
                Button("Xong") { dismiss() }
                    .buttonStyle(ChunkyButtonStyle())
            }
        }
        .padding(.bottom, 8)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.orangeText)
                .frame(width: 60, height: 60)
                .background(Theme.orangeSoft, in: Circle())
                .padding(.top, 10)
            Text("Chưa mint được").font(.game(26))
            Text(message)
                .font(.vn(13, .bold)).foregroundStyle(Theme.orangeText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Theme.orangeSoft, in: .rect(cornerRadius: 14))
            HStack(spacing: 10) {
                Button("Để sau") { dismiss() }.buttonStyle(OutlineButtonStyle())
                Button("Thử lại") { Task { await mint() } }.buttonStyle(ChunkyButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func mint() async {
        editingName = false
        guard let data = RunNFTCall.mintRun(record, name: trimmedName),
              let target = try? Config.address(Config.runNFTAddress, name: "runNFT") else { return }
        guard await model.send(target: target, data: data, account: account) else { return }
        await chain.refresh()
        if let minted = chain.runs(ownedBy: account.address).last?.id {
            tokenID = minted
            game.markRunMinted(record.id, tokenID: minted)
            onMinted(minted)
        }
    }
}

// MARK: - Hình vẽ dùng chung trong file

/// Ngôi sao 4 cánh (biểu tượng mint trong design).
private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(12, 2))
        path.addQuadCurve(to: p(20, 10), control: p(13.2, 8.8))
        path.addQuadCurve(to: p(12, 18), control: p(13.2, 11.2))
        path.addQuadCurve(to: p(4, 10), control: p(10.8, 11.2))
        path.addQuadCurve(to: p(12, 2), control: p(10.8, 8.8))
        path.closeSubpath()
        return path
    }
}

/// Một khu phố minh hoạ (cỏ, công viên có hồ, lô nhà, đường kem viền vàng) làm nền cho hình vòng chạy.
private struct IllustratedBlock: View {
    var compact = false

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func fill(_ rect: CGRect, _ radius: CGFloat, _ hex: UInt32) {
                context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(Color(hex: hex)))
            }
            fill(CGRect(origin: .zero, size: size), 0, 0xC3EA96)
            // công viên + hồ + cây
            let park = CGRect(x: w * 0.42, y: h * 0.25, width: w * 0.35, height: h * 0.44)
            fill(park, 14, 0x8FD068)
            context.fill(Path(ellipseIn: CGRect(x: park.midX + park.width * 0.05, y: park.maxY - h * 0.17,
                                                width: park.width * 0.3, height: h * 0.12)),
                         with: .color(Color(hex: 0x5FCAD9)))
            for (x, y) in [(0.12, 0.2), (0.85, 0.18), (0.15, 0.72)] {
                context.fill(Path(ellipseIn: CGRect(x: park.minX + park.width * x - 6, y: park.minY + park.height * y - 6,
                                                    width: 12, height: 12)),
                             with: .color(Color(hex: 0x4FB043)))
            }
            // lô nhà
            for rect in [CGRect(x: w * 0.05, y: h * 0.27, width: w * 0.25, height: h * 0.19),
                         CGRect(x: w * 0.05, y: h * 0.5, width: w * 0.2, height: h * 0.19),
                         CGRect(x: w * 0.87, y: h * 0.27, width: w * 0.12, height: h * 0.42)] {
                fill(rect, 6, 0xFBF6EA)
            }
            // đường: viền vàng rồi lòng kem
            let roads: [(CGPoint, CGPoint, CGFloat)] = [
                (CGPoint(x: 0, y: h * 0.16), CGPoint(x: w, y: h * 0.16), compact ? 12 : 12),
                (CGPoint(x: 0, y: h * 0.77), CGPoint(x: w, y: h * 0.77), 14),
                (CGPoint(x: w * 0.36, y: 0), CGPoint(x: w * 0.36, y: h), 14),
                (CGPoint(x: w * 0.81, y: 0), CGPoint(x: w * 0.81, y: h), 12),
            ]
            for (extra, hex) in [(4.0, UInt32(0xE3CF9C)), (0, UInt32(0xFFF6DD))] {
                for (a, b, width) in roads {
                    var path = Path()
                    path.move(to: a)
                    path.addLine(to: b)
                    context.stroke(path, with: .color(Color(hex: hex)), lineWidth: width + extra)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Hình vòng chạy (cặp byte trên lưới 256×256) co vừa khung, có quầng cam, chấm xuất phát và về đích.
private struct RunTrace: View {
    let shape: Data

    var body: some View {
        Canvas { context, size in
            let bytes = [UInt8](shape)
            guard bytes.count >= 4 else { return }
            let raw = stride(from: 0, to: bytes.count - 1, by: 2).map { CGPoint(x: CGFloat(bytes[$0]), y: CGFloat(bytes[$0 + 1])) }
            let minX = raw.map(\.x).min()!, maxX = raw.map(\.x).max()!
            let minY = raw.map(\.y).min()!, maxY = raw.map(\.y).max()!
            let scale = min(size.width / max(maxX - minX, 1), size.height / max(maxY - minY, 1))
            let dx = (size.width - (maxX - minX) * scale) / 2, dy = (size.height - (maxY - minY) * scale) / 2
            let points = raw.map { CGPoint(x: dx + ($0.x - minX) * scale, y: dy + ($0.y - minY) * scale) }
            var path = Path()
            path.addLines(points)
            let orange = Color(hex: 0xF2690D)
            context.stroke(path, with: .color(Color(hex: 0xFF7A1A).opacity(0.25)),
                           style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(orange), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            func dot(_ point: CGPoint, _ color: Color, _ radius: CGFloat) {
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))
                context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 3)
            }
            if let last = points.last { dot(last, orange, 7) }
            if let first = points.first { dot(first, Theme.ink, 6) }
        }
        .accessibilityHidden(true)
    }
}
