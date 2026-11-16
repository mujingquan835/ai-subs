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

/// 本机识别结果 + 额度
struct DiscoverySection: View {
    @EnvironmentObject var discovery: Discovery
    @EnvironmentObject var store: Store
    let onImport: (Subscription) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionHeader(title: "本机 AI 工具", count: discovery.agents.count)
                Spacer()
                if discovery.refreshing { ProgressView().controlSize(.small) }
                Button { discovery.scan(); Task { await discovery.refreshQuota() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("重新扫描并刷新额度")
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
            Card {
                if discovery.agents.isEmpty {
                    Text("没有找到已安装的 AI 工具").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(discovery.agents.enumerated()), id: \.element.id) { i, agent in
                            AgentRow(agent: agent, quota: discovery.quota(for: agent.serviceID),
                                     added: store.items.contains { $0.catalogService.id == agent.serviceID },
                                     onImport: { onImport(makeSubscription(agent)) },
                                     onLogin: { discovery.loginClaude() })
                            if i < discovery.agents.count - 1 { Divider().padding(.leading, 60) }
                        }
                    }
                    .padding(.vertical, 4)
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

struct AgentRow: View {
    let agent: DetectedAgent
    let quota: AccountQuota?
    let added: Bool
    let onImport: () -> Void
    var onLogin: () -> Void = {}

    private var detail: String {
        guard let a = agent.account else { return agent.sources.joined(separator: " · ") + " · 未识别到订阅" }
        var parts: [String] = []
        if let c = a.channel { parts.append(c == "Apple App Store" ? "Apple 订阅" : c) }
        if let d = a.anchor {
            let t = d.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
            parts.append(a.anchorIsRenewal ? "本期至 \(t)" : "开通于 \(t)")
        }
        parts.append(agent.sources.first ?? "")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            ServiceIcon(service: agent.service, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.account == nil ? agent.service.name : agent.title).font(.body.weight(.medium))
                }
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            if let quota {
                if quota.windows.isEmpty, quota.needsLogin == true, agent.serviceID == "claude" {
                    HStack(spacing: 8) {
                        Text("登录 Claude Code 后可查看额度").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        Button("登录获取", action: onLogin).controlSize(.small)
                            .help("打开终端启动 Claude Code，输入 /login 用订阅账号登录")
                    }
                } else if quota.windows.isEmpty, let err = quota.error {
                    Label(err, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    HStack(spacing: 14) {
                        ForEach(quota.windows, id: \.label) { QuotaGauge(window: $0) }
                    }
                    .help(quota.error.map { "上次刷新失败：\($0)" } ?? "更新于 \(quota.fetchedAt.formatted(date: .omitted, time: .shortened))")
                }
            }
            Group {
                if agent.account == nil {
                    EmptyView()
                } else if added {
                    Text("已添加").font(.callout).foregroundStyle(.secondary)
                } else {
                    Button("导入", action: onImport).controlSize(.small)
                }
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// 一个额度窗口：标签、百分比和一条细进度条；≥80% 橙色，用完红色。
struct QuotaGauge: View {
    let window: QuotaWindow
    var width: CGFloat = 92
    var body: some View {
        let used = window.used()
        let color: Color = switch window.level() { case .normal: .accentColor; case .warning: .orange; case .exhausted: .red }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(window.label).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(window.level() == .exhausted ? "已用完" : "\(Int(used.rounded()))%")
                    .fontWeight(.medium).monospacedDigit()
                    .foregroundStyle(window.level() == .normal ? Color.primary : color)
            }
            .font(.caption)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(color).frame(width: max(3, g.size.width * used / 100))
                }
            }
            .frame(height: 4)
        }
        .frame(width: width)
        .help(window.resetText() ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.label)已用 \(Int(used))%，\(window.resetText() ?? "")")
    }
}
