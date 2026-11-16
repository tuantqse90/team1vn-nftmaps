import CoreLocation
import Observation
import SwiftUI

/// Gửi một lệnh gọi contract qua smart account: dựng UserOperation → paymaster trả gas → app tự ký → bundler gửi.
@MainActor
@Observable
final class MintModel {
    enum Stage: Equatable {
        case idle
        case preparing
        case sponsoring
        case sending
        case confirming
        case done(transactionHash: String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .preparing, .sponsoring, .sending, .confirming: true
            default: false
            }
        }

        /// 0…3 cho danh sách bước trên màn mint.
        var step: Int {
            switch self {
            case .idle, .failed: -1
            case .preparing: 0
            case .sponsoring: 1
            case .sending: 2
            case .confirming: 3
            case .done: 4
            }
        }
    }

    private(set) var stage: Stage = .idle

    var isDone: Bool {
        if case .done = stage { true } else { false }
    }

    @discardableResult
    func send(target: Address, data: Data, account: SmartAccount) async -> Bool {
        do {
            let bundler = PimlicoBundler(
                client: JSONRPCClient(url: try Config.bundlerURL()),
                entryPoint: account.entryPoint,
                sponsorshipPolicyID: Config.pimlicoSponsorshipPolicyID.isEmpty ? nil : Config.pimlicoSponsorshipPolicyID
            )
            stage = .preparing
            var operation = try await account.buildUserOperation(target: target, data: data)
            let gasPrice = try await bundler.gasPrice()
            operation.maxFeePerGas = gasPrice.maxFeePerGas
            operation.maxPriorityFeePerGas = gasPrice.maxPriorityFeePerGas

            stage = .sponsoring
            operation = try await bundler.sponsor(operation)

            stage = .sending
            let userOpHash = try await bundler.send(try account.sign(operation))

            stage = .confirming
            let receipt = try await bundler.waitForReceipt(userOpHash: userOpHash)
            guard receipt.success else { throw MintError.reverted(receipt.reason) }
            stage = .done(transactionHash: receipt.receipt.transactionHash)
            return true
        } catch {
            stage = .failed(error.localizedDescription)
            return false
        }
    }

    enum MintError: LocalizedError {
        case reverted(String?)

        var errorDescription: String? {
            switch self {
            case .reverted(let reason): "Giao dịch bị revert\(reason.map { ": \($0)" } ?? "")"
            }
        }
    }
}

enum LocationOnce {
    /// Vị trí hiện tại, chờ tối đa `timeout`. nil nếu không có quyền hoặc không bắt được GPS.
    @MainActor
    static func current(timeout: Duration = .seconds(15)) async -> CLLocationCoordinate2D? {
        await withTaskGroup(of: CLLocationCoordinate2D?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location { return location.coordinate }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

extension MapNFTCall {
    static func mint(latitude: Double, longitude: Double, species: UInt8, confidence: UInt8, name: String, photo: Data) -> Data {
        ABI.call(ABI.Selector.mint, [
            .int(Int64((latitude * 1e6).rounded())),
            .int(Int64((longitude * 1e6).rounded())),
            .uint(UInt64(species)),
            .uint(UInt64(confidence)),
            .string(name),
            .bytes(photo),
        ])
    }
}

/// Bắt bé: màn camera → (nhận ra bé quen? gặp lại) → mint. Dùng ở bản đồ và lúc đang chạy.
struct CaptureFlow: ViewModifier {
    @Binding var isPresented: Bool
    let account: SmartAccount
    var onPetMet: (() -> Void)?

    @State private var pending: CaughtPet?
    @State private var minting: CaughtPet?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented, onDismiss: {
                minting = pending
                pending = nil
            }) {
                CatchScreen { pending = $0 }
            }
            .fullScreenCover(item: $minting) { pet in
                MintSheet(account: account, pet: pet, onPetMet: onPetMet)
            }
    }
}

extension View {
    func captureFlow(isPresented: Binding<Bool>, account: SmartAccount, onPetMet: (() -> Void)? = nil) -> some View {
        modifier(CaptureFlow(isPresented: isPresented, account: account, onPetMet: onPetMet))
    }
}

struct MintSheet: View {
    let account: SmartAccount
    let pet: CaughtPet
    var onPetMet: (() -> Void)?

    private enum Phase {
        case checking
        case again(MapToken)
        case againConfirmed(MapToken)
        /// "Bé mới!" — thẻ bé, đặt tên (artboard Reveal).
        case reveal
        /// "Mint thẻ" — xác nhận mạng/ví/vị trí/phí, rồi mint (artboards Mint, MintSuccess, MintError).
        case confirm
        case saved
    }

    /// Contract giới hạn tên 64 byte (UTF-8).
    private static let maxNameBytes = 64

    @Environment(GameStore.self) private var game
    @Environment(MapViewModel.self) private var chain
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fuzzLocation") private var fuzzLocation = true
    @State private var model = MintModel()
    @State private var phase: Phase = .checking
    @State private var name = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var located = false
    @State private var place: String?
    @State private var firstHere = false
    @State private var caughtAt = Date()
    @State private var mintedID: UInt64?
    @State private var rewardXP = 0
    @State private var appeared = false
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameIsValid: Bool { !trimmedName.isEmpty && trimmedName.utf8.count <= Self.maxNameBytes }

    /// Toạ độ sẽ lên chain.
    private var chainCoordinate: CLLocationCoordinate2D? {
        coordinate.map { fuzzLocation ? LocationPrivacy.fuzz($0) : $0 }
    }

    private var rarity: Rarity {
        guard let chainCoordinate else { return .common }
        return chain.rarityForNewPet(species: pet.detection.species, at: chainCoordinate)
    }

    private var canMint: Bool {
        chainCoordinate != nil && nameIsValid && !model.stage.isBusy && !model.isDone
    }

    private var photo: Image { Image(uiImage: UIImage(data: pet.thumbnail) ?? UIImage()) }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            if showsRays {
                MintRays(spin: appeared).ignoresSafeArea().transition(.opacity)
            }
            switch phase {
            case .checking:
                VStack(spacing: 14) {
                    ProgressView().tint(.white).controlSize(.large)
                    Text("Xem có phải bé quen không…").font(.vn(15, .semibold)).foregroundStyle(Theme.onDark)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { topBar(title: nil) }
            case .again(let token):
                againView(token)
            case .againConfirmed(let token):
                againDone(token)
            case .reveal:
                revealView
            case .confirm, .saved:
                confirmView
            }
        }
        .foregroundStyle(.white)
        .animation(.spring(duration: 0.45), value: model.stage)
        .presentationBackground(Theme.ink)
        .interactiveDismissDisabled(model.stage.isBusy)
        .task { await start() }
        .onAppear { appeared = true }
    }

    private var showsRays: Bool {
        switch phase {
        case .reveal: true
        case .confirm: model.isDone
        default: false
        }
    }

    // MARK: Gặp lại

    private func againView(_ token: MapToken) -> some View {
        VStack(spacing: 0) {
            topBar(title: nil)
            Spacer(minLength: 12)
            VStack(spacing: 16) {
                Text("BÉ QUEN?")
                    .font(.vn(11, .heavy)).tracking(1.6)
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Theme.gold.opacity(0.14), in: Capsule())
                Text("Giống \(token.name)?").font(.game(34)).multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    photoTile(photo, caption: "Vừa chụp")
                    Image(systemName: "equal")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Theme.teal, in: Circle())
                    OnChainPhoto(token: token, model: chain)
                        .frame(width: 136, height: 136)
                        .clipShape(.rect(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.rarity(chain.rarity(of: token)), lineWidth: 4))
                        .overlay(alignment: .bottom) { caption(token.name) }
                }
                Text("Bạn đã gặp \(token.name) gần đây, cách chưa tới 300 m.")
                    .font(.vn(14)).foregroundStyle(Theme.onDark).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 12)
            bottomSheet {
                VStack(spacing: 10) {
                    Button {
                        game.recordReencounter(tokenID: token.id)
                        onPetMet?()
                        Haptics.notify(.success)
                        withAnimation(.spring(duration: 0.45)) { phase = .againConfirmed(token) }
                    } label: { Text("Đúng bé này · +\(GameRules.reencounterXP) XP").font(.game(19)) }
                        .buttonStyle(ChunkyButtonStyle(fill: Theme.teal, shadow: Theme.tealText))
                    Button { withAnimation { phase = .reveal } } label: { Text("Bé khác, mint mới").font(.game(18)) }
                        .buttonStyle(OutlineButtonStyle())
                }
            }
        }
    }

    /// Thẻ "Gặp lại" (artboard CaptureAgain).
    private func againDone(_ token: MapToken) -> some View {
        let encounters = game.friendship(of: token.id)
        let level = min(encounters, 5)
        let tokenRarity = chain.rarity(of: token)
        return VStack(spacing: 0) {
            topBar(title: nil)
            Spacer(minLength: 12)
            OnChainPhoto(token: token, model: chain)
                .frame(width: 220, height: 220)
                .clipShape(.rect(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Theme.rarity(tokenRarity), lineWidth: 6))
                .shadow(color: .black.opacity(0.35), radius: 20, y: 16)
            Spacer(minLength: 12)
            bottomSheet {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        OnChainPhoto(token: token, model: chain)
                            .frame(width: 60, height: 60)
                            .clipShape(.rect(cornerRadius: 14))
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Theme.rarity(tokenRarity)).frame(height: 4)
                            }
                            .clipShape(.rect(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("GẶP LẠI").font(.vn(11, .heavy)).tracking(1.2).foregroundStyle(Theme.tealText)
                            Text(token.name).font(.game(26)).lineLimit(1).minimumScaleFactor(0.7)
                            HStack(spacing: 6) {
                                smallChip("Lần \(encounters)", foreground: Theme.ink, background: Theme.line)
                                smallChip(tokenRarity.title, foreground: Theme.rarityText(tokenRarity),
                                          background: Theme.rarity(tokenRarity).opacity(0.14))
                            }
                        }
                        Spacer(minLength: 0)
                        smallChip("+\(GameRules.reencounterXP) XP", foreground: Theme.purpleText, background: Theme.purpleSoft)
                    }
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "heart.fill").foregroundStyle(Theme.orange)
                            Text("Thân thiết").font(.vn(14, .bold))
                            Spacer()
                            Text("Lv \(level)").font(.game(16)).foregroundStyle(Theme.orangeText)
                            Text("+1").font(.game(16)).foregroundStyle(Theme.tealText)
                        }
                        HStack(spacing: 4) {
                            ForEach(0..<5, id: \.self) { index in
                                Capsule()
                                    .fill(index < level ? Theme.orange : Theme.line)
                                    .frame(height: 8)
                            }
                        }
                    }
                    .padding(14)
                    .background(Theme.paper, in: .rect(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
                    Button { dismiss() } label: { Text("Chạy tiếp").font(.game(19)) }
                        .buttonStyle(ChunkyButtonStyle())
                }
            }
        }
    }

    // MARK: Bé mới (Reveal)

    private var revealView: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    closeButton
                    Spacer()
                }
                .padding(.bottom, -18)
                if let place {
                    Text(firstHere ? "LẦN ĐẦU Ở \(place.uppercased())" : place.uppercased())
                        .font(.vn(11, .heavy)).tracking(1.6)
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Theme.gold.opacity(0.14), in: Capsule())
                        .lineLimit(1)
                }
                Text("Bé mới!").font(.game(38))
                    .scaleEffect(appeared ? 1 : 0.6)
                    .animation(.spring(duration: 0.6, bounce: 0.5), value: appeared)
                revealCard
                    .rotation3DEffect(.degrees(appeared ? 0 : 60), axis: (x: 0, y: 1, z: 0))
                    .animation(.spring(duration: 0.7, bounce: 0.35), value: appeared)
                Text("+\(GameRules.newPetXP + GameRules.rarityBonusXP(rarity)) XP")
                    .font(.game(16))
                    .foregroundStyle(Color(hex: 0xE9D8FF))
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .background(Theme.purple.opacity(0.35), in: Capsule())
                Button {
                    nameFocused = false
                    withAnimation(.spring(duration: 0.45)) { phase = .confirm }
                } label: {
                    Label("Mint NFT", systemImage: "sparkle").font(.game(22))
                }
                .buttonStyle(ChunkyButtonStyle(height: 60))
                .disabled(!nameIsValid)
                .opacity(nameIsValid ? 1 : 0.55)
                .padding(.top, 4)
                .accessibilityIdentifier("mintNext")
                Button {
                    if canMint { saveForLater() } else { dismiss() }
                } label: {
                    Text("Để sau").font(.vn(15, .semibold)).underline()
                }
                .foregroundStyle(.white)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    private var revealCard: some View {
        let tint = Theme.rarity(rarity)
        return VStack(spacing: 0) {
            HStack {
                rarityLabel(foreground: .white)
                Spacer()
                Image(systemName: pet.detection.species.symbolName).font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(tint)
            photo.resizable().scaledToFill()
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityLabel("Ảnh bé vừa bắt")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Đặt tên cho bé", text: $name)
                            .font(.game(26))
                            .foregroundStyle(Theme.ink)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .accessibilityLabel("Tên bé")
                        Text("\(pet.detection.species.displayName) · \(pet.detection.confidencePercent)%")
                            .font(.vn(13)).foregroundStyle(Theme.ink2)
                    }
                    Button { nameFocused = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 2))
                    }
                    .accessibilityLabel("Sửa tên")
                }
                if trimmedName.utf8.count > Self.maxNameBytes {
                    Text("Tên dài quá, tối đa \(Self.maxNameBytes) byte.").font(.vn(12, .semibold)).foregroundStyle(Theme.orangeText)
                }
                HStack(spacing: 14) {
                    Label(placeText, systemImage: "mappin")
                    Label(Self.timeFormat.string(from: caughtAt), systemImage: "clock")
                }
                .font(.vn(12))
                .foregroundStyle(Theme.ink2)
                .labelStyle(TightLabelStyle())
                .lineLimit(1)
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
            .background(.white)
        }
        .frame(width: 300)
        .clipShape(.rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(tint, lineWidth: 6).padding(-6))
        .padding(12)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 32))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 20)
    }

    /// "06:12 · 11/11" như thẻ trong design.
    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm · dd/MM"
        return formatter
    }()

    /// "Tao Đàn ±100 m" — nơi bắt + độ mờ vị trí.
    private var placeText: String {
        guard coordinate != nil else { return located ? "Không lấy được vị trí" : "Đang lấy vị trí…" }
        let suffix = fuzzLocation ? " ±100 m" : ""
        return (place ?? "Vị trí hiện tại") + suffix
    }

    private var locationText: String {
        if coordinate == nil { return located ? "Không lấy được" : "Đang lấy…" }
        return fuzzLocation ? "Làm mờ ±100 m" : "Chính xác"
    }

    // MARK: Mint thẻ

    private var confirmView: some View {
        VStack(spacing: 0) {
            topBar(title: "Mint thẻ")
            Spacer(minLength: 8)
            mintCard
                .opacity(isFailed ? 0.45 : 1)
                .scaleEffect(model.isDone ? 1.06 : 1)
            Spacer(minLength: 8)
            bottomSheet { sheetContent }
        }
    }

    private var isFailed: Bool { if case .failed = model.stage { true } else { false } }

    private var mintCard: some View {
        let tint = Theme.rarity(rarity)
        return VStack(alignment: .leading, spacing: 0) {
            photo.resizable().scaledToFill()
                .frame(width: 198, height: 196)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
            VStack(alignment: .leading, spacing: 3) {
                Text(trimmedName.isEmpty ? pet.detection.species.displayName : trimmedName)
                    .font(.game(22)).lineLimit(1).minimumScaleFactor(0.6)
                rarityLabel(foreground: .white).font(.vn(11, .heavy))
            }
            .foregroundStyle(.white)
            .padding(EdgeInsets(top: 9, leading: 10, bottom: 11, trailing: 10))
        }
        .frame(width: 198)
        .background(tint)
        .clipShape(.rect(cornerRadius: 18))
        .padding(6)
        .background(tint, in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 16)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var sheetContent: some View {
        if case .saved = phase {
            VStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.tealText)
                    .frame(width: 60, height: 60)
                    .background(Theme.tealSoft, in: Circle())
                Text("Đã lưu!").font(.game(26))
                Text("Có mạng thì mint trong Hồ sơ › Bé chờ mint.")
                    .font(.vn(14)).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
                Button { dismiss() } label: { Text("Xong").font(.game(19)) }
                    .buttonStyle(ChunkyButtonStyle())
            }
            .frame(maxWidth: .infinity)
        } else {
            switch model.stage {
            case .idle:
                VStack(spacing: 0) {
                    infoRow("Mạng", "Avalanche Fuji")
                    infoRow("Ví", account.address.short)
                    infoRow("Ảnh", "Ảnh thật")
                    infoRow("Vị trí", locationText)
                    infoRow("Phí", "Miễn phí", valueColor: Theme.tealText, divider: false)
                    if chain.isOffline {
                        Button { saveForLater() } label: { Text("Lưu, mint khi có mạng").font(.game(20)) }
                            .buttonStyle(ChunkyButtonStyle(fill: Theme.ink, shadow: .black, height: 60))
                            .disabled(!canMint)
                            .padding(.top, 12)
                    } else {
                        Button { Task { await mint() } } label: {
                            Label("Mint", systemImage: "sparkle").font(.game(22))
                        }
                        .buttonStyle(ChunkyButtonStyle(height: 60))
                        .disabled(!canMint)
                        .opacity(canMint ? 1 : 0.55)
                        .padding(.top, 12)
                        .accessibilityLabel("Mint")
                        .accessibilityIdentifier("mintButton")
                    }
                }
            case .preparing, .sponsoring, .sending, .confirming:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Đang mint…").font(.game(26)).padding(.bottom, 4)
                    steps
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .done(let hash):
                doneContent(hash)
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.orangeText)
                        .frame(width: 60, height: 60)
                        .background(Theme.orangeSoft, in: Circle())
                    Text("Chưa mint được").font(.game(26))
                    Text(message)
                        .font(.vn(13, .bold))
                        .foregroundStyle(Theme.orangeText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Theme.orangeSoft, in: .rect(cornerRadius: 14))
                    HStack(spacing: 10) {
                        Button { saveForLater() } label: { Text("Lưu, mint sau").font(.game(16)) }
                            .buttonStyle(OutlineButtonStyle())
                        Button { Task { await mint() } } label: { Text("Thử lại").font(.game(18)) }
                            .buttonStyle(ChunkyButtonStyle())
                    }
                    Button { dismiss() } label: { Text("Để sau").font(.vn(15, .semibold)).underline() }
                        .foregroundStyle(Theme.ink2)
                        .frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func doneContent(_ hash: String) -> some View {
        let url = Config.explorerURL.appending(path: "tx/\(hash)")
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Đã mint!").font(.game(32))
                Spacer()
                if let mintedID {
                    Text("NFT #\(mintedID)")
                        .font(.game(15)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Theme.ink, in: Capsule())
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Giao dịch").font(.vn(11)).foregroundStyle(Theme.ink2)
                    Text("\(hash.prefix(6))…\(hash.suffix(4))").font(.vn(14, .bold)).monospaced()
                }
                Spacer()
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .background(.white, in: .rect(cornerRadius: 12))
                }
                .accessibilityLabel("Xem giao dịch trên Snowtrace")
            }
            .padding(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 6))
            .background(Theme.paper, in: .rect(cornerRadius: 16))
            smallChip("+\(rewardXP) XP", foreground: Theme.purpleText, background: Theme.purpleSoft)
            HStack(spacing: 10) {
                ShareLink(item: url, message: Text("Mình vừa mint bé \(trimmedName) trên PawRun!")) {
                    Label("Chia sẻ", systemImage: "square.and.arrow.up").font(.game(18))
                }
                .buttonStyle(OutlineButtonStyle())
                Button { dismiss() } label: { Text("Xong").font(.game(18)) }
                    .buttonStyle(ChunkyButtonStyle())
            }
        }
    }

    private var steps: some View {
        ForEach(Array(["Chuẩn bị giao dịch", "Xin tài trợ phí", "Ký và gửi", "Xác nhận trên chuỗi"].enumerated()),
                id: \.offset) { index, title in
            HStack(spacing: 12) {
                Group {
                    if index < model.stage.step {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Theme.teal, in: Circle())
                    } else if index == model.stage.step {
                        ProgressView().tint(Theme.orange).frame(width: 28, height: 28)
                    } else {
                        Circle().strokeBorder(Color(hex: 0xD9D3EA), lineWidth: 3).frame(width: 28, height: 28)
                    }
                }
                Text(title)
                    .font(.vn(15, .bold))
                    .foregroundStyle(index <= model.stage.step ? Theme.ink : Theme.ink2)
            }
            .frame(height: 48)
        }
    }

    // MARK: Mảnh dùng chung

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.12), in: Circle())
        }
        .disabled(model.stage.isBusy)
        .accessibilityLabel("Đóng")
    }

    private func topBar(title: String?) -> some View {
        HStack {
            closeButton
            Spacer()
            if let title { Text(title).font(.game(20)) }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(Color(hex: 0x5EEAD4)).frame(width: 8, height: 8)
                Text("Fuji").font(.vn(12, .bold))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(.white.opacity(0.12), in: Capsule())
            .accessibilityLabel("Mạng Avalanche Fuji")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func bottomSheet<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(Theme.ink)
            .padding(EdgeInsets(top: 22, leading: 20, bottom: 12, trailing: 20))
            .frame(maxWidth: .infinity)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                    .fill(.white)
                    .ignoresSafeArea(edges: .bottom)
            }
            .environment(\.colorScheme, .light)
    }

    private func rarityLabel(foreground: Color) -> some View {
        HStack(spacing: 6) {
            Text(rarity.title.uppercased()).tracking(1)
            Text(String(repeating: "★", count: rarity.stars)).tracking(1)
        }
        .font(.game(14))
        .foregroundStyle(foreground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Độ hiếm \(rarity.title.lowercased())")
    }

    private func smallChip(_ text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(.game(14))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(background, in: Capsule())
    }

    private func photoTile(_ image: Image, caption text: String) -> some View {
        image.resizable().scaledToFill()
            .frame(width: 136, height: 136)
            .clipShape(.rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white, lineWidth: 4))
            .overlay(alignment: .bottom) { caption(text) }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.vn(11, .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.ink.opacity(0.75), in: Capsule())
            .padding(6)
    }

    private func infoRow(_ title: String, _ value: String, valueColor: Color = Theme.ink, divider: Bool = true) -> some View {
        HStack {
            Text(title).font(.vn(13)).foregroundStyle(Theme.ink2)
            Spacer()
            Text(value).font(.vn(15, .bold)).foregroundStyle(valueColor)
        }
        .frame(height: 46)
        .overlay(alignment: .bottom) {
            if divider { Rectangle().fill(Color(hex: 0xF0ECF8)).frame(height: 1) }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Hành động

    private func start() async {
        coordinate = await LocationOnce.current()
        located = true
        if let coordinate {
            firstHere = !chain.tokens(ownedBy: account.address).contains { $0.coordinate.distance(to: coordinate) < 1_000 }
            Task { place = await RouteService.placeName(coordinate) }
        }
        guard let coordinate, let match = await findKnownPet(near: coordinate) else {
            withAnimation(.spring(duration: 0.45)) { phase = .reveal }
            return
        }
        phase = .again(match)
    }

    /// Bé cùng loài của mình trong 300 m có ảnh giống ảnh vừa chụp.
    private func findKnownPet(near coordinate: CLLocationCoordinate2D) async -> MapToken? {
        let nearby = chain.tokens(ownedBy: account.address).filter {
            $0.species == pet.detection.species && $0.coordinate.distance(to: coordinate) < 300
        }
        var candidates: [(id: UInt64, photo: Data)] = []
        for token in nearby.suffix(12) {
            if let photo = try? await chain.photo(id: token.id) { candidates.append((token.id, photo)) }
        }
        guard !candidates.isEmpty else { return nil }
        let thumbnail = pet.thumbnail
        let match = await Task.detached(priority: .userInitiated) {
            PetMatcher.bestMatch(for: thumbnail, among: candidates)
        }.value
        return match.flatMap { match in nearby.first { $0.id == match.id } }
    }

    private func mint() async {
        guard let chainCoordinate, let nft = try? Config.address(Config.contractAddress, name: "contractAddress") else { return }
        let rarity = rarity
        let data = MapNFTCall.mint(latitude: chainCoordinate.latitude, longitude: chainCoordinate.longitude,
                                   detection: pet.detection, name: trimmedName, photo: pet.thumbnail)
        guard await model.send(target: nft, data: data, account: account) else { return }
        await chain.refresh()
        mintedID = chain.tokens(ownedBy: account.address).last?.id
        rewardXP = GameRules.newPetXP + GameRules.rarityBonusXP(rarity)
        game.recordNewPet(tokenID: mintedID, rarity: rarity)
        onPetMet?()
        Haptics.notify(.success)
    }

    private func saveForLater() {
        guard let chainCoordinate else { return }
        game.enqueue(PendingMint(name: trimmedName, species: pet.detection.species.rawValue,
                                 confidence: pet.detection.confidencePercent,
                                 latitude: chainCoordinate.latitude, longitude: chainCoordinate.longitude,
                                 photo: pet.thumbnail))
        game.recordNewPet(tokenID: nil, rarity: rarity)
        onPetMet?()
        withAnimation(.spring(duration: 0.45)) { phase = .saved }
    }
}

/// Nhãn icon + chữ sát nhau (dòng nơi bắt / giờ trên thẻ).
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

/// Tia nắng vàng sau thẻ (màn Bé mới!, Đã mint!).
private struct MintRays: View {
    let spin: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height) * 1.4
            Canvas { context, size in
                let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                for (r, alpha) in [(side * 0.2, 0.07), (side * 0.13, 0.08)] {
                    context.fill(Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2)),
                                 with: .color(Theme.gold.opacity(alpha)))
                }
                var rays = Path()
                let length = side / 2
                for k in 0..<12 {
                    var wedge = Path()
                    wedge.move(to: .zero)
                    wedge.addLine(to: CGPoint(x: -length * 0.075, y: -length))
                    wedge.addLine(to: CGPoint(x: length * 0.075, y: -length))
                    wedge.closeSubpath()
                    rays.addPath(wedge.applying(CGAffineTransform(translationX: mid.x, y: mid.y).rotated(by: Double(k) * .pi / 6)))
                }
                context.fill(rays, with: .color(Theme.gold.opacity(0.09)))
            }
            .frame(width: side, height: side)
            .rotationEffect(.degrees(spin ? 30 : 0))
            .animation(.linear(duration: 16).repeatForever(autoreverses: false), value: spin)
            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.36)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Bé đã lưu lúc mất mạng: mint lần lượt khi có mạng.
struct PendingMintsView: View {
    let account: SmartAccount

    @Environment(GameStore.self) private var game
    @Environment(MapViewModel.self) private var chain
    @State private var model = MintModel()
    @State private var current: UUID?

    var body: some View {
        List {
            if game.progress.pendingMints.isEmpty {
                ContentUnavailableView("Không có bé chờ mint", systemImage: "tray")
            }
            ForEach(game.progress.pendingMints) { pending in
                HStack(spacing: 12) {
                    Image(uiImage: UIImage(data: pending.photo) ?? UIImage())
                        .resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pending.name).font(.game(18))
                        Text(pending.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.vn(12)).foregroundStyle(Theme.ink2)
                    }
                    Spacer()
                    if current == pending.id, model.stage.isBusy {
                        ProgressView()
                    } else {
                        Button { Task { await mint(pending) } } label: {
                            Text("Mint")
                                .font(.game(16))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .frame(height: 40)
                                .background(Theme.orange, in: Capsule())
                                .background(Theme.orangeDeep, in: Capsule().offset(y: 3))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.stage.isBusy)
                        .opacity(model.stage.isBusy ? 0.5 : 1)
                    }
                }
            }
            if case .failed(let message) = model.stage {
                Text(message).font(.vn(13)).foregroundStyle(Theme.orangeText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .navigationTitle("Bé chờ mint")
    }

    private func mint(_ pending: PendingMint) async {
        guard let nft = try? Config.address(Config.contractAddress, name: "contractAddress") else { return }
        current = pending.id
        let data = MapNFTCall.mint(latitude: pending.latitude, longitude: pending.longitude, species: pending.species,
                                   confidence: pending.confidence, name: pending.name, photo: pending.photo)
        if await model.send(target: nft, data: data, account: account) {
            game.removePending(pending.id)
            await chain.refresh()
        }
        current = nil
    }
}
