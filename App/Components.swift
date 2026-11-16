import SwiftUI

/// 白色圆角卡片容器，对应 macOS 系统设置里的分组样式。
struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }
}

struct SectionHeader: View {
    let title: String
    var count: Int?
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let count { Text("\(count)").monospacedDigit().foregroundStyle(.tertiary) }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

/// 剩余天数胶囊：进入提醒期用橙色，同时保留文字，不只靠颜色。
struct DaysBadge: View {
    let item: Subscription
    var body: some View {
        Text(item.daysText)
            .font(.callout.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(item.isDueSoon ? Color.orange : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background((item.isDueSoon ? Color.orange : Color.primary).opacity(item.isDueSoon ? 0.14 : 0.06), in: Capsule())
    }
}

/// 带图标的胶囊按钮，对应参考图里“点一下即可接入”的样式。
struct ServiceChip: View {
    let service: Service
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ServiceIcon(service: service, size: 20)
                Text(service.name).foregroundStyle(.primary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(hovering ? 0.07 : 0.0), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(hovering ? 0.2 : 0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct StepNumber: View {
    let n: Int
    var body: some View {
        Text("\(n)")
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.2))
    }
}

/// 简单的流式布局，用于换行排列胶囊按钮。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }
    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }
    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var r = rows[rows.count - 1]
            r.width += (r.indices.isEmpty ? 0 : spacing) + size.width
            r.height = max(r.height, size.height)
            r.indices.append(i)
            rows[rows.count - 1] = r
        }
        return rows
    }
}
