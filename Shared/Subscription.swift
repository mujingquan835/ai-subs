import Foundation

struct Subscription: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var amount: String
    var currency = "USD"
    var region = "美国"
    var channel = "官网"
    var payment = "银行卡"
    var anchor = Date()
    var months = 1
    var reminderDays = 3
    // 以下为后加字段，均为可选，以兼容旧数据文件
    var service: String?
    var note: String?

    var catalogService: Service {
        ServiceCatalog.service(id: service) ?? ServiceCatalog.match(name: name) ?? ServiceCatalog.custom(name: name)
    }

    /// 下一次扣费所在周期序号 n（日期 = 锚点 + n × 周期）。
    private func cycleIndex(now: Date) -> Int {
        let c = Calendar.current
        let today = c.startOfDay(for: now)
        var n = 0
        // 每次都从原始锚点推算，避免 31 日在短月截短后继续漂移
        while let d = c.date(byAdding: .month, value: n * max(1, months), to: anchor), c.startOfDay(for: d) < today { n += 1 }
        return n
    }

    func nextDate(now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .month, value: cycleIndex(now: now) * max(1, months), to: anchor) ?? anchor
    }

    /// 上一次扣费日；首个扣费日还没到时，按往前推一个周期估算。
    func previousDate(now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .month, value: (cycleIndex(now: now) - 1) * max(1, months), to: anchor) ?? anchor
    }

    /// 本周期已过去的比例，0…1，按日历日计算。
    func cycleProgress(now: Date = Date()) -> Double {
        let c = Calendar.current
        let start = c.startOfDay(for: previousDate(now: now)), end = c.startOfDay(for: nextDate(now: now))
        let total = c.dateComponents([.day], from: start, to: end).day ?? 0
        guard total > 0 else { return 1 }
        let passed = c.dateComponents([.day], from: start, to: c.startOfDay(for: now)).day ?? 0
        return min(1, max(0, Double(passed) / Double(total)))
    }

    func days(now: Date = Date()) -> Int {
        let c = Calendar.current
        return c.dateComponents([.day], from: c.startOfDay(for: now), to: c.startOfDay(for: nextDate(now: now))).day ?? 0
    }
    var days: Int { days() }

    var decimalAmount: Decimal? { Decimal(string: amount.trimmingCharacters(in: .whitespaces)) }
    var isDueSoon: Bool { days <= reminderDays }
    func isDueSoon(now: Date) -> Bool { days(now: now) <= reminderDays }

    var formattedAmount: String { Self.format(decimalAmount ?? 0, currency: currency) }

    /// 符号在前，例如 $19.99、¥19、HK$58
    static func format(_ value: Decimal, currency: String) -> String {
        let c = Currency.find(currency)
        let digits = ["JPY", "KRW"].contains(c.code) ? 0 : 2
        let number = value.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "zh_CN")))
        return c.prefix + number
    }

    var cycleShort: String {
        switch months { case 1: "月"; case 12: "年"; case 3: "季"; default: "\(months) 个月" }
    }

    var cycleName: String {
        switch months { case 1: "每月"; case 3: "每季度"; case 6: "每半年"; case 12: "每年"; default: "每 \(months) 个月" }
    }

    /// “每月 15 日”“每年 12 月 15 日”
    var cycleDescription: String {
        let c = Calendar.current.dateComponents([.month, .day], from: anchor)
        let day = c.day ?? 1
        switch months {
        case 1: return "每月 \(day) 日"
        case 12: return "每年 \(c.month ?? 1) 月 \(day) 日"
        default: return "\(cycleName)（\(day) 日）"
        }
    }

    var daysText: String {
        switch days { case 0: "今天"; case 1: "明天"; default: "\(days) 天后" }
    }
}

struct Currency {
    let code: String
    let name: String
    let symbol: String
    /// 金额前缀，与人民币同为 ¥ 的日元加 JP 区分
    var prefix: String { code == "JPY" ? "JP¥" : symbol }
    var label: String { "\(name) \(symbol)" }

    static let all: [Currency] = [
        .init(code: "USD", name: "美元", symbol: "$"),
        .init(code: "CNY", name: "人民币", symbol: "¥"),
        .init(code: "HKD", name: "港币", symbol: "HK$"),
        .init(code: "JPY", name: "日元", symbol: "¥"),
        .init(code: "EUR", name: "欧元", symbol: "€"),
        .init(code: "GBP", name: "英镑", symbol: "£"),
        .init(code: "KRW", name: "韩元", symbol: "₩"),
        .init(code: "TRY", name: "土耳其里拉", symbol: "₺"),
        .init(code: "CAD", name: "加元", symbol: "C$"),
    ]
    static func find(_ code: String) -> Currency { all.first { $0.code == code } ?? .init(code: code, name: code, symbol: code + " ") }
}

/// 数据文件位置与读取。App 与小组件共用 App Group 容器里的同一份 JSON。
enum SubscriptionFile {
    /// 由构建设置 APP_GROUP_ID 写入 Info.plist（团队 ID + 包名），未签名构建时为空
    static let appGroup: String? = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "AISubAppGroup") as? String,
              !id.isEmpty, !id.hasPrefix("."), !id.contains("$(") else { return nil }
        return id
    }()
    static let legacyURL = URL.applicationSupportDirectory.appending(path: "AISubscriptions/subscriptions.json")

    static var url: URL {
        // AISUB_DATA 仅用于开发调试，指向独立的数据文件，避免碰到真实数据
        if let custom = ProcessInfo.processInfo.environment["AISUB_DATA"] { return URL(fileURLWithPath: custom) }
        if let appGroup, let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return group.appending(path: "subscriptions.json")
        }
        return legacyURL
    }

    /// 旧版本数据在 Application Support，首次启动时复制进共享容器（保留原文件）。
    static func migrateIfNeeded() {
        let target = url
        let fm = FileManager.default
        guard target != legacyURL, !fm.fileExists(atPath: target.path), fm.fileExists(atPath: legacyURL.path) else { return }
        try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.copyItem(at: legacyURL, to: target)
    }

    static func load() throws -> [Subscription] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Subscription].self, from: Data(contentsOf: url))
    }

    static func sorted(_ items: [Subscription], now: Date = Date()) -> [Subscription] {
        items.sorted {
            let a = $0.nextDate(now: now), b = $1.nextDate(now: now)
            if a != b { return a < b }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

@MainActor final class Store: ObservableObject {
    @Published var items: [Subscription] = []
    @Published var error: String?
    let url: URL
    /// 保存成功后调用，App 用它通知小组件刷新
    var onSave: (() -> Void)?

    init() {
        SubscriptionFile.migrateIfNeeded()
        url = SubscriptionFile.url
        do { items = try SubscriptionFile.load() }
        catch { self.error = "读取数据失败：\(error.localizedDescription)" }
    }

    var sorted: [Subscription] { SubscriptionFile.sorted(items) }

    @discardableResult func save(_ value: [Subscription]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            items = value
            error = nil
            onSave?()
            return true
        } catch {
            self.error = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult func upsert(_ item: Subscription) -> Bool {
        var next = items
        if let i = next.firstIndex(where: { $0.id == item.id }) { next[i] = item } else { next.append(item) }
        return save(next)
    }

    func delete(_ id: UUID) { save(items.filter { $0.id != id }) }
}
