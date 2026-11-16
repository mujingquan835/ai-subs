import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let accounts: [AccountQuota]
    var style: WidgetBackground = .white
}

struct QuotaProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: Date(), accounts: Self.sample) }

    func snapshot(for configuration: StyleIntent, in context: Context) async -> QuotaEntry {
        let accounts = QuotaFile.load()
        return QuotaEntry(date: Date(), accounts: context.isPreview && accounts.isEmpty ? Self.sample : accounts, style: configuration.background)
    }

    func timeline(for configuration: StyleIntent, in context: Context) async -> Timeline<QuotaEntry> {
        // 数据由 App 每 5 分钟写入并触发刷新；这里每 15 分钟重排一次，让“X 小时后重置”和过期清零跟着走
        let accounts = QuotaFile.load()
        let now = Date()
        let entries = (0..<8).map { QuotaEntry(date: now.addingTimeInterval(Double($0) * 900), accounts: accounts, style: configuration.background) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// 仅用于小组件库预览
    static let sample: [AccountQuota] = [
        AccountQuota(id: "chatgpt", name: "ChatGPT Plus", windows: [
            QuotaWindow(label: "5 小时", usedPercent: 42, resetsAt: Date().addingTimeInterval(9000), spanSeconds: 18000),
            QuotaWindow(label: "本周", usedPercent: 63, resetsAt: Date().addingTimeInterval(300000), spanSeconds: 604800)], fetchedAt: Date()),
        AccountQuota(id: "claude", name: "Claude Pro", windows: [
            QuotaWindow(label: "5 小时", usedPercent: 86, resetsAt: Date().addingTimeInterval(4000), spanSeconds: 18000),
            QuotaWindow(label: "本周", usedPercent: 30, resetsAt: Date().addingTimeInterval(400000), spanSeconds: 604800)], fetchedAt: Date()),
    ]
}

struct QuotaWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QuotaWidget", intent: StyleIntent.self, provider: QuotaProvider()) { entry in
            QuotaWidgetView(entry: entry).widgetBackground(entry.style)
        }
        .configurationDisplayName("AI 额度")
        .description("Codex、Claude Code 的 5 小时与每周额度。需在 App 里开启自动识别。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuotaWidgetView: View {
    let entry: QuotaEntry
    @Environment(\.widgetFamily) private var family

    private var accounts: [AccountQuota] { entry.accounts.filter { !$0.windows.isEmpty } }

    var body: some View {
        if accounts.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.title2).foregroundStyle(.secondary)
                Text("暂无额度数据").font(.system(size: 13, weight: .semibold))
                Text("在 App 中开启自动识别").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if family == .systemSmall {
            SmallQuota(account: accounts[0], now: entry.date)
        } else {
            MediumQuota(accounts: accounts, now: entry.date)
        }
    }
}

/// 中号：一个账号时大圆环＋图例；两个账号时左右并排
struct MediumQuota: View {
    let accounts: [AccountQuota]
    let now: Date
    var body: some View {
        if accounts.count == 1 {
            HStack(spacing: 16) {
                QuotaRings(account: accounts[0], now: now, size: 104)
                VStack(alignment: .leading, spacing: 10) {
                    Text(accounts[0].name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    ForEach(Array(accounts[0].windows.enumerated()), id: \.offset) { i, w in QuotaLegendRow(window: w, index: i, now: now) }
                    Spacer(minLength: 0)
                    UpdatedText(account: accounts[0])
                }
            }
        } else {
            HStack(spacing: 12) {
                ForEach(Array(accounts.prefix(2).enumerated()), id: \.offset) { n, a in
                    if n > 0 { Rectangle().fill(.primary.opacity(0.1)).frame(width: 1) }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            QuotaRings(account: a, now: now, size: 58)
                            Text(a.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        }
                        ForEach(Array(a.windows.enumerated()), id: \.offset) { i, w in QuotaLegendRow(window: w, index: i, now: now, compact: true) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// 小号：上方大圆环，下方两行百分比
struct SmallQuota: View {
    let account: AccountQuota
    let now: Date
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                QuotaRings(account: account, now: now, size: 56)
                Text(account.name).font(.system(size: 12, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            ForEach(Array(account.windows.prefix(2).enumerated()), id: \.offset) { i, w in QuotaLegendRow(window: w, index: i, now: now, compact: true) }
        }
    }
}

struct UpdatedText: View {
    let account: AccountQuota
    var body: some View {
        Text("更新于 \(account.fetchedAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN"))))")
            .font(.system(size: 9)).foregroundStyle(.tertiary)
    }
}
