import SwiftUI

/// 首次使用时的授权说明：讲清楚会读什么、发给谁，用户同意后才扫描。
struct DiscoveryConsentCard: View {
    @EnvironmentObject var discovery: Discovery
    var body: some View {
        Card(padding: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("自动识别本机的 AI 订阅").font(.headline)
                    Text("找出这台 Mac 上安装的 AI 工具，读取 Claude Code、Codex 的本地登录信息来识别订阅档位，一键导入，并显示 5 小时和每周额度。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("会读取哪些内容") {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("应用程序文件夹与常见命令行安装位置", systemImage: "app.badge")
                            Label("~/.codex/auth.json、~/.claude.json", systemImage: "doc.text")
                            Label("钥匙串中的 Claude Code 登录项（通过系统 security 工具）", systemImage: "key")
                            Label("查询额度时只连接 OpenAI 与 Anthropic 官方服务器，不上传到其他地方", systemImage: "lock.shield")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }
                    .font(.callout)
                    HStack(spacing: 10) {
                        Button("允许并扫描") { withAnimation(.snappy) { discovery.allow() } }
                            .buttonStyle(.borderedProminent)
                        Button("暂不") { withAnimation(.snappy) { discovery.dismissed = true } }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

/// 订阅列表标题右侧的工具：刷新额度、设置向导、更多
struct DiscoveryToolbar: View {
    @EnvironmentObject var discovery: Discovery
    var body: some View {
        HStack(spacing: 10) {
            if discovery.refreshing { ProgressView().controlSize(.small) }
            Button { discovery.scan(); Task { await discovery.refreshQuota() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("重新扫描本机并刷新额度")
                .disabled(discovery.refreshing)
            Button("设置向导…") { discovery.showGuide = true }
                .buttonStyle(.borderless)
                .help("安装、登录 Codex 与 Claude Code")
            Menu {
                Button("设置向导…") { discovery.showGuide = true }
                Divider()
                Button("关闭自动识别", role: .destructive) { withAnimation(.snappy) { discovery.turnOff() } }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.trailing, 4)
    }
}

/// 本机发现、但还没加进订阅的工具。识别到订阅档位的可一键导入，其余可快速添加。
struct DiscoveredChips: View {
    @EnvironmentObject var discovery: Discovery
    @EnvironmentObject var store: Store
    let onImport: (Subscription) -> Void
    let onAdd: (Service) -> Void

    private var pending: [DetectedAgent] {
        discovery.agents.filter { a in !store.items.contains { $0.catalogService.id == a.serviceID } }
    }

    var body: some View {
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionHeader(title: "本机还发现")
                    Spacer()
                    // 没有订阅时列表不显示，工具放在这里
                    if store.items.isEmpty { DiscoveryToolbar() }
                }
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("这些工具装在本机，但还没加进订阅。点一下添加；带“可导入”的已识别到订阅档位和续费日。")
                            .font(.callout).foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(pending) { agent in
                                DiscoveredChip(agent: agent) {
                                    if agent.account != nil { onImport(makeSubscription(agent)) } else { onAdd(agent.service) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func makeSubscription(_ agent: DetectedAgent) -> Subscription {
        var s = Subscription(name: agent.title, amount: "")
        s.service = agent.serviceID
        if let a = agent.account {
            if let anchor = a.anchor { s.anchor = anchor }
            if let channel = a.channel { s.channel = channel }
            s.note = "由本机识别导入：\(agent.title)"
        }
        return s
    }
}

private struct DiscoveredChip: View {
    let agent: DetectedAgent
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ServiceIcon(service: agent.service, size: 20)
                Text(agent.account == nil ? agent.service.name : agent.title).foregroundStyle(.primary)
                if agent.account != nil {
                    Text("可导入").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                Image(systemName: "plus").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(hovering ? 0.07 : 0), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(hovering ? 0.2 : 0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(agent.sources.joined(separator: " · "))
    }
}
