import SwiftUI

/// Bộ sưu tập (Collection.dc.html): tiêu đề + tìm kiếm, 3 ô thống kê, thẻ độ hiếm, hàng chip lọc,
/// lưới thẻ bé 3 cột (của mình hoặc của mọi người) hoặc lưới vòng chạy đã mint.
struct CollectionView: View {
    let account: SmartAccount
    let startRun: () -> Void

    private enum Scope: String, CaseIterable, Identifiable {
        case mine = "Của tôi"
        case everyone = "Mọi người"
        case runs = "Vòng chạy"

        var id: Self { self }
    }

    private enum Filter: String, CaseIterable, Identifiable {
        case cat = "Mèo"
        case dog = "Chó"
        case rare = "Hiếm+"

        var id: Self { self }
    }

    @Environment(MapViewModel.self) private var chain
    @State private var scope: Scope = .mine
    @State private var filter: Filter?
    @State private var isSearching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var mine: [MapToken] { chain.tokens(ownedBy: account.address) }
    private var myRuns: [RunToken] { chain.runs(ownedBy: account.address) }

    private var shown: [MapToken] {
        var list = Array((scope == .mine ? mine : chain.visibleTokens).reversed())
        switch filter {
        case .cat: list = list.filter { $0.species == .cat }
        case .dog: list = list.filter { $0.species == .dog }
        case .rare: list = list.filter { chain.rarity(of: $0) >= .rare }
        case nil: break
        }
        let text = query.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            list = list.filter { $0.name.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return list
    }

    /// Độ hiếm mình chưa gặp → thẻ "???" cuối lưới (như design).
    private var missingRarities: [Rarity] {
        guard scope == .mine, filter == nil, query.isEmpty, !mine.isEmpty else { return [] }
        let have = Set(mine.map { chain.rarity(of: $0) })
        return Rarity.allCases.filter { !have.contains($0) }
    }

    /// Số khu ~1 km khác nhau mình đã gặp bé.
    private var areas: Int { Set(mine.map { LocationPrivacy.area($0.coordinate) }).count }
    private var rarityTiers: Int { Set(mine.map { chain.rarity(of: $0) }).count }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                if isSearching { searchField }
                HStack(spacing: 10) {
                    StatTile(value: "\(mine.count)", label: "bé")
                    StatTile(value: "\(mine.count + myRuns.count)", label: "NFT")
                    StatTile(value: "\(areas)", label: "khu")
                }
                rarityCard
                chips
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24 + tabBarClearance)
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0).background(Theme.paper) }
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Sưu tập")
        .navigationDestination(for: MapToken.self) { token in
            TokenDetailView(token: token, account: account, showsBack: true).hidesTabBar()
        }
        .refreshable { await chain.refresh() }
    }

    private var header: some View {
        HStack {
            Text("Sưu tập")
                .font(.game(32))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                withAnimation(.snappy) {
                    isSearching.toggle()
                    if isSearching { searchFocused = true } else { query = "" }
                }
            } label: {
                Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
                    .shadow(color: Theme.ink.opacity(0.08), radius: 5, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSearching ? "Đóng tìm kiếm" : "Tìm kiếm")
        }
        .padding(.horizontal, 4)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink2)
            TextField("Tìm theo tên bé", text: $query)
                .font(.vn(15))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.white, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 2))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Thẻ mực: đã gặp bao nhiêu loại độ hiếm (thay cho "Quận 1 14/40" của design — app chưa có số bé theo quận).
    private var rarityCard: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Độ hiếm đã gặp").font(.game(19))
                Spacer()
                Text("\(rarityTiers)/\(Rarity.allCases.count)")
                    .font(.game(17))
                    .foregroundStyle(Color(hex: 0xFFB27A))
                    .monospacedDigit()
            }
            ProgressBar(value: Double(rarityTiers) / Double(Rarity.allCases.count), tint: Theme.orange,
                        track: .white.opacity(0.14), height: 10)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.ink, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Đã gặp \(rarityTiers) trên \(Rarity.allCases.count) loại độ hiếm")
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Scope.allCases) { option in
                    FilterChip(title: option.rawValue, selected: scope == option) {
                        withAnimation(.snappy) { scope = option }
                    }
                }
                if scope != .runs {
                    Capsule().fill(Theme.line).frame(width: 2, height: 22).accessibilityHidden(true)
                    ForEach(Filter.allCases) { option in
                        FilterChip(title: option.rawValue, selected: filter == option) {
                            withAnimation(.snappy) { filter = filter == option ? nil : option }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    @ViewBuilder
    private var content: some View {
        if scope == .runs {
            runsGrid
        } else if shown.isEmpty && missingRarities.isEmpty {
            if filter == nil && query.isEmpty {
                empty
            } else {
                Text("Không có bé nào khớp.")
                    .font(.vn(14))
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            }
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(shown) { token in
                    NavigationLink(value: token) { PetCell(token: token, model: chain) }
                        .buttonStyle(.plain)
                }
                ForEach(missingRarities, id: \.self) { MysteryCell(rarity: $0) }
            }
        }
    }

    /// CollectionEmpty: 3 thẻ "?" nghiêng, "Chưa có bé nào", nút chạy ngay.
    private var empty: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(Array(zip([Rarity.common, .rare, .epic], [-6.0, 0, 6])), id: \.0) { rarity, angle in
                    Text("?")
                        .font(.game(30))
                        .foregroundStyle(Color(hex: 0x7A75A0))
                        .frame(width: 64, height: 84)
                        .background(Color(hex: 0xEEEAF6))
                        .overlay(alignment: .bottom) { DashLine().stroke(Theme.rarity(rarity), style: dashStyle).frame(height: 4) }
                        .clipShape(.rect(cornerRadius: 14))
                        .rotationEffect(.degrees(angle))
                }
            }
            .accessibilityHidden(true)
            Text(scope == .mine ? "Chưa có bé nào" : "Chưa ai gặp bé nào").font(.game(24))
            Button(action: startRun) {
                Label("Chạy ngay", systemImage: "play.fill")
                    .font(.game(20))
            }
            .buttonStyle(ChunkyButtonStyle())
        }
        .padding(EdgeInsets(top: 24, leading: 20, bottom: 18, trailing: 20))
        .frame(maxWidth: .infinity)
        .background(.white, in: .rect(cornerRadius: 24))
        .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
    }

    @ViewBuilder
    private var runsGrid: some View {
        let runs = Array(myRuns.reversed())
        if runs.isEmpty {
            VStack(spacing: 10) {
                LoopGlyph().frame(width: 56, height: 56)
                Text("Chưa mint vòng chạy nào").font(.game(20))
                Text("Chạy từ 500 m rồi bấm Mint vòng chạy ở màn tổng kết.")
                    .font(.vn(13))
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(.white, in: .rect(cornerRadius: 24))
            .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(runs) { run in RunCell(run: run) }
            }
        }
    }
}

/// Thẻ vòng chạy đã mint: hình vòng (đọc từ chuỗi) trên nền cỏ, viền đáy cam, tên + số mét.
struct RunCell: View {
    let run: RunToken

    @Environment(MapViewModel.self) private var chain
    @State private var shape: Data?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color(hex: 0xC3EA96)
                if let shape {
                    RouteShapeView(shape: shape, lineWidth: 4).padding(14)
                } else if failed {
                    LoopGlyph().frame(width: 64, height: 64).opacity(0.7).accessibilityLabel("Chưa tải được hình vòng")
                } else {
                    ProgressView()
                }
            }
            .frame(height: 120)
            .overlay(alignment: .topLeading) { NFTTag().padding(6) }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.orange).frame(height: 4) }
            VStack(alignment: .leading, spacing: 0) {
                Text(run.name).font(.game(15)).lineLimit(1)
                Text("\(GameRules.metersText(Double(run.meters))) · \(GameRules.number(run.steps)) bước")
                    .font(.vn(10.5, .bold))
                    .foregroundStyle(Theme.orangeText)
                    .lineLimit(1)
            }
            .padding(EdgeInsets(top: 7, leading: 10, bottom: 9, trailing: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(.rect(cornerRadius: 18))
        .shadow(color: Theme.ink.opacity(0.08), radius: 5, y: 3)
        .foregroundStyle(Theme.ink)
        .task(id: run.id) {
            do { shape = try await chain.route(runID: run.id) } catch { failed = true }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Mảnh dùng trong file

/// Thanh tab tự vẽ của AppShell (cao ~62pt + nút CHẠY nhô ~28pt) không đẩy safe area vào trong NavigationStack,
/// nên nội dung tự chừa chỗ để phần cuối cuộn lên được trên thanh tab.
private let tabBarClearance: CGFloat = 92

private let dashStyle = StrokeStyle(lineWidth: 4, dash: [7, 5])

/// Đường ngang giữa khung (viền đáy nét đứt của thẻ chưa gặp).
private struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.game(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.vn(12)).foregroundStyle(Color(hex: 0x6E6A8E))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white, in: .rect(cornerRadius: 18))
        .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
        .accessibilityElement(children: .combine)
    }
}

private struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.vn(13, selected ? .bold : .semibold))
                .foregroundStyle(selected ? .white : Theme.ink)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(selected ? Theme.ink : .white, in: Capsule())
                .overlay { if !selected { Capsule().strokeBorder(Theme.line, lineWidth: 2) } }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NFTTag: View {
    var body: some View {
        Text("NFT")
            .font(.vn(9, .heavy))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.ink, in: .rect(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}

/// Thẻ bé chưa gặp ở độ hiếm này: "?" trên nền tím nhạt, viền đáy nét đứt.
private struct MysteryCell: View {
    let rarity: Rarity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("?")
                .font(.game(40))
                .foregroundStyle(Color(hex: 0x7A75A0))
                .frame(maxWidth: .infinity)
                .frame(height: 92)
                .background(Color(hex: 0xEEEAF6))
                .overlay(alignment: .bottom) { DashLine().stroke(Theme.rarity(rarity), style: dashStyle).frame(height: 4) }
            VStack(alignment: .leading, spacing: 0) {
                Text("???").font(.game(15)).foregroundStyle(Color(hex: 0x6E6A8E))
                Text(label).font(.vn(10.5, .bold)).foregroundStyle(Theme.rarityText(rarity))
            }
            .padding(EdgeInsets(top: 7, leading: 10, bottom: 9, trailing: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(.rect(cornerRadius: 18))
        .shadow(color: Theme.ink.opacity(0.08), radius: 5, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chưa gặp bé \(rarity.title.lowercased())")
    }

    private var label: String {
        let lower = rarity.title.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}
