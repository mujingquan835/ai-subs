import SwiftUI
import WidgetKit

// MARK: - 时间线

struct UpcomingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UpcomingEntry { UpcomingEntry(date: Date(), items: Self.sample) }

    func snapshot(for configuration: StyleIntent, in context: Context) async -> UpcomingEntry {
        var entry = load(at: Date())
        // 小组件库预览时如果还没有数据，用示例展示样式
        if context.isPreview && entry.items.isEmpty { entry = placeholder(in: context) }
        entry.style = configuration.background
        return entry
    }

    func timeline(for configuration: StyleIntent, in context: Context) async -> Timeline<UpcomingEntry> {
        // 每 30 分钟一条，共 24 小时：天数跨日会变，额度的重置时间与过期清零也要跟着走
        let now = Date()
        let dates = (0..<48).map { now.addingTimeInterval(Double($0) * 1800) }
        let entries = dates.map { d -> UpcomingEntry in var e = load(at: d); e.style = configuration.background; return e }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func load(at date: Date) -> UpcomingEntry {
        do { return UpcomingEntry(date: date, items: SubscriptionFile.sorted(try SubscriptionFile.load(), now: date), quotas: QuotaFile.load()) }
        catch { return UpcomingEntry(date: date, items: [], failed: true) }
    }

    /// 仅用于小组件库预览，不是官方价格
    static let sample: [Subscription] = {
        let c = Calendar.current, today = Date()
        func make(_ service: String, _ name: String, _ amount: String, _ currency: String, inDays: Int) -> Subscription {
            var s = Subscription(name: name, amount: amount, currency: currency)
            s.service = service
            s.anchor = c.date(byAdding: .day, value: inDays, to: today) ?? today
            return s
        }
        return [make("chatgpt", "ChatGPT / Codex", "20", "USD", inDays: 2),
                make("claude", "Claude", "20", "USD", inDays: 10),
                make("doubao", "豆包", "19", "CNY", inDays: 13)]
    }()
}

// MARK: - 小组件

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "UpcomingWidget", intent: StyleIntent.self, provider: UpcomingProvider()) { entry in
            UpcomingView(entry: entry).widgetBackground(entry.style)
        }
        .configurationDisplayName("即将扣费")
        .description("续费倒计时，以及各平台的 5 小时和每周额度。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main struct SubscriptionWidgets: WidgetBundle {
    var body: some Widget { UpcomingWidget(); QuotaWidget() }
}

