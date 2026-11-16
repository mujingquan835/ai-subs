import SwiftUI
import WidgetKit

struct UpcomingEntry: TimelineEntry {
    let date: Date
    let items: [Subscription]   // 已按下次扣费排序
    var quotas: [AccountQuota] = []
    var failed = false
    var style: WidgetBackground = .white

    /// 订阅对应服务的额度（目前只有 ChatGPT / Codex 与 Claude 能拿到）
    func quota(for item: Subscription) -> AccountQuota? {
        quotas.first { $0.id == item.catalogService.id && !$0.windows.isEmpty }
    }
}

struct UpcomingView: View {
    let entry: UpcomingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.items.isEmpty {
            EmptyWidget(failed: entry.failed)
        } else if family == .systemLarge {
            LargeWidget(entry: entry)
        } else {
            MediumWidget(entry: entry)
        }
    }
}

// MARK: - 共用部件

private let zh = Locale(identifier: "zh_CN")
private func dateText(_ d: Date) -> String { d.formatted(.dateTime.month().day().weekday(.abbreviated).locale(zh)) }
private func shortDate(_ d: Date) -> String { d.formatted(.dateTime.month().day().locale(zh)) }

/// 倒计时颜色：进入提醒期用橙色，否则用强调色
private func dueTint(_ item: Subscription, _ now: Date) -> Color { item.isDueSoon(now: now) ? .orange : .accentColor }

/// 大字倒计时：“6 天后”，当天显示“今天扣费”，次日显示“明天扣费”
struct Countdown: View {
    let item: Subscription
    let now: Date
    var size: CGFloat
    var suffix = "天后"
    var body: some View {
        let d = item.days(now: now)
        Group {
            if d <= 1 {
                Text(d == 0 ? "今天扣费" : "明天扣费").font(.system(size: size * 0.6, weight: .bold, design: .rounded))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(d)").font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(suffix).font(.system(size: max(11, size * 0.3), weight: .medium))
                }
            }
        }
        .foregroundStyle(dueTint(item, now))
        .widgetAccentable()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// 续费进度条：上次扣费到下次扣费之间已经过去的比例
struct CycleBar: View {
    let item: Subscription
    let now: Date
    var height: CGFloat = 4
    var muted = false
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                Capsule().fill(muted ? Color.secondary.opacity(0.5) : dueTint(item, now)).widgetAccentable()
                    .frame(width: max(height, g.size.width * item.cycleProgress(now: now)))
            }
        }
        .frame(height: height)
        .accessibilityLabel("本期已过 \(Int(item.cycleProgress(now: now) * 100))%")
    }
}

/// 一个订阅的两个额度圆环（5 小时、本周）；没有额度时显示“无额度”
struct QuotaPair: View {
    let quota: AccountQuota?
    let now: Date
    var size: CGFloat = 28
    var labels: (String, String)? = ("5 小时", "本周")
    var spacing: CGFloat = 7

    var body: some View {
        if let q = quota {
            HStack(spacing: spacing) {
                QuotaMiniRing(window: q.windows.first, index: 0, now: now, size: size, label: labels?.0)
                QuotaMiniRing(window: q.windows.dropFirst().first, index: 1, now: now, size: size, label: labels?.1)
            }
        } else {
            Text("无额度").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                .frame(width: size * 2 + spacing, height: size)
        }
    }
}

// MARK: - 中号：主次分栏（方案 C）

struct MediumWidget: View {
    let entry: UpcomingEntry
    var body: some View {
        let a = entry.items[0]
        let b = entry.items.count > 1 ? entry.items[1] : nil
        HStack(spacing: 12) {
            // 左：最先扣费的一项，放大
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ServiceIcon(service: a.catalogService, size: 20)
                    Text(a.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                Spacer(minLength: 2)
                HStack(alignment: .center, spacing: 4) {
                    Countdown(item: a, now: entry.date, size: 38)
                    Spacer(minLength: 4)
                    QuotaPair(quota: entry.quota(for: a), now: entry.date, size: 30)
                }
                Spacer(minLength: 2)
                Text("\(dateText(a.nextDate(now: entry.date))) · \(a.formattedAmount)")
                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                CycleBar(item: a, now: entry.date).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右：第二项，紧凑
            if let b {
                Rectangle().fill(.primary.opacity(0.1)).frame(width: 1)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        ServiceIcon(service: b.catalogService, size: 18)
                        Text(b.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    Countdown(item: b, now: entry.date, size: 26)
                    Text(shortDate(b.nextDate(now: entry.date))).font(.system(size: 9.5)).foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    QuotaPair(quota: entry.quota(for: b), now: entry.date, size: 24, labels: ("5h", "周"), spacing: 6)
                    CycleBar(item: b, now: entry.date, height: 3).padding(.top, 5)
                }
                .frame(width: 104, alignment: .leading)
            }
        }
    }
}

// MARK: - 大号：置顶卡片 + 两项列表（L1）

struct LargeWidget: View {
    let entry: UpcomingEntry

    private var next30: String {
        let c = Calendar.current
        guard let end = c.date(byAdding: .day, value: 30, to: c.startOfDay(for: entry.date)) else { return "" }
        var sums: [String: Decimal] = [:]
        for item in entry.items {
            var d = item.nextDate(now: entry.date)
            while c.startOfDay(for: d) <= end {
                sums[item.currency, default: 0] += item.decimalAmount ?? 0
                guard let n = c.date(byAdding: .month, value: max(1, item.months), to: d) else { break }
                d = n
            }
        }
        return sums.isEmpty ? "无扣费" : sums.sorted { $0.key < $1.key }.map { Subscription.format($0.value, currency: $0.key) }.joined(separator: " · ")
    }

    var body: some View {
        let h = entry.items[0]
        let hq = entry.quota(for: h)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    ServiceIcon(service: h.catalogService, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text("\(dateText(h.nextDate(now: entry.date))) · \(h.formattedAmount)")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Countdown(item: h, now: entry.date, size: 36)
                }
                CycleBar(item: h, now: entry.date, height: 5)
                if let hq {
                    HStack(spacing: 18) {
                        ForEach(Array(hq.windows.prefix(2).enumerated()), id: \.offset) { i, w in
                            HStack(spacing: 8) {
                                QuotaMiniRing(window: w, index: i, now: entry.date, size: 38)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(w.label) \(Int(w.used(now: entry.date).rounded()))%").font(.system(size: 11, weight: .medium))
                                    Text(w.resetText(now: entry.date) ?? "").font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(dueTint(h, entry.date).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer(minLength: 0)
            ForEach(entry.items.dropFirst().prefix(2)) { i in
                HStack(spacing: 10) {
                    ServiceIcon(service: i.catalogService, size: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(i.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(i.days(now: entry.date) == 0 ? "今天" : "\(i.days(now: entry.date)) 天后")
                                .font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(i.isDueSoon(now: entry.date) ? Color.orange : Color.primary)
                        }
                        CycleBar(item: i, now: entry.date, height: 3, muted: !i.isDueSoon(now: entry.date))
                        Text("\(dateText(i.nextDate(now: entry.date))) · \(i.formattedAmount)")
                            .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    }
                    QuotaPair(quota: entry.quota(for: i), now: entry.date, size: 28, labels: ("5h", "周"), spacing: 5)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            }
            Spacer(minLength: 0)
            Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
            HStack {
                Text("未来 30 天").foregroundStyle(.secondary)
                Spacer()
                Text(next30).fontWeight(.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.system(size: 11.5))
        }
    }
}

// MARK: - 空状态

struct EmptyWidget: View {
    let failed: Bool
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: failed ? "exclamationmark.triangle" : "calendar.badge.plus").font(.title2).foregroundStyle(.secondary)
            Text(failed ? "读取数据失败" : "还没有订阅").font(.system(size: 13, weight: .semibold))
            Text(failed ? "打开 App 查看" : "打开 App 添加").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
