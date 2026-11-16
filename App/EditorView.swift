import SwiftUI

/// 新增 / 编辑订阅。新增分两步：选服务 → 填账单；编辑或已预选服务时直接进入表单。
struct EditorView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var item: Subscription
    @State private var picking: Bool
    @State private var confirmDelete = false
    @State private var showMore = false
    @FocusState private var amountFocused: Bool
    private let isNew: Bool

    init(route: EditorRoute) {
        switch route {
        case .edit(let existing):
            _item = State(initialValue: existing)
            _picking = State(initialValue: false)
            isNew = false
        case .new(let preset):
            var s = Subscription(name: preset?.name ?? "", amount: "")
            s.service = preset?.id
            _item = State(initialValue: s)
            _picking = State(initialValue: preset == nil)
            isNew = true
        case .guide:
            _item = State(initialValue: Subscription(name: "", amount: ""))
            _picking = State(initialValue: true)
            isNew = true
        case .prefill(let s):
            _item = State(initialValue: s)
            _picking = State(initialValue: false)
            isNew = true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if picking {
                ServicePicker(selected: item.service) { choose($0) } onCustom: { choose(nil) } onCancel: { dismiss() }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                form.transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 540, height: picking ? 620 : 490)
        .animation(.snappy(duration: 0.28), value: picking)
    }

    private func choose(_ service: Service?) {
        let oldDefault = ServiceCatalog.service(id: item.service)?.name ?? ""
        item.service = service?.id
        // 名称仍是默认值时才跟着服务变，避免覆盖用户自己起的名字
        if item.name.isEmpty || item.name == oldDefault { item.name = service?.name ?? "" }
        picking = false
    }

    // MARK: 表单

    private var amountInvalid: Bool { item.decimalAmount.map { $0 < 0 } ?? true }
    private var nameEmpty: Bool { item.name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canSave: Bool { !amountInvalid && !nameEmpty }

    private var form: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    if item.service == nil {
                        TextField("名称", text: $item.name, prompt: Text("服务名称"))
                    }
                    LabeledContent("金额") {
                        HStack(spacing: 8) {
                            TextField("金额", text: $item.amount, prompt: Text("0.00"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .focused($amountFocused)
                            Picker("币种", selection: $item.currency) {
                                ForEach(Currency.all, id: \.code) { Text($0.label).tag($0.code) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                    if !item.amount.isEmpty && amountInvalid {
                        Text("请输入不小于 0 的数字，例如 19.99").font(.callout).foregroundStyle(.red)
                    }
                    CyclePicker(months: $item.months)
                    DatePicker("最近一次扣费", selection: $item.anchor, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    Picker("提醒", selection: $item.reminderDays) {
                        Text("当天").tag(0); Text("提前 1 天").tag(1); Text("提前 3 天").tag(3); Text("提前 7 天").tag(7)
                    }
                } footer: {
                    Text("填过去任意一次扣费日即可，下次日期自动推算。")
                }

                Section {
                    DisclosureGroup(isExpanded: $showMore) {
                        if item.service != nil {
                            TextField("显示名称", text: $item.name, prompt: Text("例如：Claude 工作账号"))
                        }
                        OptionPicker(title: "账单地区", value: $item.region, options: ["美国", "中国大陆", "中国香港", "日本", "韩国", "土耳其", "加拿大", "欧洲", "其他"])
                        OptionPicker(title: "订阅渠道", value: $item.channel, options: ["官网", "Apple App Store", "Google Play", "其他"])
                        OptionPicker(title: "支付方式", value: $item.payment, options: ["银行卡", "礼品卡余额", "支付宝", "微信", "PayPal", "其他"])
                        TextField("备注", text: Binding(get: { item.note ?? "" }, set: { item.note = $0.isEmpty ? nil : $0 }),
                                  prompt: Text("充值说明、取消续订提示等"), axis: .vertical)
                            .lineLimit(1...3)
                    } label: {
                        HStack {
                            Text("更多信息")
                            Spacer()
                            if !showMore {
                                Text("\(item.region) · \(item.channel) · \(item.payment)").foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.snappy) { showMore.toggle() } }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            footer
        }
        .onAppear { amountFocused = true }
        .alert("删除“\(item.name)”？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { withAnimation(.snappy) { store.delete(item.id) }; dismiss() }
            Button("取消", role: .cancel) {}
        } message: { Text("这条记录会从列表中移除，无法撤销。") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ServiceIcon(service: item.catalogService, size: 40)
                .animation(.snappy, value: item.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(isNew ? "添加订阅" : "编辑订阅").font(.headline)
                Text(item.service.flatMap { ServiceCatalog.service(id: $0)?.name } ?? "自定义项目")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("更换服务") { picking = true }.controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    private var summary: String {
        guard let value = item.decimalAmount, value >= 0 else { return "填写金额后显示下次扣费" }
        let next = item.nextDate()
        let days = item.days
        let reminder = item.reminderDays == 0 ? "当天提醒" : "提前 \(item.reminderDays) 天提醒"
        return "\(item.cycleDescription) · \(Subscription.format(value, currency: item.currency)) · 下次 \(next.formatted(.dateTime.month().day()))（\(days == 0 ? "今天" : "\(days) 天后")）· \(reminder)"
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock").foregroundStyle(.secondary)
                Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(2).monospacedDigit()
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            HStack {
                if !isNew {
                    Button("删除…", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "添加" : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .controlSize(.large)
            .padding(20)
        }
        .background(.bar)
    }

    private func save() {
        guard canSave, let value = item.decimalAmount else { return }
        var clean = item
        clean.name = item.name.trimmingCharacters(in: .whitespaces)
        clean.amount = "\(value)"
        var ok = false
        withAnimation(.snappy) { ok = store.upsert(clean) }
        if ok { dismiss() }
    }
}

// MARK: - 第一步：选择服务

struct ServicePicker: View {
    let selected: String?
    let onPick: (Service) -> Void
    let onCustom: () -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private func services(_ group: Service.Group) -> [Service] {
        ServiceCatalog.all.filter { $0.group == group && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("选择服务").font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索服务", text: $query).textFieldStyle(.plain).focused($searchFocused)
                        .onSubmit { if let first = (services(.global) + services(.domestic)).first { onPick(first) } }
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Service.Group.allCases, id: \.self) { group in
                        let list = services(group)
                        if !list.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionHeader(title: group.rawValue)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                    ForEach(list) { s in ServiceTile(service: s, selected: s.id == selected) { onPick(s) } }
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "其他")
                        Button(action: onCustom) {
                            HStack(spacing: 10) {
                                Image(systemName: "plus").font(.body.weight(.semibold)).frame(width: 32, height: 32)
                                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(query.isEmpty ? "自定义项目" : "自定义“\(query)”").foregroundStyle(.primary)
                                    Text("目录里没有时，直接填写名称").font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverRowStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            Divider()
            HStack {
                Text("点击服务进入下一步").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction).controlSize(.large)
            }
            .padding(16)
            .background(.bar)
        }
        .onAppear { searchFocused = true }
    }
}

struct ServiceTile: View {
    let service: Service
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ServiceIcon(service: service, size: 40)
                Text(service.name).font(.callout).lineLimit(1).minimumScaleFactor(0.85).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(hovering ? 0.06 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .scaleEffect(hovering ? 1.02 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(service.name)
    }
}

struct HoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { HoverRow(configuration: configuration) }
    private struct HoverRow: View {
        let configuration: Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(configuration.isPressed ? 0.1 : hovering ? 0.05 : 0)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - 表单控件

/// 周期：预设 + 自定义每 N 个月。
struct CyclePicker: View {
    @Binding var months: Int
    private static let presets = [1, 3, 12]
    private var mode: Binding<Int> {
        Binding(get: { Self.presets.contains(months) ? months : 0 }, set: { months = $0 == 0 ? 6 : $0 })
    }
    var body: some View {
        Picker("周期", selection: mode) {
            Text("月付").tag(1); Text("季付").tag(3); Text("年付").tag(12); Text("自定义").tag(0)
        }
        .pickerStyle(.segmented)
        if !Self.presets.contains(months) {
            Stepper(value: $months, in: 1...36) { Text("每 \(months) 个月扣费一次").monospacedDigit() }
        }
    }
}

/// 下拉选项，旧数据里的非预设值也会保留并显示。
struct OptionPicker: View {
    let title: String
    @Binding var value: String
    let options: [String]
    var body: some View {
        Picker(title, selection: $value) {
            ForEach(options.contains(value) ? options : options + [value], id: \.self) { Text($0) }
        }
    }
}
