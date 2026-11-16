import CoreLocation
import SwiftUI

private let muted = Color(hex: 0x6E6A8E)

/// Nhiệm vụ trong ngày + rương (artboard "Nhiệm vụ"), và tab thử thách (artboard "Thử thách": chuỗi ngày,
/// huy chương, bảng xếp hạng khu).
struct QuestsView: View {
    let account: SmartAccount

    private enum Tab: String, CaseIterable {
        case today = "Hôm nay"
        case challenges = "Thử thách"
    }

    @Environment(GameStore.self) private var game
    @Environment(MapViewModel.self) private var chain
    @State private var tab: Tab = .today

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                segments
                switch tab {
                case .today: today
                case .challenges: ChallengesSection(account: account)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await game.refreshSteps() }
    }

    // MARK: Đầu trang

    private var header: some View {
        HStack {
            Text(tab == .today ? "Nhiệm vụ" : "Thử thách")
                .font(.game(32))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            switch tab {
            case .today:
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let left = Self.untilMidnight(from: context.date)
                    HStack(spacing: 5) {
                        Image(systemName: "clock").font(.system(size: 13, weight: .bold))
                        Text(String(format: "%02d:%02d", left / 3600, left % 3600 / 60)).monospacedDigit()
                    }
                    .font(.game(14, .bold))
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white, in: Capsule())
                    .shadow(color: Theme.ink.opacity(0.06), radius: 6, y: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Làm mới sau \(left / 3600) giờ \(left % 3600 / 60) phút")
                }
            case .challenges:
                if let rank = myRank(game: game, chain: chain, account: account) {
                    HStack(spacing: 5) {
                        Image(systemName: "trophy").font(.system(size: 13, weight: .bold))
                        Text("#\(rank)")
                    }
                    .font(.game(14))
                    .foregroundStyle(Theme.orangeText)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white, in: Capsule())
                    .shadow(color: Theme.ink.opacity(0.06), radius: 6, y: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Hạng \(rank) trong khu")
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 40)
    }

    private static func untilMidnight(from date: Date) -> Int {
        let calendar = Calendar.current
        let next = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: date)!)
        return max(0, Int(next.timeIntervalSince(date)))
    }

    private var segments: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    withAnimation(.snappy) { tab = item }
                } label: {
                    Text(item.rawValue)
                        .font(.game(16))
                        .foregroundStyle(tab == item ? .white : Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(tab == item ? Theme.ink : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.line, in: Capsule())
    }

    // MARK: Hôm nay

    private var today: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepsCard
            ForEach(DailyQuest.allCases) { quest in questRow(quest) }
            chestCard
        }
    }

    private var stepsCard: some View {
        let goal = DailyQuest.steps.goal
        let fraction = min(Double(game.stepsToday) / Double(goal), 1)
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.14), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "shoeprints.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFFB27A))
            }
            .padding(5)
            .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(GameRules.number(game.stepsToday)).font(.game(42)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("/ \(GameRules.number(goal)) bước").font(.vn(12)).foregroundStyle(Theme.onDark)
                        .lineLimit(1).fixedSize()
                }
                HStack(spacing: 8) {
                    Text(GameRules.metersText(game.progress.dayMeters))
                        .font(.game(15))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.10), in: Capsule())
                    HStack(spacing: 4) {
                        FlameGlyph().frame(width: 15, height: 17)
                        Text("\(game.streak)")
                    }
                    .font(.game(15))
                    .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 12))
                    .background(.white.opacity(0.10), in: Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Chuỗi \(game.streak) ngày")
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(Theme.ink, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bước hôm nay \(GameRules.number(game.stepsToday)) trên \(GameRules.number(goal))")
    }

    private func questStyle(_ quest: DailyQuest) -> (tint: Color, soft: Color, text: Color) {
        switch quest {
        case .steps: (Theme.orange, Theme.orangeSoft, Theme.orangeText)
        case .run: (Theme.orange, Theme.orangeSoft, Theme.orangeText)
        case .meetPets: (Theme.blue, Theme.blueSoft, Color(hex: 0x2563D9))
        case .visitStation: (Theme.teal, Theme.tealSoft, Theme.tealText)
        }
    }

    private func questRow(_ quest: DailyQuest) -> some View {
        let progress = game.questProgress(quest)
        let done = game.isQuestDone(quest)
        let claimed = game.isQuestClaimed(quest)
        let claimable = done && !claimed
        let style = questStyle(quest)
        return HStack(spacing: 12) {
            questIcon(quest)
                .foregroundStyle(claimable ? Theme.ink : style.text)
                .frame(width: 42, height: 42)
                .background(claimable ? Theme.gold : style.soft, in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(quest.title).font(.vn(14, .bold))
                    Spacer()
                    Text(quest.goal >= 1_000 ? GameRules.number(progress)
                                             : "\(min(progress, quest.goal))/\(quest.goal)")
                        .font(.vn(12, .semibold)).foregroundStyle(muted).monospacedDigit()
                }
                ProgressBar(value: Double(progress) / Double(quest.goal),
                            tint: claimable ? Color(hex: 0xF0A818) : style.tint, height: 8)
                    .frame(height: 8)
            }
            if claimed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .black))
                    Text("+\(quest.rewardXP) XP")
                }
                .font(.game(14)).foregroundStyle(Theme.tealText)
                .padding(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 10))
                .background(Theme.tealSoft, in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Đã nhận \(quest.rewardXP) XP")
            } else if claimable {
                Button("Nhận") {
                    game.claimQuest(quest)
                    Haptics.notify(.success)
                }
                .font(.game(16))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Theme.gold, in: .rect(cornerRadius: 14))
                .background(Theme.goldDeep, in: .rect(cornerRadius: 14).offset(y: 4))
                .padding(.bottom, 4)
                .buttonStyle(.plain)
            } else {
                Text("+\(quest.rewardXP) XP")
                    .font(.game(14)).foregroundStyle(Theme.purpleText)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Theme.purpleSoft, in: Capsule())
            }
        }
        .padding(EdgeInsets(top: claimable ? 8 : 10, leading: claimable ? 10 : 12,
                            bottom: claimable ? 8 : 10, trailing: claimable ? 10 : 12))
        .background(.white, in: .rect(cornerRadius: 20))
        .overlay {
            if claimable { RoundedRectangle(cornerRadius: 20).strokeBorder(Color(hex: 0xF5B82E), lineWidth: 2) }
        }
        .shadow(color: Theme.ink.opacity(0.06), radius: 6, y: 3)
    }

    @ViewBuilder
    private func questIcon(_ quest: DailyQuest) -> some View {
        if quest == .meetPets {
            PawGlyph().fill(.foreground).frame(width: 22, height: 22)
        } else {
            Image(systemName: quest.symbol).font(.system(size: 19, weight: .bold))
        }
    }

    private var chestCard: some View {
        let total = DailyQuest.allCases.count
        let opened = game.progress.chestOpened
        return Button { game.openChest() } label: {
            HStack(spacing: 12) {
                Image(systemName: opened ? "shippingbox.and.arrow.backward" : "shippingbox")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 42, height: 42)
                    .background(Theme.gold, in: .rect(cornerRadius: 14))
                Text("Rương ngày").font(.game(17))
                Spacer(minLength: 4)
                if opened {
                    Text("Đã mở · mai quay lại").font(.vn(12, .semibold)).foregroundStyle(Theme.goldText)
                } else {
                    HStack(spacing: 5) {
                        ForEach(0..<total, id: \.self) { index in
                            Capsule()
                                .fill(index < game.claimedCount ? Theme.ink : Theme.ink.opacity(0.16))
                                .frame(width: 22, height: 10)
                        }
                    }
                    if game.canOpenChest {
                        Text("Mở")
                            .font(.game(15)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(Theme.ink, in: Capsule())
                    } else {
                        Text("\(game.claimedCount)/\(total)").font(.game(15)).foregroundStyle(Theme.goldText)
                    }
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 14))
            .background(Theme.goldSoft, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(game.canOpenChest)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(opened ? "Rương ngày, đã mở"
                                   : "Rương ngày, xong \(game.claimedCount) trên \(total) nhiệm vụ")
        .accessibilityHint(game.canOpenChest ? "Mở rương" : "")
    }
}

/// Hạng của mình ở khu ~1 km của vòng chạy gần nhất (nil nếu chưa mint vòng nào ở đó).
@MainActor
private func myRank(game: GameStore, chain: MapViewModel, account: SmartAccount) -> Int? {
    guard let area = game.progress.runs.last(where: { $0.area != nil })?.area else { return nil }
    return chain.leaderboard(area: area).firstIndex { $0.owner == account.address }.map { $0 + 1 }
}

// MARK: - Thử thách

struct ChallengesSection: View {
    let account: SmartAccount

    @Environment(GameStore.self) private var game
    @Environment(MapViewModel.self) private var chain
    @State private var areaName: String?

    /// Khu ~1 km của vòng chạy gần nhất có hình.
    private var myArea: RunArea? { game.progress.runs.last(where: { $0.area != nil })?.area }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            weekStrip
            Text("Chạy từ 1.000 m mỗi ngày để giữ chuỗi.")
                .font(.vn(12)).foregroundStyle(muted)
                .padding(.horizontal, 4)

            HStack(spacing: 10) {
                ForEach(Medal.allCases) { medal in medalTile(medal) }
            }
            .fixedSize(horizontal: false, vertical: true)

            leaderboard
        }
        .task(id: myArea) {
            guard let myArea else { return }
            let center = CLLocationCoordinate2DMake(Double(myArea.lat) / 100, Double(myArea.lng) / 100)
            areaName = await RouteService.placeName(center)
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                FlameGlyph().frame(width: 30, height: 34)
                Text("\(game.streak)").font(.game(30)).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Chuỗi \(game.streak) ngày")
            HStack(spacing: 4) {
                ForEach(Array(game.week.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 4) {
                        ZStack {
                            if day.done {
                                Circle().fill(Theme.orange)
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                            } else if day.isToday {
                                Circle().strokeBorder(Theme.orange, lineWidth: 3)
                            } else {
                                Circle().fill(.white.opacity(0.12))
                            }
                        }
                        .frame(width: 24, height: 24)
                        Text(day.label)
                            .font(.vn(10, day.isToday ? .bold : .regular))
                            .foregroundStyle(day.isToday ? .white : Theme.onDark)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.label), \(day.done ? "đã chạy" : "chưa chạy")")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .background(Theme.ink, in: .rect(cornerRadius: 22))
    }

    private func medalTile(_ medal: Medal) -> some View {
        let unlocked = game.progress.medals[medal] != nil
        let (soft, text): (Color, Color) = switch medal {
        case .sprint: (Theme.orangeSoft, Theme.orangeText)
        case .hold: (Theme.tealSoft, Theme.tealText)
        case .tenK: (Theme.purpleSoft, Theme.purpleText)
        }
        return VStack(spacing: 5) {
            Image(systemName: medal.symbol)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(unlocked ? text : Theme.ink2.opacity(0.45))
                .frame(width: 42, height: 42)
                .background(unlocked ? soft : Theme.line, in: Circle())
            Text(medal.title).font(.game(16))
            Text(medal.detail).font(.vn(11)).foregroundStyle(muted).multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
            if unlocked {
                Circle().fill(Color(hex: 0xF5B82E)).frame(width: 14, height: 14).padding(.top, 2)
            } else {
                Circle().strokeBorder(Color(hex: 0xD9D3EA), lineWidth: 2).frame(width: 14, height: 14).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(EdgeInsets(top: 12, leading: 6, bottom: 12, trailing: 6))
        .background(.white, in: .rect(cornerRadius: 18))
        .shadow(color: Theme.ink.opacity(0.06), radius: 6, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityValue(unlocked ? "Đã có" : "Chưa có")
    }

    @ViewBuilder
    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(areaName ?? "Bảng xếp hạng khu").font(.game(16))
                Spacer()
                if let myArea {
                    let count = chain.leaderboard(area: myArea).count
                    if count > 0 { Text("\(count) người chạy").font(.vn(12)).foregroundStyle(muted) }
                }
            }
            if let myArea {
                let rows = chain.leaderboard(area: myArea)
                if rows.isEmpty {
                    Text("Chưa ai mint vòng chạy ở khu này. Mint vòng đầu tiên để lên bảng!")
                        .font(.vn(14)).foregroundStyle(Theme.ink2)
                } else {
                    // Top 10, thêm dòng của mình nếu mình ở ngoài top.
                    let mine = rows.firstIndex { $0.owner == account.address }
                    let shown = Array(0..<min(10, rows.count)) + (mine.flatMap { $0 >= 10 ? [$0] : nil } ?? [])
                    ForEach(shown, id: \.self) { index in
                        leaderRow(rank: index + 1, owner: rows[index].owner, meters: rows[index].meters,
                                  isMe: rows[index].owner == account.address)
                    }
                }
            } else {
                Text("Chạy và mint một vòng để xem bảng xếp hạng khu của bạn.")
                    .font(.vn(14)).foregroundStyle(Theme.ink2)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .background(.white, in: .rect(cornerRadius: 20))
        .shadow(color: Theme.ink.opacity(0.06), radius: 6, y: 3)
    }

    private func leaderRow(rank: Int, owner: Address, meters: Int, isMe: Bool) -> some View {
        let rankColor: Color = isMe ? Theme.orangeText
            : rank == 1 ? Color(hex: 0x946200) : rank == 2 ? Color(hex: 0x5F667A) : Theme.ink2
        let avatar: Color = isMe ? Color(hex: 0xFFD9BF)
            : [Color(hex: 0xFFE08A), Color(hex: 0xC2DAFF), Color(hex: 0xD7F0C2), Color(hex: 0xEADCFB)][rank % 4]
        let initials = String(owner.hex.dropFirst(2).prefix(2)).uppercased()
        return HStack(spacing: 10) {
            Text("\(rank)").font(.game(16)).foregroundStyle(rankColor).frame(width: 22, alignment: .leading)
            Text(initials)
                .font(.vn(11, .heavy))
                .foregroundStyle(isMe ? Theme.orangeText : Theme.ink)
                .frame(width: 30, height: 30)
                .background(avatar, in: Circle())
            Text(isMe ? "Bạn" : owner.short)
                .font(.vn(14, isMe ? .bold : .semibold))
                .lineLimit(1)
            Spacer()
            Text(GameRules.metersText(Double(meters))).font(.game(15)).monospacedDigit()
        }
        .frame(height: isMe ? 38 : 36)
        .padding(.horizontal, isMe ? 8 : 0)
        .background(isMe ? Theme.orangeSoft : .clear, in: .rect(cornerRadius: 12))
        .padding(.horizontal, isMe ? -8 : 0)
        .accessibilityElement(children: .combine)
    }
}
