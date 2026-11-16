import SwiftUI

enum Filter: String, CaseIterable, Identifiable {
    case all = "全部", week = "7 天内", month = "30 天内"
    var id: Self { self }
    func includes(_ item: Subscription) -> Bool {
        switch self { case .all: true; case .week: item.days <= 7; case .month: item.days <= 30 }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var discovery: Discovery
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var editor: EditorRoute?
    @State private var pendingDelete: Subscription?

    private var visible: [Subscription] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return store.sorted.filter { filter.includes($0) && (q.isEmpty || [$0.name, $0.region, $0.channel, $0.payment, $0.note ?? ""].contains { $0.localizedCaseInsensitiveContains(q) }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = store.error { ErrorBanner(text: error) { store.error = nil } }
                if !discovery.enabled && !discovery.dismissed { DiscoveryConsentCard() }
                if store.items.isEmpty {
                    if discovery.enabled { DiscoverySection { editor = .prefill($0) } }
                    OnboardingCard { editor = .new($0) }
                } else {
                    SummaryCard(items: store.sorted) { editor = .edit($0) }
                    if discovery.enabled { DiscoverySection { editor = .prefill($0) } }
                    list
                }
                if !discovery.enabled && discovery.dismissed {
                    Button("自动识别本机 AI 订阅…") { withAnimation(.snappy) { discovery.dismissed = false } }
                        .buttonStyle(.link)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("AI 订阅管家")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("筛选", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    .disabled(store.items.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { editor = .new(nil) } label: { Label("添加订阅", systemImage: "plus") }
                    .keyboardShortcut("n")
                    .help("添加订阅（⌘N）")
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "搜索名称、地区、渠道")
        .sheet(item: $editor) { route in
            if case .guide = route { SetupGuideView() } else { EditorView(route: route) }
        }
        .onChange(of: discovery.showGuide) { _, show in if show { editor = .guide } }
        .onChange(of: editor?.id) { _, id in if id != "guide" { discovery.showGuide = false } }
        .onAppear {
            discovery.store = store
            if discovery.enabled { Task { await discovery.refreshQuota() } }
            #if DEBUG
            // 仅调试：AISUB_OPEN=new / edit 启动即打开表单，便于截图检查
            switch ProcessInfo.processInfo.environment["AISUB_OPEN"] {
            case "new": editor = .new(nil)
            case "add": editor = .new(ServiceCatalog.service(id: "claude"))
            case "guide": editor = .guide
            case "edit": if let first = store.sorted.first { editor = .edit(first) }
            default: break
            }
            #endif
        }
        .alert("删除“\(pendingDelete?.name ?? "")”？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("删除", role: .destructive) {
                if let id = pendingDelete?.id { withAnimation(.snappy) { store.delete(id) } }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这条记录会从列表中移除，无法撤销。")
        }
    }

    @ViewBuilder private var list: some View {
        let soon = visible.filter(\.isDueSoon)
        let later = visible.filter { !$0.isDueSoon }
        if visible.isEmpty {
            Card {
                ContentUnavailableView(search.isEmpty ? "\(filter.rawValue)没有扣费" : "没有匹配“\(search)”的订阅",
                                       systemImage: search.isEmpty ? "calendar" : "magnifyingglass")
                    .padding(.vertical, 28)
            }
        }
        if !soon.isEmpty { group("即将扣费", soon) }
        if !later.isEmpty { group(soon.isEmpty ? "全部订阅" : "之后", later) }
    }

    private func group(_ title: String, _ items: [Subscription]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title, count: items.count)
            Card {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        SubscriptionRow(item: item, onEdit: { editor = .edit(item) }, onDelete: { pendingDelete = item })
                        if index < items.count - 1 { Divider().padding(.leading, 64) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - 列表行

struct SubscriptionRow: View {
    @EnvironmentObject var discovery: Discovery
    let item: Subscription
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    /// 能查额度的服务：有数据显示两个圆环；没数据显示“获取额度”；原工具没登录显示“登录获取”
    @ViewBuilder private var quotaArea: some View {
        let id = item.catalogService.id
        if Discovery.quotaServices.contains(id) {
            let q = discovery.enabled ? discovery.quota(for: id) : nil
            if let q, !q.windows.isEmpty {
                HStack(spacing: 6) {
                    QuotaMiniRing(window: q.windows.first, index: 0, now: Date(), size: 28, label: "5 小时")
                    QuotaMiniRing(window: q.windows.dropFirst().first, index: 1, now: Date(), size: 28, label: "本周")
                }
                .help(q.windows.compactMap { w in w.resetText().map { "\(w.label)：\($0)" } }.joined(separator: "\n"))
            } else if q?.needsLogin == true && id == "claude" {
                Button("登录获取") { discovery.loginClaude() }.controlSize(.small)
                    .help("打开终端启动 Claude Code，输入 /login 用订阅账号登录，之后回来点刷新")
            } else if discovery.refreshing {
                ProgressView().controlSize(.small)
            } else {
                Button("获取额度") { discovery.requestQuota() }.controlSize(.small)
                    .help(q?.error ?? "读取本机登录信息，查询 5 小时和每周额度")
            }
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ServiceIcon(service: item.catalogService, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                Text([item.region, item.channel, item.payment].joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            quotaArea
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(item.formattedAmount) / \(item.cycleShort)").font(.body).monospacedDigit()
                Text(item.nextDate().formatted(.dateTime.month().day().weekday(.abbreviated)))
                    .font(.callout).foregroundStyle(.secondary)
            }
            DaysBadge(item: item).frame(width: 76, alignment: .trailing)
            Menu {
                Button("编辑…", systemImage: "pencil", action: onEdit)
                Divider()
                Button("删除…", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis").frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
            .help("更多操作")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.045 : 0)).padding(.horizontal, 4))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("编辑…", systemImage: "pencil", action: onEdit)
            Divider()
            Button("删除…", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "编辑", onEdit)
        .accessibilityAction(named: "删除", onDelete)
    }
}

// MARK: - 概览

struct SummaryCard: View {
    let items: [Subscription]
    let onOpen: (Subscription) -> Void

    /// 未来 30 天内（含今天）的扣费，按币种分别求和，不跨币种相加。
    private var next30: [(String, Decimal)] {
        let c = Calendar.current
        let today = c.startOfDay(for: Date())
        guard let end = c.date(byAdding: .day, value: 30, to: today) else { return [] }
        var sums: [String: Decimal] = [:]
        for item in items {
            var d = item.nextDate()
            while c.startOfDay(for: d) <= end {
                sums[item.currency, default: 0] += item.decimalAmount ?? 0
                guard let n = c.date(byAdding: .month, value: max(1, item.months), to: d) else { break }
                d = n
            }
        }
        return sums.sorted { $0.key < $1.key }
    }

    private var monthly: [(String, Decimal)] {
        var sums: [String: Decimal] = [:]
        for item in items { sums[item.currency, default: 0] += (item.decimalAmount ?? 0) / Decimal(max(1, item.months)) }
        return sums.sorted { $0.key < $1.key }
    }

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 0) {
                if let first = items.first {
                    metric("下一次扣费") {
                        Button { onOpen(first) } label: {
                            HStack(spacing: 10) {
                                ServiceIcon(service: first.catalogService, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(first.name).font(.headline).lineLimit(1)
                                    Text("\(first.nextDate().formatted(.dateTime.month().day())) · \(first.formattedAmount)")
                                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                                }
                                Spacer(minLength: 4)
                                DaysBadge(item: first)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                }
                Divider().padding(.vertical, 14)
                metric("未来 30 天") { amounts(next30, empty: "无扣费") }.frame(width: 190)
                Divider().padding(.vertical, 14)
                metric("月均 · \(items.count) 项") { amounts(monthly, empty: "—") }.frame(width: 190)
            }
        }
    }

    private func metric<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func amounts(_ list: [(String, Decimal)], empty: String) -> some View {
        if list.isEmpty {
            Text(empty).font(.title3.weight(.semibold)).foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(list, id: \.0) { code, value in
                    Text(Subscription.format(value, currency: code))
                        .font(list.count > 1 ? .headline : .title3.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - 空状态：快速上手

struct OnboardingCard: View {
    let onPick: (Service?) -> Void
    var body: some View {
        Card(padding: 24) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("快速上手").font(.title2.weight(.semibold))
                    Text("还没有订阅记录").foregroundStyle(.secondary)
                }
                .padding(.bottom, 20)

                step(1, "选择一个 AI 服务", "点一下常用服务直接开始填写，或从完整目录里挑选、自定义") {
                    FlowLayout(spacing: 8) {
                        ForEach(ServiceCatalog.popular) { s in ServiceChip(service: s) { onPick(s) } }
                        Button("全部服务…") { onPick(nil) }.buttonStyle(.link).padding(.leading, 4).padding(.top, 6)
                    }
                    .padding(.top, 12)
                }
                Divider().padding(.vertical, 18)
                step(2, "填写费用与扣费日期", "地区、渠道、支付方式和周期都可以按实际账单记录", content: { EmptyView() })
                Divider().padding(.vertical, 18)
                step(3, "查看扣费倒计时", "列表按下次扣费排序，进入提醒期的订阅会以橙色标出", content: { EmptyView() })
            }
        }
    }

    private func step<V: View>(_ n: Int, _ title: String, _ detail: String, @ViewBuilder content: () -> V) -> some View {
        HStack(alignment: .top, spacing: 14) {
            StepNumber(n: n)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
                content()
            }
            .padding(.top, 3)
        }
    }
}

struct ErrorBanner: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(text).textSelection(.enabled)
            Spacer()
            Button("关闭", action: dismiss).buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
