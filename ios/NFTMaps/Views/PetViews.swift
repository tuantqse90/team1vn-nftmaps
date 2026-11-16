import CoreLocation
import PhotosUI
import SwiftUI

/// Ảnh JPEG on-chain của một token. Lúc tải (hoặc tải lỗi) hiện nền pastel + hình minh hoạ theo loài như design.
/// Người gọi tự đặt khung và cắt (ảnh dùng `scaledToFill`).
struct OnChainPhoto: View {
    let token: MapToken
    let model: MapViewModel

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                petPastel(token)
                Image(petIllustration(token))
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(0.78)
                    .opacity(failed ? 0.55 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if failed {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.ink2)
                                .padding(4)
                        }
                    }
                    .accessibilityLabel(failed ? "Chưa tải được ảnh" : "Đang tải ảnh")
            }
        }
        .task(id: token.id) {
            do {
                image = UIImage(data: try await model.photo(id: token.id))
            } catch {
                failed = true
            }
        }
    }
}

/// Ghim trên bản đồ: ảnh tròn của bé, viền theo độ hiếm, huy hiệu tím nếu là bé của mình.
struct PetPin: View {
    let token: MapToken
    let isMine: Bool
    let model: MapViewModel

    var body: some View {
        let tint = Theme.rarity(model.rarity(of: token))
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                OnChainPhoto(token: token, model: model)
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(tint, lineWidth: 4))
                Image(systemName: isMine ? "star.fill" : token.species.symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(isMine ? Theme.purple : tint, in: Circle())
                    .offset(x: 4, y: 2)
            }
            PinTip()
                .fill(tint)
                .frame(width: 14, height: 9)
        }
        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(token.name), \(token.species.displayName), \(model.rarity(of: token).title.lowercased())")
        .accessibilityIdentifier("pin-\(token.id)")
    }
}

private struct PinTip: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

// MARK: - Thẻ trong bộ sưu tập

/// Thẻ bé (Collection.dc.html): ảnh trên nền pastel, nhãn NFT, viền đáy màu độ hiếm, tên + độ hiếm.
struct PetCell: View {
    let token: MapToken
    let model: MapViewModel

    var body: some View {
        let rarity = model.rarity(of: token)
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 92)
                .overlay { OnChainPhoto(token: token, model: model) }
                .clipped()
                .overlay(alignment: .topLeading) { NFTTag().padding(6) }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.rarity(rarity)).frame(height: 4) }
            VStack(alignment: .leading, spacing: 0) {
                Text(token.name)
                    .font(.game(15))
                    .lineLimit(1)
                Text(rarityLabel(rarity))
                    .font(.vn(10.5, .bold))
                    .foregroundStyle(Theme.rarityText(rarity))
            }
            .padding(EdgeInsets(top: 7, leading: 10, bottom: 9, trailing: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(.rect(cornerRadius: 18))
        .shadow(color: Theme.ink.opacity(0.08), radius: 5, y: 3)
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(token.name), \(token.species.displayName), \(rarity.title.lowercased())")
        .accessibilityIdentifier("cell-\(token.id)")
    }
}

// MARK: - Chi tiết bé

/// Chi tiết một bé (PetDetail.dc.html): ảnh trên nền pastel, thẻ trắng kéo lên với tên, độ hiếm, chỉ số,
/// bản đồ khu vực (đã làm mờ ±100 m), nhận bé / báo cứu hộ, xem NFT + chia sẻ.
struct TokenDetailView: View {
    let token: MapToken
    let account: SmartAccount
    /// true khi được đẩy vào NavigationStack (nút ‹ quay lại); false khi là gốc của sheet (nút ✕ "Xong" đóng sheet).
    var showsBack = false

    @Environment(GameStore.self) private var game
    @Environment(MapViewModel.self) private var chain
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: Image?
    @State private var place: String?
    @State private var miniMap = PawMapController()

    private var isMine: Bool { token.owner == account.address }
    private var nftURL: URL { Config.explorerURL.appending(path: "nft/\(Config.contractAddress)/\(token.id)") }

    var body: some View {
        let rarity = chain.rarity(of: token)
        ScrollView {
            VStack(spacing: 0) {
                hero
                card(rarity)
                    .padding(.top, -28)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(alignment: .top) { petPastel(token).frame(height: 420) }
        .background(Theme.paper)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) { topBar }
        .foregroundStyle(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle(token.name)
        .task(id: token.id) {
            if let data = try? await chain.photo(id: token.id), let image = UIImage(data: data) {
                shareImage = Image(uiImage: image)
            }
        }
        .task(id: token.id) { place = await RouteService.placeName(token.coordinate) }
    }

    private var topBar: some View {
        HStack {
            BackCircle(symbol: showsBack ? "chevron.left" : "xmark", label: showsBack ? "Quay lại" : "Xong") { dismiss() }
            Spacer()
            Text("NFT #\(token.id)")
                .font(.game(14))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.ink, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var hero: some View {
        ZStack {
            petPastel(token)
            Color.clear
                .frame(width: 230, height: 230)
                .overlay { OnChainPhoto(token: token, model: chain) }
                .clipShape(.rect(cornerRadius: 40))
                .overlay(RoundedRectangle(cornerRadius: 40).strokeBorder(.white, lineWidth: 6))
                .shadow(color: Theme.ink.opacity(0.18), radius: 14, y: 8)
                .rotationEffect(.degrees(-3))
                .padding(.top, 40)
        }
        .frame(height: 380)
    }

    private func card(_ rarity: Rarity) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(token.name)
                        .font(.game(32))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(token.species == .cat ? "Mèo" : "Chó")
                        .font(.vn(14))
                        .foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 0)
                RarityPill(rarity: rarity)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 10) {
                stat("\(max(game.friendship(of: token.id), isMine ? 1 : 0))", "lần gặp")
                stat("\(token.confidence)%", "AI nhận diện")
                catcherTile
            }

            areaMap(rarity)

            HStack(spacing: 8) {
                NavigationLink { ClaimPetView(token: token).hidesTabBar() } label: {
                    pill("Bé nhà bạn?", symbol: "house", tint: Theme.ink)
                }
                NavigationLink { ReportPetView(token: token).hidesTabBar() } label: {
                    pill("Bé cần giúp", symbol: "cross.circle", tint: Theme.orangeText)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Link(destination: nftURL) { Text("Xem NFT") }
                    .buttonStyle(OutlineButtonStyle())
                Group {
                    if let shareImage {
                        ShareLink(item: shareImage, message: Text("Mình gặp bé \(token.name) trên PawRun"),
                                  preview: SharePreview(token.name, image: shareImage)) {
                            Label("Chia sẻ", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        ShareLink(item: nftURL, message: Text("Mình gặp bé \(token.name) trên PawRun")) {
                            Label("Chia sẻ", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .buttonStyle(ChunkyButtonStyle(height: 56))
            }
            .padding(.top, 4)
        }
        .padding(EdgeInsets(top: 24, leading: 16, bottom: 34, trailing: 16))
        .frame(maxWidth: .infinity)
        .background(Theme.paper, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
    }

    /// Ô "người bắt": bé của người khác thì bấm để theo dõi ví người bắt.
    @ViewBuilder
    private var catcherTile: some View {
        if isMine {
            stat("Bạn", "người bắt")
        } else {
            let following = game.isFollowing(token.owner)
            Button {
                following ? game.unfollow(token.owner) : game.follow(token.owner)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(token.owner.short)
                        .font(.game(16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(height: 24, alignment: .leading)
                    Text(following ? "✓ Đang theo dõi" : "+ Theo dõi")
                        .font(.vn(12, .bold))
                        .foregroundStyle(following ? Theme.tealText : Theme.orangeText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                .background(.white, in: .rect(cornerRadius: 18))
                .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(following ? "Đang theo dõi người bắt \(token.owner.short)" : "Theo dõi người bắt \(token.owner.short)")
        }
    }

    private func areaMap(_ rarity: Rarity) -> some View {
        var layers = PawMapLayers()
        layers.me = token.coordinate
        layers.rangeMeters = LocationPrivacy.cellMeters
        layers.rings = [(token.coordinate, Theme.rarity(rarity))]
        return PawMap(controller: miniMap, layers: layers, interactive: false) { EmptyView() }
            .frame(height: 150)
            .clipShape(.rect(cornerRadius: 22))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                    Text("\(place ?? "Khu vực") ±\(Int(LocationPrivacy.cellMeters)) m").lineLimit(1)
                }
                .font(.vn(12, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.white, in: Capsule())
                .shadow(color: Theme.ink.opacity(0.12), radius: 3, y: 2)
                .padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                Link(destination: URL(string: "https://maps.apple.com/?daddr=\(token.latitude),\(token.longitude)&dirflg=w")!) {
                    Label("Chỉ đường", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.vn(12, .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .background(.white, in: Capsule())
                        .shadow(color: Theme.ink.opacity(0.12), radius: 3, y: 2)
                }
                .padding(10)
            }
            .onAppear {
                miniMap.pitch = 0
                miniMap.look(at: token.coordinate, zoom: 15.6, duration: 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Bản đồ khu vực bé, đã làm mờ \(Int(LocationPrivacy.cellMeters)) mét")
    }

    private func pill(_ title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.vn(14, .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.white, in: Capsule())
            .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.game(22))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 24, alignment: .leading)
            Text(label).font(.vn(12)).foregroundStyle(Color(hex: 0x6E6A8E)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(.white, in: .rect(cornerRadius: 18))
        .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Nhận bé

/// Chủ nuôi/người chăm xin ẩn bé khỏi bản đồ (ClaimPet.dc.html). Không có server: app soạn sẵn tin (kèm ảnh) để gửi
/// cho người kiểm duyệt, người kiểm duyệt (owner của MapNFT) gọi `setHidden` sau khi xác minh.
struct ClaimPetView: View {
    let token: MapToken

    private enum Role: String, CaseIterable, Identifiable {
        case owner = "Chủ nuôi"
        case carer = "Người hay chăm bé"

        var id: Self { self }
    }

    @Environment(MapViewModel.self) private var chain
    @Environment(\.dismiss) private var dismiss
    @State private var role: Role = .owner
    @State private var hide = true
    @State private var pickerItem: PhotosPickerItem?
    @State private var homePhoto: UIImage?
    @State private var isSharing = false
    @State private var sent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FormHeader(title: "Bé nhà bạn?") { dismiss() }
                PetSummaryCard(token: token, subtitle: "\(token.species.displayName) · NFT #\(token.id)")
                if sent {
                    SentState(title: "Đã gửi", chip: "Chờ duyệt")
                } else {
                    form
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Bé nhà bạn?")
        .safeAreaInset(edge: .bottom) {
            Group {
                if sent {
                    Button("Xong") { dismiss() }.buttonStyle(ChunkyButtonStyle(height: 58))
                } else {
                    Button("Gửi xác nhận") { isSharing = true }
                        .buttonStyle(ChunkyButtonStyle(fill: homePhoto == nil ? Theme.line : Theme.orange,
                                                       shadow: homePhoto == nil ? Theme.line : Theme.orangeDeep,
                                                       foreground: homePhoto == nil ? Theme.ink2 : .white, height: 58))
                        .disabled(homePhoto == nil)
                        .accessibilityHint(homePhoto == nil ? "Thêm ảnh bé ở nhà trước" : "")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(Theme.paper)
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) { homePhoto = UIImage(data: data) }
            }
        }
        .sheet(isPresented: $isSharing) {
            CompletableShareSheet(items: [message] + (homePhoto.map { [$0] } ?? [])) { completed in
                if completed { withAnimation(.spring) { sent = true } }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bạn là").font(.game(17)).padding(.horizontal, 4)
                ForEach(Role.allCases) { option in
                    Button { role = option } label: {
                        HStack(spacing: 12) {
                            RadioDot(on: role == option)
                            Text(option.rawValue).font(.vn(15, .bold))
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 56)
                        .background(.white, in: .rect(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(role == option ? Theme.orange : Theme.line, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(role == option ? .isSelected : [])
                }
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                DashedPhotoBox(height: 96, title: homePhoto == nil ? "Ảnh bé ở nhà" : "Đổi ảnh", image: homePhoto)
            }
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                Toggle(isOn: $hide) {
                    RowLabel(symbol: "eye.slash", tint: Theme.orangeText, background: Theme.orangeSoft, title: "Ẩn bé khỏi bản đồ")
                }
                .toggleStyle(CheckToggleStyle())
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
            }
            .background(.white, in: .rect(cornerRadius: 20))
            .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)

            Text("Người kiểm duyệt xem ảnh rồi mới ẩn. Ẩn chỉ bỏ ghim trong app, NFT vẫn còn trên chuỗi.")
                .font(.vn(12))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 4)
        }
    }

    private var message: String {
        """
        PawRun · Yêu cầu nhận bé
        Bé: \(token.name) (NFT #\(token.id), contract \(Config.contractAddress))
        Tôi là: \(role.rawValue)
        Yêu cầu: \(hide ? "ẩn bé khỏi bản đồ" : "xác nhận là bé nhà tôi")
        Ảnh bé ở nhà đính kèm.
        """
    }
}

// MARK: - Báo bé cần giúp

/// Soạn tin cứu hộ có vị trí thật (lấy ngay lúc báo, không làm mờ) + ảnh, gửi qua Zalo/Messenger/Mail cho nhóm cứu hộ
/// (ReportPet.dc.html). Vị trí thật chỉ nằm trong tin nhắn này, không lên chuỗi.
struct ReportPetView: View {
    let token: MapToken

    private static let issues = ["Bị thương", "Gầy yếu", "Bị lạc", "Gặp nguy"]

    @Environment(MapViewModel.self) private var chain
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var note = ""
    @State private var sendLocation = true
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var shareItems: [Any] = []
    @State private var isSharing = false
    @State private var isPreparing = false
    @State private var sent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FormHeader(title: "Bé cần giúp") { dismiss() }
                PetSummaryCard(token: token, subtitle: "\(token.species.displayName) · NFT #\(token.id)")
                if sent {
                    SentState(title: "Đã gửi cứu hộ", chip: "Cảm ơn bạn")
                } else {
                    form
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Bé cần giúp")
        .safeAreaInset(edge: .bottom) {
            Group {
                if sent {
                    Button("Xong") { dismiss() }.buttonStyle(ChunkyButtonStyle(height: 58))
                } else {
                    let ready = !picked.isEmpty && !isPreparing
                    Button(isPreparing ? "Đang lấy vị trí…" : "Gửi cứu hộ") { Task { await prepare() } }
                        .buttonStyle(ChunkyButtonStyle(fill: ready ? Theme.orange : Theme.line,
                                                       shadow: ready ? Theme.orangeDeep : Theme.line,
                                                       foreground: ready ? .white : Theme.ink2, height: 58))
                        .disabled(!ready)
                        .accessibilityHint(picked.isEmpty ? "Chọn bé bị gì trước" : "")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(Theme.paper)
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) { photo = UIImage(data: data) }
            }
        }
        .sheet(isPresented: $isSharing) {
            CompletableShareSheet(items: shareItems) { completed in
                if completed { withAnimation(.spring) { sent = true } }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bé bị gì?").font(.game(17)).padding(.horizontal, 4)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Self.issues, id: \.self) { issue in
                        let on = picked.contains(issue)
                        Button {
                            if on { picked.remove(issue) } else { picked.insert(issue) }
                        } label: {
                            HStack(spacing: 6) {
                                if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)) }
                                Text(issue)
                            }
                            .font(.vn(14, .bold))
                            .foregroundStyle(on ? .white : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(on ? Theme.ink : .white, in: .rect(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(on ? Theme.ink : Theme.line, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                DashedPhotoBox(height: 64, title: photo == nil ? "Thêm ảnh" : "Đổi ảnh", image: photo, horizontal: true)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("Ghi chú").font(.vn(13, .bold)).padding(.horizontal, 4)
                TextField("Bé ở đâu, trông thế nào…", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.vn(14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 64, alignment: .topLeading)
                    .background(.white, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line, lineWidth: 2))
            }

            Toggle(isOn: $sendLocation) {
                RowLabel(symbol: "location.fill", tint: Theme.tealText, background: Theme.tealSoft, title: "Gửi vị trí thật cho cứu hộ")
            }
            .toggleStyle(CheckToggleStyle())
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(.white, in: .rect(cornerRadius: 18))
            .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)

            Text("Không chọn ảnh mới thì gửi ảnh bé trên thẻ. Vị trí thật chỉ nằm trong tin nhắn, không lên chuỗi.")
                .font(.vn(12))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 4)
        }
    }

    private func prepare() async {
        isPreparing = true
        defer { isPreparing = false }
        var lines = ["PawRun · Bé cần giúp", "Bé: \(token.name) (\(token.species.displayName))",
                     "Tình trạng: \(Self.issues.filter(picked.contains).joined(separator: ", "))"]
        if !note.isEmpty { lines.append("Ghi chú: \(note)") }
        if sendLocation, let here = await LocationOnce.current() {
            lines.append("Vị trí: https://maps.apple.com/?ll=\(here.latitude),\(here.longitude)&q=Be%20can%20giup")
        }
        var image = photo
        if image == nil, let data = try? await chain.photo(id: token.id) { image = UIImage(data: data) }
        shareItems = [lines.joined(separator: "\n")] + (image.map { [$0] } ?? [])
        isSharing = true
    }
}

// MARK: - Mảnh dùng chung trong file

/// Nền pastel của thẻ bé (bảng màu thẻ trong Collection.dc.html), cố định theo id.
private func petPastel(_ token: MapToken) -> Color {
    let palette: [UInt32] = [0xFFE9D6, 0xF1E9DD, 0xE3E0F5, 0xEDE3F9, 0xFFF1D6, 0xE6F2FB, 0xE6ECF5]
    return Color(hex: palette[Int(token.id % UInt64(palette.count))])
}

/// Hình minh hoạ theo loài, dùng khi chưa có ảnh.
private func petIllustration(_ token: MapToken) -> String {
    switch token.species {
    case .dog: "pet-dog"
    case .cat: token.id % 2 == 0 ? "pet-cat" : "pet-cat-black"
    }
}

/// "HIẾM" → "Hiếm" (chữ dưới tên trên thẻ).
private func rarityLabel(_ rarity: Rarity) -> String {
    let lower = rarity.title.lowercased()
    return lower.prefix(1).uppercased() + lower.dropFirst()
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

/// Nhãn độ hiếm cỡ lớn (PetDetail): chữ Baloo + sao.
private struct RarityPill: View {
    let rarity: Rarity

    var body: some View {
        HStack(spacing: 4) {
            Text(rarity.title).tracking(0.8)
            ForEach(0..<rarity.stars, id: \.self) { _ in Image(systemName: "star.fill").font(.system(size: 9)) }
        }
        .font(.game(14))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Theme.rarity(rarity), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Độ hiếm \(rarity.title.lowercased())")
    }
}

/// Nút tròn trắng 44pt ở góc trên (quay lại / đóng).
private struct BackCircle: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(.white, in: Circle())
                .shadow(color: Theme.ink.opacity(0.1), radius: 5, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Đầu trang form: nút quay lại + tiêu đề Baloo 28.
private struct FormHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            BackCircle(symbol: "chevron.left", label: "Quay lại", action: back)
            Text(title).font(.game(28)).accessibilityAddTraits(.isHeader)
            Spacer()
        }
    }
}

/// Thẻ nhỏ: ảnh bé 64pt viền đáy màu độ hiếm + tên + dòng phụ.
private struct PetSummaryCard: View {
    let token: MapToken
    let subtitle: String

    @Environment(MapViewModel.self) private var chain

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 64, height: 64)
                .overlay { OnChainPhoto(token: token, model: chain) }
                .clipShape(.rect(cornerRadius: 16))
                .overlay(alignment: .bottom) {
                    UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
                        .fill(Theme.rarity(chain.rarity(of: token)))
                        .frame(height: 4)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(token.name).font(.game(20)).lineLimit(1)
                Text(subtitle).font(.vn(12)).foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.white, in: .rect(cornerRadius: 20))
        .shadow(color: Theme.ink.opacity(0.06), radius: 5, y: 3)
        .accessibilityElement(children: .combine)
    }
}

/// Ô chọn ảnh viền nét đứt.
private struct DashedPhotoBox: View {
    let height: CGFloat
    let title: String
    let image: UIImage?
    var horizontal = false

    var body: some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 6))
        layout {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: height - 20, height: height - 20)
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                Image(systemName: "camera")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
            }
            Text(title).font(.vn(13, .bold))
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .background(.white, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Color(hex: 0xC9C4DE), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
        .contentShape(Rectangle())
    }
}

/// Icon vuông bo góc + chữ đậm (dòng trong thẻ cài đặt).
private struct RowLabel: View {
    let symbol: String
    let tint: Color
    let background: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(background, in: .rect(cornerRadius: 12))
            Text(title).font(.vn(14, .bold)).foregroundStyle(Theme.ink)
        }
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

private struct RadioDot: View {
    let on: Bool

    var body: some View {
        Circle()
            .strokeBorder(on ? Theme.orange : Color(hex: 0xC9C4DE), lineWidth: 2)
            .background(Circle().fill(.white))
            .overlay { if on { Circle().fill(Theme.orange).padding(5) } }
            .frame(width: 22, height: 22)
    }
}

/// Màn "đã gửi": dấu tích xanh ngọc, tiêu đề, chip trạng thái.
private struct SentState: View {
    let title: String
    let chip: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(Theme.teal, in: Circle())
                .background(Theme.tealText, in: Circle().offset(y: 6))
            Text(title).font(.game(30))
            Text(chip)
                .font(.vn(13, .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Theme.line, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

/// Bảng chia sẻ iOS báo lại người dùng đã gửi (completed) hay huỷ.
private struct CompletableShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
