import AVFoundation
import CoreLocation
import CoreMotion
import SwiftUI

/// Hồ sơ (Profile.dc.html): nút bạn bè / cài đặt, nhân vật + cấp + XP, 3 ô chỉ số, lưới huy hiệu,
/// thẻ ví + tuỳ chọn nhanh, bé chờ mint, lịch sử chạy.
struct ProfileView: View {
    let session: WalletSession
    let account: SmartAccount

    @Environment(GameStore.self) private var game
    @Environment(MapViewModel.self) private var chain
    @AppStorage("fuzzLocation") private var fuzzLocation = true
    @AppStorage("voiceMilestones") private var voiceMilestones = true
    @State private var copied = false

    private var myPets: [MapToken] { chain.tokens(ownedBy: account.address) }
    private var myRunNFTs: Int { chain.runs(ownedBy: account.address).count }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Spacer()
                    NavigationLink { FriendsView(account: account).hidesTabBar() } label: {
                        CircleGlyph(symbol: "person.2")
                    }
                    .accessibilityLabel("Bạn bè")
                    NavigationLink { SettingsView(session: session, account: account).hidesTabBar() } label: {
                        CircleGlyph(symbol: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Cài đặt")
                }
                .buttonStyle(.plain)

                header

                HStack(spacing: 10) {
                    StatTile(value: kmText(game.totalRunMeters), label: "km")
                    StatTile(value: "\(myPets.count)", label: "bé")
                    StatTile(value: "\(myPets.count + myRunNFTs)", label: "NFT")
                }

                badges

                VStack(spacing: 0) {
                    walletRow
                    Divider().overlay(Color(hex: 0xF0ECF6))
                    Toggle(isOn: $fuzzLocation) {
                        RowLabel(symbol: "lock", tint: Theme.orangeText, background: Theme.orangeSoft, title: "Làm mờ vị trí")
                    }
                    .toggleStyle(CheckToggleStyle())
                    .padding(.horizontal, 14)
                    .frame(minHeight: 56)
                    Divider().overlay(Color(hex: 0xF0ECF6))
                    Toggle(isOn: $voiceMilestones) {
                        RowLabel(symbol: "speaker.wave.2", tint: Color(hex: 0x2563D9), background: Theme.blueSoft,
                                 title: "Đọc mốc khi chạy")
                    }
                    .toggleStyle(CheckToggleStyle())
                    .padding(.horizontal, 14)
                    .frame(minHeight: 56)
                    Divider().overlay(Color(hex: 0xF0ECF6))
                    NavigationLink { PendingMintsView(account: account).hidesTabBar() } label: {
                        NavRow(symbol: "tray.and.arrow.up", tint: Theme.goldText, background: Theme.goldSoft,
                               title: "Bé chờ mint", detail: "\(game.progress.pendingMints.count)")
                    }
                    .buttonStyle(.plain)
                }
                .background(.white, in: .rect(cornerRadius: 20))
                .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)

                if !game.progress.runs.isEmpty { recentRuns }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24 + tabBarClearance)
        }
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0).background(Theme.paper) }
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Hồ sơ")
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .topLeading) {
                Color(hex: 0xC3EA96)
                Image("hero-stand")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 157)
                    .offset(x: -6, y: 4)
            }
            .frame(width: 92, height: 92)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 4))
            .shadow(color: Theme.ink.opacity(0.12), radius: 8, y: 6)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(session.username)
                        .font(.game(30))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Lv \(game.level)")
                        .font(.game(14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Theme.purple, in: Capsule())
                        .fixedSize()
                }
                ProgressBar(value: game.levelProgress, tint: Theme.purple, height: 10)
                HStack {
                    Text("\(GameRules.number(game.progress.xp)) / \(GameRules.number(GameRules.xpRequired(forLevel: game.level + 1))) XP")
                        .font(.vn(12))
                        .foregroundStyle(Color(hex: 0x6E6A8E))
                    Spacer()
                    CoinBadge(amount: game.progress.coins)
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    /// Lưới huy hiệu 3 cột: chuỗi ngày, bé hiếm nhất, số khu, rồi các huy chương (chưa có thì ô nét đứt có khoá).
    private var badges: some View {
        let rarest = myPets.max { chain.rarity(of: $0) < chain.rarity(of: $1) }
        let areas = Set(myPets.map { LocationPrivacy.area($0.coordinate) }).count
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            BadgeTile(title: "\(game.streak) ngày", background: Theme.orangeSoft) {
                FlameGlyph().frame(width: 24, height: 26)
            }
            .accessibilityLabel("Chuỗi \(game.streak) ngày")
            if let rarest {
                BadgeTile(title: rarest.name, background: Theme.rarity(chain.rarity(of: rarest)).opacity(0.18)) {
                    OnChainPhoto(token: rarest, model: chain).frame(width: 40, height: 40).clipShape(Circle())
                }
                .accessibilityLabel("Bé hiếm nhất: \(rarest.name), \(chain.rarity(of: rarest).title.lowercased())")
            }
            BadgeTile(title: "\(areas) khu", background: Theme.tealSoft) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.tealText)
            }
            .accessibilityLabel("Gặp bé ở \(areas) khu")
            ForEach(Medal.allCases) { medal in
                let unlocked = game.progress.medals[medal] != nil
                BadgeTile(title: medal.title, background: unlocked ? Theme.goldSoft : Color(hex: 0xE6E1F0), locked: !unlocked) {
                    Image(systemName: unlocked ? medal.symbol : "lock")
                        .font(.system(size: unlocked ? 22 : 20, weight: .bold))
                        .foregroundStyle(unlocked ? Color(hex: 0x946200) : Color(hex: 0x7A75A0))
                }
                .accessibilityLabel("\(medal.title), \(unlocked ? "đã có" : "chưa có")")
            }
        }
    }

    private var walletRow: some View {
        Button {
            UIPasteboard.general.string = account.address.hex
            copied = true
        } label: {
            HStack(spacing: 12) {
                RowLabel(symbol: "wallet.bifold", tint: Theme.purpleText, background: Theme.purpleSoft, title: account.address.short)
                Spacer()
                Text(copied ? "Đã chép" : "Đã nối")
                    .font(.vn(12, .bold))
                    .foregroundStyle(Theme.tealText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Theme.tealSoft, in: Capsule())
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ví \(account.address.short)")
        .accessibilityHint("Chép địa chỉ ví")
    }

    private var recentRuns: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vòng chạy gần đây").font(.game(20)).padding(.horizontal, 4).padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(game.progress.runs.suffix(5).reversed().enumerated()), id: \.element.id) { index, run in
                    if index > 0 { Divider().overlay(Color(hex: 0xF0ECF6)) }
                    HStack(spacing: 12) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.orangeText)
                            .frame(width: 36, height: 36)
                            .background(Theme.orangeSoft, in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(GameRules.metersText(run.meters)).font(.game(17))
                            Text(run.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.vn(12)).foregroundStyle(Theme.ink2)
                        }
                        Spacer()
                        Text("\(GameRules.number(run.steps)) bước").font(.vn(13, .semibold)).foregroundStyle(Theme.ink2)
                        if run.mintedTokenID != nil {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.teal)
                                .accessibilityLabel("Đã mint")
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 58)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(.white, in: .rect(cornerRadius: 20))
            .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
        }
    }

    private func kmText(_ meters: Double) -> String {
        let km = meters / 1000
        return km >= 10 ? GameRules.number(Int(km.rounded())) : String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Cài đặt

/// Cài đặt (Settings.dc.html): nhóm thẻ trắng có tiêu đề chữ hoa, ô tích cam, đăng xuất.
struct SettingsView: View {
    let session: WalletSession
    let account: SmartAccount

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("fuzzLocation") private var fuzzLocation = true
    @AppStorage("voiceMilestones") private var voiceMilestones = true
    @State private var locationStatus = ""
    @State private var cameraStatus = ""
    @State private var motionStatus = ""

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Cài đặt") { dismiss() }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("TÀI KHOẢN")
                    Group {
                        VStack(spacing: 0) {
                            Link(destination: Config.explorerURL.appending(path: "address/\(account.address.hex)")) {
                                NavRow(symbol: "wallet.bifold", tint: Theme.purpleText, background: Theme.purpleSoft,
                                       title: "Ví", detail: account.address.short, compact: true)
                            }
                            RowDivider()
                            InfoRow(symbol: "person", tint: Theme.ink, background: Theme.line,
                                    title: "Đăng nhập", detail: session.username)
                            RowDivider()
                            InfoRow(symbol: "network", tint: Theme.tealText, background: Theme.tealSoft,
                                    title: "Mạng", detail: "Avalanche Fuji")
                        }
                    }
                    .settingsCard()

                    SectionLabel("QUYỀN")
                    VStack(spacing: 0) {
                        Button(action: openSettings) {
                            NavRow(symbol: "location", tint: Theme.orangeText, background: Theme.orangeSoft,
                                   title: "Vị trí", detail: locationStatus, compact: true)
                        }
                        RowDivider()
                        Button(action: openSettings) {
                            NavRow(symbol: "camera", tint: Color(hex: 0x2563D9), background: Theme.blueSoft,
                                   title: "Camera", detail: cameraStatus, compact: true)
                        }
                        RowDivider()
                        Button(action: openSettings) {
                            NavRow(symbol: "figure.walk", tint: Theme.purpleText, background: Theme.purpleSoft,
                                   title: "Chuyển động", detail: motionStatus, compact: true)
                        }
                    }
                    .buttonStyle(.plain)
                    .settingsCard()

                    SectionLabel("RIÊNG TƯ")
                    Toggle(isOn: $fuzzLocation) {
                        RowLabel(symbol: "lock", tint: Theme.orangeText, background: Theme.orangeSoft,
                                 title: "Làm mờ vị trí khi mint (±100 m)", compact: true)
                    }
                    .toggleStyle(CheckToggleStyle())
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .settingsCard()
                    Footnote(fuzzLocation
                             ? "Toạ độ lên chuỗi được kéo về tâm ô 100 m. Vòng chạy chỉ lưu hình, bỏ 200 m đầu và cuối."
                             : "Tắt thì toạ độ chính xác sẽ lên chuỗi công khai và không xoá được.")

                    SectionLabel("CHẠY")
                    VStack(spacing: 0) {
                        InfoRow(symbol: "ruler", tint: Theme.tealText, background: Theme.tealSoft, title: "Đơn vị", detail: "Mét")
                        RowDivider()
                        Toggle(isOn: $voiceMilestones) {
                            RowLabel(symbol: "speaker.wave.2", tint: Color(hex: 0x2563D9), background: Theme.blueSoft,
                                     title: "Đọc mốc khi chạy", compact: true)
                        }
                        .toggleStyle(CheckToggleStyle())
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                    }
                    .settingsCard()

                    Button { session.signOut() } label: {
                        Text("Đăng xuất")
                            .font(.vn(15, .bold))
                            .foregroundStyle(Theme.orangeText)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(.white, in: .rect(cornerRadius: 18))
                            .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    Footnote("Ví sinh từ tên + mật khẩu. Đăng nhập lại đúng mật khẩu là về ví cũ.")
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Cài đặt")
        .task(id: scenePhase) { refreshPermissions() }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    private func refreshPermissions() {
        locationStatus = switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: "Luôn luôn"
        case .authorizedWhenInUse: "Khi dùng app"
        case .denied, .restricted: "Đã tắt"
        default: "Chưa hỏi"
        }
        cameraStatus = switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: "Bật"
        case .denied, .restricted: "Đã tắt"
        default: "Chưa hỏi"
        }
        motionStatus = switch CMPedometer.authorizationStatus() {
        case .authorized: "Bật"
        case .denied, .restricted: "Đã tắt"
        default: "Chưa hỏi"
        }
    }
}

// MARK: - Bạn bè

/// Theo dõi ví khác (nhập địa chỉ hoặc bấm "Theo dõi" ở thẻ bé) và xem bé/vòng chạy họ mint, đọc từ chuỗi
/// (Friends.dc.html). App một người chơi, không có server: không có "đang chạy" hay lượt khen.
struct FriendsView: View {
    let account: SmartAccount

    private enum Item: Identifiable {
        case pet(MapToken)
        case run(RunToken)

        var id: String {
            switch self {
            case .pet(let token): "pet-\(token.id)"
            case .run(let run): "run-\(run.id)"
            }
        }

        var owner: Address {
            switch self {
            case .pet(let token): token.owner
            case .run(let run): run.owner
            }
        }
    }

    @Environment(GameStore.self) private var game
    @Environment(MapViewModel.self) private var chain
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var invalid = false
    @State private var isAdding = false
    @FocusState private var inputFocused: Bool

    private var feed: [Item] {
        let followed = Set(game.followedAddresses)
        let pets = chain.visibleTokens.filter { followed.contains($0.owner) }.map(Item.pet)
        let runs = chain.runs.filter { followed.contains($0.owner) }.map(Item.run)
        // Không có thời gian mint cho bé on-chain → xếp bé theo id, vòng chạy chen theo thứ tự id riêng.
        return (pets.reversed() + runs.reversed()).prefix(30).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    BackCircle(label: "Quay lại") { dismiss() }
                    Text("Bạn bè").font(.game(28)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        withAnimation(.snappy) { isAdding.toggle() }
                        if isAdding { inputFocused = true }
                    } label: {
                        Image(systemName: isAdding ? "xmark" : "person.badge.plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Theme.orange, in: Circle())
                            .background(Theme.orangeDeep, in: Circle().offset(y: 4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isAdding ? "Đóng thêm bạn" : "Thêm bạn")
                }

                if isAdding || game.followedAddresses.isEmpty { addCard }

                SectionLabel("ĐANG THEO DÕI")
                following

                VStack(spacing: 10) {
                    if feed.isEmpty {
                        Text("Theo dõi ai đó để xem bé và vòng chạy họ mint.")
                            .font(.vn(14))
                            .foregroundStyle(Theme.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.white, in: .rect(cornerRadius: 20))
                            .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
                    }
                    ForEach(feed) { item in feedCard(item) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0).background(Theme.paper) }
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Bạn bè")
        .refreshable { await chain.refresh() }
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Địa chỉ ví 0x…", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14, design: .monospaced))
                    .focused($inputFocused)
                    .submitLabel(.done)
                    .onSubmit(follow)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Theme.paper, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 2))
                Button("Theo dõi", action: follow)
                    .font(.game(16))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(input.isEmpty ? Theme.ink2.opacity(0.4) : Theme.ink, in: Capsule())
                    .disabled(input.isEmpty)
            }
            if invalid { Text("Địa chỉ không hợp lệ").font(.vn(12, .bold)).foregroundStyle(Theme.orangeText) }
            Text("Mời bạn: gửi địa chỉ ví của bạn \(account.address.short) (chép ở Hồ sơ).")
                .font(.vn(12))
                .foregroundStyle(Theme.ink2)
        }
        .padding(12)
        .background(.white, in: .rect(cornerRadius: 20))
        .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var following: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ShareLink(item: account.address.hex, message: Text("Theo dõi mình trên PawRun")) {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.ink2)
                            .frame(width: 56, height: 56)
                            .overlay(Circle().strokeBorder(Color(hex: 0xC9C4DE), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                        Text("Mời").font(.vn(11, .bold)).foregroundStyle(Theme.ink2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mời bạn: gửi địa chỉ ví của bạn")
                ForEach(game.followedAddresses, id: \.self) { address in
                    VStack(spacing: 4) {
                        AddressAvatar(address: address, size: 56)
                        Text(address.short).font(.vn(11, .bold)).lineLimit(1)
                        Text("\(chain.tokens(ownedBy: address).count) bé · \(chain.runs(ownedBy: address).count) vòng")
                            .font(.vn(10, .semibold))
                            .foregroundStyle(Theme.ink2)
                    }
                    .frame(width: 84)
                    .contextMenu {
                        Button("Bỏ theo dõi", systemImage: "person.badge.minus", role: .destructive) { game.unfollow(address) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAction(named: "Bỏ theo dõi") { game.unfollow(address) }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -16)
    }

    @ViewBuilder
    private func feedCard(_ item: Item) -> some View {
        let card = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AddressAvatar(address: item.owner, size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.owner.short).font(.vn(14, .bold))
                    Text(subtitle(item)).font(.vn(11)).foregroundStyle(Theme.ink2)
                }
            }
            HStack(spacing: 12) {
                switch item {
                case .pet(let token):
                    Color.clear
                        .frame(width: 56, height: 56)
                        .overlay { OnChainPhoto(token: token, model: chain) }
                        .clipShape(.rect(cornerRadius: 16))
                        .overlay(alignment: .bottom) {
                            UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
                                .fill(Theme.rarity(chain.rarity(of: token))).frame(height: 4)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gặp \(token.name)").font(.game(18)).lineLimit(1)
                        Text("\(capitalized(chain.rarity(of: token).title)) · \(token.species.displayName)")
                            .font(.vn(12, .semibold)).foregroundStyle(Theme.ink2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink2)
                case .run(let run):
                    RunThumb(run: run)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GameRules.metersText(Double(run.meters))).font(.game(18))
                        Text("\(GameRules.number(run.steps)) bước · \(run.name)")
                            .font(.vn(12, .semibold)).foregroundStyle(Theme.ink2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: .rect(cornerRadius: 20))
        .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
        .accessibilityElement(children: .combine)

        if case .pet(let token) = item {
            NavigationLink { TokenDetailView(token: token, account: account, showsBack: true).hidesTabBar() } label: { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    private func subtitle(_ item: Item) -> String {
        switch item {
        case .pet(let token): "NFT #\(token.id)"
        case .run(let run): run.finishedAt.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private func follow() {
        guard let address = try? Address(input.trimmingCharacters(in: .whitespacesAndNewlines)),
              address != account.address else {
            invalid = true
            return
        }
        invalid = false
        game.follow(address)
        input = ""
        withAnimation(.snappy) { isAdding = false }
    }
}

// MARK: - Mảnh dùng trong file

/// Thanh tab tự vẽ của AppShell (cao ~62pt + nút CHẠY nhô ~28pt) không đẩy safe area vào trong NavigationStack,
/// nên nội dung tự chừa chỗ để phần cuối cuộn lên được trên thanh tab.
private let tabBarClearance: CGFloat = 92

private func capitalized(_ upper: String) -> String {
    let lower = upper.lowercased()
    return lower.prefix(1).uppercased() + lower.dropFirst()
}

private struct CircleGlyph: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(width: 44, height: 44)
            .background(.white, in: Circle())
            .shadow(color: Theme.ink.opacity(0.08), radius: 5, y: 3)
    }
}

private struct BackCircle: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { CircleGlyph(symbol: "chevron.left") }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}

private struct PageHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            BackCircle(label: "Quay lại", action: back)
            Text(title).font(.game(28)).accessibilityAddTraits(.isHeader)
            Spacer()
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

/// Ô huy hiệu: vòng tròn icon 48pt + nhãn; chưa mở thì nền tím nhạt viền nét đứt.
private struct BadgeTile<Icon: View>: View {
    let title: String
    let background: Color
    var locked = false
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        VStack(spacing: 6) {
            icon()
                .frame(width: 48, height: 48)
                .background(background, in: Circle())
            Text(title)
                .font(.vn(12, .bold))
                .foregroundStyle(locked ? Color(hex: 0x6E6A8E) : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 12, leading: 6, bottom: 10, trailing: 6))
        .background(locked ? Color(hex: 0xF3F0F8) : .white, in: .rect(cornerRadius: 18))
        .overlay {
            if locked {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color(hex: 0xD9D3E8), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        .shadow(color: Theme.ink.opacity(locked ? 0 : 0.06), radius: 5, y: 3)
        .accessibilityElement(children: .ignore)
    }
}

private struct RowLabel: View {
    let symbol: String
    let tint: Color
    let background: Color
    let title: String
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 15 : 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: compact ? 34 : 36, height: compact ? 34 : 36)
                .background(background, in: .rect(cornerRadius: compact ? 11 : 12))
            Text(title).font(.vn(14, .bold)).foregroundStyle(Theme.ink)
        }
    }
}

/// Dòng có chi tiết bên phải + mũi tên.
private struct NavRow: View {
    let symbol: String
    let tint: Color
    let background: Color
    let title: String
    let detail: String
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            RowLabel(symbol: symbol, tint: tint, background: background, title: title, compact: compact)
            Spacer(minLength: 8)
            Text(detail).font(.vn(13)).foregroundStyle(Theme.ink2).lineLimit(1)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: compact ? 52 : 56)
        .contentShape(Rectangle())
    }
}

private struct InfoRow: View {
    let symbol: String
    let tint: Color
    let background: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            RowLabel(symbol: symbol, tint: tint, background: background, title: title, compact: true)
            Spacer(minLength: 8)
            Text(detail).font(.vn(13)).foregroundStyle(Theme.ink2).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

private struct RowDivider: View {
    var body: some View { Divider().overlay(Color(hex: 0xF0ECF6)) }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.vn(12, .heavy))
            .tracking(1)
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct Footnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.vn(12)).foregroundStyle(Theme.ink2).padding(.horizontal, 6)
    }
}

private extension View {
    func settingsCard() -> some View {
        background(.white, in: .rect(cornerRadius: 20))
            .clipShape(.rect(cornerRadius: 20))
            .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
    }
}

/// Ô tích cam (thay công tắc iOS, đúng design).
private struct CheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isOn ? Theme.orange : .white)
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                        } else {
                            RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0xC9C4DE), lineWidth: 2)
                        }
                    }
                    .frame(width: 22, height: 22)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "Bật" : "Tắt")
    }
}

/// Avatar tròn màu pastel với 2 ký tự đầu của địa chỉ ví.
private struct AddressAvatar: View {
    let address: Address
    let size: CGFloat

    var body: some View {
        let hex = address.hex.lowercased().hasPrefix("0x") ? String(address.hex.dropFirst(2)) : address.hex
        let palette: [UInt32] = [0xFFE08A, 0xC2DAFF, 0xDDF5F1, 0xFFD9BF, 0xE3E0F5]
        let index = Int(hex.unicodeScalars.reduce(0) { $0 &+ $1.value } % UInt32(palette.count))
        Text(hex.prefix(2).uppercased())
            .font(size > 40 ? .game(17) : .vn(12, .heavy))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(Color(hex: palette[index]), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Hình vòng chạy nhỏ trên nền cỏ (thẻ bảng tin).
private struct RunThumb: View {
    let run: RunToken

    @Environment(MapViewModel.self) private var chain
    @State private var shape: Data?

    var body: some View {
        ZStack {
            Color(hex: 0xC3EA96)
            if let shape { RouteShapeView(shape: shape, lineWidth: 3).padding(8) }
        }
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 16))
        .task(id: run.id) { shape = try? await chain.route(runID: run.id) }
    }
}
