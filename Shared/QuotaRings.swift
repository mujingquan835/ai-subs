import SwiftUI

/// 额度颜色：正常时 5 小时蓝、每周青；≥80% 橙；用完红。颜色之外始终带百分比文字。
func quotaColor(_ window: QuotaWindow, index: Int, now: Date) -> Color {
    switch window.level(now: now) {
    case .exhausted: .red
    case .warning: .orange
    case .normal: index == 0 ? .blue : .teal
    }
}

/// 同心圆环：外圈 = 每周，内圈 = 5 小时，中间是服务图标。
struct QuotaRings: View {
    let account: AccountQuota
    let now: Date
    var size: CGFloat = 76

    var body: some View {
        let line = size * 0.11
        ZStack {
            ForEach(Array(account.windows.prefix(2).enumerated()), id: \.offset) { i, w in
                // 第 0 个是 5 小时，画在内圈；第 1 个是每周，画在外圈
                let inset = account.windows.count > 1 && i == 0 ? line * 1.45 : 0
                Ring(progress: w.used(now: now) / 100, color: quotaColor(w, index: i, now: now), lineWidth: line)
                    .padding(inset)
            }
            ServiceIcon(service: ServiceCatalog.service(id: account.id) ?? ServiceCatalog.custom(name: account.name),
                        size: size * (account.windows.count > 1 ? 0.34 : 0.46))
        }
        .frame(width: size, height: size)
    }
}

struct Ring: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

/// 图例一行：色点、名称、百分比，下面一行是重置时间。
struct QuotaLegendRow: View {
    let window: QuotaWindow
    let index: Int
    let now: Date
    var compact = false

    var body: some View {
        let color = quotaColor(window, index: index, now: now)
        let level = window.level(now: now)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(window.label).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(level == .exhausted ? "已用完" : "\(Int(window.used(now: now).rounded()))%")
                    .font(.system(size: compact ? 13 : 15, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(level == .normal ? Color.primary : color)
            }
            if let reset = window.resetText(now: now) {
                Text(reset).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 12)
            }
        }
    }
}

/// 单个额度圆环：中间写百分比，下面写标签；没有数据时显示灰环和“–”
struct QuotaMiniRing: View {
    let window: QuotaWindow?
    let index: Int
    let now: Date
    var size: CGFloat = 28
    var label: String?

    var body: some View {
        let used = window?.used(now: now) ?? 0
        let color = window.map { quotaColor($0, index: index, now: now) } ?? .secondary
        VStack(spacing: 2) {
            ZStack {
                Ring(progress: used / 100, color: color, lineWidth: size * 0.12)
                Text(window == nil ? "–" : window!.level(now: now) == .exhausted ? "满" : "\(Int(used.rounded()))")
                    .font(.system(size: size * 0.33, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(used >= 80 ? color : .primary)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: size, height: size)
            if let label { Text(label).font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label ?? "")已用 \(Int(used))%")
    }
}

