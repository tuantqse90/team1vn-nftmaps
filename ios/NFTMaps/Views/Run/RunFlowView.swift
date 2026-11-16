import MapKit
import SwiftUI

/// Chuẩn bị → đang chạy → tổng kết, trong một màn toàn màn hình.
struct RunFlowView: View {
    let account: SmartAccount

    private enum Step {
        case setup
        case running(RunTracker, RoutePlan?)
        case summary(RunRecord)
    }

    @Environment(GameStore.self) private var game
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .setup

    var body: some View {
        switch step {
        case .setup:
            RunSetupView(onClose: { dismiss() }) { tracker, route in
                tracker.start()
                step = .running(tracker, route)
            }
        case .running(let tracker, let route):
            RunView(tracker: tracker, suggestedRoute: route, account: account) {
                let record = tracker.finish()
                game.recordRun(record)
                step = .summary(record)
            } onCancel: {
                tracker.cancel()
                dismiss()
            }
        case .summary(let record):
            RunSummaryView(record: record, account: account) { dismiss() }
        }
    }
}

// MARK: - Chuẩn bị chạy

/// Artboard "Chuẩn bị chạy": thẻ mục tiêu xanh mực, 3 vòng gợi ý vẽ trên bản đồ minh hoạ, thử thách mang theo, vé x2.
struct RunSetupView: View {
    let onClose: () -> Void
    let onStart: (RunTracker, RoutePlan?) -> Void

    private enum Mode: String, CaseIterable {
        case meters = "Mét"
        case steps = "Bước"
    }

    @Environment(GameStore.self) private var game
    @Environment(MapViewModel.self) private var chain
    @AppStorage("voiceMilestones") private var voiceMilestones = true
    @State private var mode: Mode = .meters
    @State private var meters = 3_000
    @State private var steps = 5_000
    @State private var sprint = true
    @State private var hold = true
    @State private var useTicket = false
    @State private var loops: [RoutePlan] = []
    @State private var loopNames: [String] = []
    @State private var loadingLoops = false
    @State private var chosen: Int?

    private var targetMeters: Int { mode == .meters ? meters : Int(Double(steps) / 1.3) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    CircleIconButton(symbol: "chevron.left", label: "Quay lại", action: onClose)
                    Text("Chuẩn bị chạy").font(.game(28))
                }

                goalCard

                sectionTitle("Vòng gợi ý")
                loopTiles

                sectionTitle("Mang theo thử thách")
                HStack(spacing: 8) {
                    toggleChip("Bứt tốc", $sprint)
                    toggleChip("Giữ nhịp", $hold)
                    toggleChip("Đọc mốc", $voiceMilestones)
                }

                ticketRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .safeAreaInset(edge: .bottom) {
            Button { start() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill").font(.system(size: 20, weight: .bold))
                    Text("BẮT ĐẦU").font(.game(24)).tracking(0.5)
                }
            }
            .buttonStyle(ChunkyButtonStyle(height: 66))
            .accessibilityLabel("Bắt đầu")
            .accessibilityIdentifier("beginRun")
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .background(Theme.paper)
        }
        .task(id: targetMeters / 500) { await loadLoops() }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.game(17)).padding(.horizontal, 4).padding(.top, 2)
    }

    // MARK: Mục tiêu

    private var goalCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Mode.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.snappy) { mode = item }
                    } label: {
                        Text(item.rawValue)
                            .font(.game(16))
                            .foregroundStyle(mode == item ? Theme.ink : .white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(mode == item ? Color.white : .clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == item ? .isSelected : [])
                }
            }
            .padding(4)
            .background(.white.opacity(0.10), in: Capsule())

            HStack {
                Button {
                    if mode == .meters { meters = max(500, meters - 500) } else { steps = max(1_000, steps - 1_000) }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Giảm")
                Spacer()
                VStack(spacing: 2) {
                    Text(mode == .meters ? GameRules.number(meters) : GameRules.number(steps))
                        .font(.game(54))
                        .contentTransition(.numericText())
                        .monospacedDigit()
                        .frame(height: 52)
                    Text(mode == .meters ? "mét" : "bước").font(.vn(13)).foregroundStyle(Theme.onDark)
                }
                Spacer()
                Button {
                    if mode == .meters { meters = min(21_000, meters + 500) } else { steps = min(30_000, steps + 1_000) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Theme.orange, in: Circle())
                        .background(Theme.orangeDeep, in: Circle().offset(y: 4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tăng")
            }
            Text(estimate).font(.vn(13, .semibold)).foregroundStyle(Theme.onDark)
        }
        .foregroundStyle(.white)
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        .background(Theme.ink, in: .rect(cornerRadius: 24))
        .animation(.snappy, value: meters)
        .animation(.snappy, value: steps)
    }

    private var estimate: String {
        let minutes = max(1, Int((Double(targetMeters) * 6.2 / 1000).rounded()))
        return mode == .meters
            ? "~\(GameRules.number(GameRules.estimatedSteps(meters: Double(meters)))) bước · ~\(minutes) phút"
            : "~\(GameRules.number(targetMeters)) m · ~\(minutes) phút"
    }

    // MARK: Vòng gợi ý

    @ViewBuilder
    private var loopTiles: some View {
        if loadingLoops || !loops.isEmpty {
            HStack(spacing: 10) {
                if loadingLoops {
                    ForEach(0..<3, id: \.self) { _ in placeholderTile }
                } else {
                    ForEach(Array(loops.prefix(3).enumerated()), id: \.offset) { index, loop in loopTile(index, loop) }
                }
            }
        } else {
            Text("Chưa tìm được vòng quanh đây. Cứ chạy tự do nhé.")
                .font(.vn(14)).foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white, in: .rect(cornerRadius: 18))
        }
    }

    private var placeholderTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            MiniMapBackdrop().frame(height: 62).overlay { ProgressView().tint(Theme.orange) }
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Theme.line).frame(width: 54, height: 12)
                Capsule().fill(Theme.line).frame(width: 70, height: 9)
            }
            .padding(EdgeInsets(top: 8, leading: 8, bottom: 10, trailing: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: .rect(cornerRadius: 18))
        .clipShape(.rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line, lineWidth: 3))
        .accessibilityLabel("Đang tìm vòng gợi ý")
    }

    private func loopTile(_ index: Int, _ loop: RoutePlan) -> some View {
        let selected = chosen == index
        let pets = chain.visibleTokens.filter { token in
            loop.coordinates.contains { $0.distance(to: token.coordinate) < 80 }
        }.count
        let name = index < loopNames.count ? loopNames[index] : "Vòng \(index + 1)"
        return Button {
            withAnimation(.snappy) { chosen = selected ? nil : index }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    MiniMapBackdrop()
                    LoopShape(coordinates: loop.coordinates)
                        .stroke(Theme.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                }
                .frame(height: 62)
                .clipped()
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.game(15)).lineLimit(1).minimumScaleFactor(0.8)
                    Text("\(GameRules.number(Int(loop.meters.rounded()))) m · \(pets) bé")
                        .font(.vn(11, .semibold)).foregroundStyle(Theme.ink2).lineLimit(1)
                }
                .padding(EdgeInsets(top: 6, leading: 8, bottom: 8, trailing: 8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white)
            .clipShape(.rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? Theme.orange : Theme.line, lineWidth: 3))
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(GameRules.metersText(loop.meters)), \(pets) bé dọc đường")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Thử thách & vé

    private func toggleChip(_ title: String, _ isOn: Binding<Bool>) -> some View {
        let on = isOn.wrappedValue
        return Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 5) {
                if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .black)) }
                Text(title).font(.vn(13, .bold)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(on ? .white : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(on ? Theme.ink : .white, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Theme.ink : Theme.line, lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var ticketRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "ticket")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Theme.gold, in: .rect(cornerRadius: 12))
            Text("Vé x2 XP").font(.game(17))
            Spacer()
            Text("còn \(game.progress.x2Tickets)").font(.vn(12, .semibold)).foregroundStyle(Theme.ink2)
            Toggle("Vé x2 XP", isOn: $useTicket)
                .labelsHidden()
                .tint(Theme.orange)
                .disabled(game.progress.x2Tickets == 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .background(.white, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(useTicket ? Color(hex: 0xF5B82E) : Theme.line, lineWidth: 2))
        .opacity(game.progress.x2Tickets == 0 && !useTicket ? 0.6 : 1)
    }

    // MARK: Logic

    private func loadLoops() async {
        guard let here = await LocationOnce.current(timeout: .seconds(8)) else { return }
        loadingLoops = true
        defer { loadingLoops = false }
        var found: [RoutePlan] = []
        for bearing in [20.0, 140, 260] {
            // Bỏ vòng vô lý (định tuyến vòng qua sông/biển ra hàng chục km).
            if let loop = try? await RouteService.loop(from: here, targetMeters: Double(targetMeters), bearing: bearing),
               loop.meters <= Double(targetMeters) * 2.5 {
                found.append(loop)
            }
        }
        // Tên vòng: phường/khu ở điểm xa nhất của vòng; trùng nhau thì gọi theo hướng.
        var names: [String] = []
        for loop in found {
            let apex = loop.coordinates.max { $0.distance(to: here) < $1.distance(to: here) } ?? here
            let fallback = "Hướng " + compassName(here.bearing(to: apex))
            names.append(await RouteService.placeName(apex) ?? fallback)
        }
        if Set(names).count < names.count {
            names = found.map { loop in
                let apex = loop.coordinates.max { $0.distance(to: here) < $1.distance(to: here) } ?? here
                return "Hướng " + compassName(here.bearing(to: apex))
            }
        }
        loops = found
        loopNames = names
        chosen = nil
    }

    private func start() {
        let doubled = useTicket && game.useTicket()
        let goal: RunGoal = mode == .meters ? .meters(meters) : .steps(steps)
        let tracker = RunTracker(goal: goal, sprint: sprint, hold: hold, doubleXP: doubled)
        tracker.voiceEnabled = voiceMilestones
        onStart(tracker, chosen.map { loops[$0] })
    }
}

private func compassName(_ bearing: Double) -> String {
    let names = ["Bắc", "Đông Bắc", "Đông", "Đông Nam", "Nam", "Tây Nam", "Tây", "Tây Bắc"]
    let normalized = (bearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    return names[Int((normalized + 22.5) / 45) % 8]
}

private extension CLLocationCoordinate2D {
    /// Hướng (độ, 0 = bắc) từ điểm này tới điểm kia.
    func bearing(to other: CLLocationCoordinate2D) -> Double {
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }
}

/// Nền bản đồ minh hoạ nhỏ (cỏ + lô đất) theo bảng màu PawRun.
private struct MiniMapBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 96, sy = size.height / 62
            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
                Path(roundedRect: CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy), cornerRadius: 3.5)
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xC3EA96)))
            let block = GraphicsContext.Shading.color(Color(hex: 0xB6E289))
            context.fill(rect(30, 22, 38, 20), with: block)
            context.fill(rect(2, 2, 16, 10), with: block)
            context.fill(rect(80, 46, 14, 12), with: block)
        }
        .accessibilityHidden(true)
    }
}

/// Đường vòng chạy co vừa khung (giữ tỉ lệ, chiếu phẳng quanh vĩ độ của vòng).
private struct LoopShape: Shape {
    let coordinates: [CLLocationCoordinate2D]

    func path(in rect: CGRect) -> Path {
        guard coordinates.count > 1 else { return Path() }
        let lat0 = coordinates[0].latitude * .pi / 180
        let points = coordinates.map { CGPoint(x: $0.longitude * cos(lat0), y: -$0.latitude) }
        let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
        let scale = min(rect.width / max(maxX - minX, 1e-9), rect.height / max(maxY - minY, 1e-9))
        let offsetX = rect.minX + (rect.width - (maxX - minX) * scale) / 2
        let offsetY = rect.minY + (rect.height - (maxY - minY) * scale) / 2
        var path = Path()
        for (index, point) in points.enumerated() {
            let mapped = CGPoint(x: offsetX + (point.x - minX) * scale, y: offsetY + (point.y - minY) * scale)
            index == 0 ? path.move(to: mapped) : path.addLine(to: mapped)
        }
        return path
    }
}
