import Foundation

/// 一个额度窗口，例如 5 小时或 7 天。
struct QuotaWindow: Codable, Hashable {
    var label: String          // “5 小时”“本周”
    var usedPercent: Double    // 0…100
    var resetsAt: Date?
    var spanSeconds: Double

    /// 已过重置时间的窗口视为清零，避免小组件显示过期数据
    func used(now: Date = Date()) -> Double {
        if let r = resetsAt, r <= now { return 0 }
        return min(100, max(0, usedPercent))
    }
    func level(now: Date = Date()) -> QuotaLevel {
        let u = used(now: now)
        return u >= 100 ? .exhausted : u >= 80 ? .warning : .normal
    }

    /// “2 小时 58 分后重置”“周三 21:00 重置”
    func resetText(now: Date = Date()) -> String? {
        guard let r = resetsAt else { return nil }
        if r <= now { return "已重置" }
        let s = Int(r.timeIntervalSince(now))
        if s < 3600 { return "\(max(1, s / 60)) 分钟后重置" }
        if s < 24 * 3600 { return "\(s / 3600) 小时 \((s % 3600) / 60) 分后重置" }
        return r.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(Locale(identifier: "zh_CN"))) + " 重置"
    }
}

enum QuotaLevel { case normal, warning, exhausted }

/// 一个账号的额度快照，由 App 拉取后写入共享容器，小组件只读。
struct AccountQuota: Codable, Identifiable, Hashable {
    var id: String             // 服务 ID，例如 chatgpt、claude
    var name: String           // “ChatGPT Plus”
    var windows: [QuotaWindow]
    var fetchedAt: Date
    var error: String?
    var needsLogin: Bool?      // 原工具没有用订阅账号登录或登录已过期

    func level(now: Date = Date()) -> QuotaLevel {
        let ls = windows.map { $0.level(now: now) }
        return ls.contains(.exhausted) ? .exhausted : ls.contains(.warning) ? .warning : .normal
    }
}

enum QuotaFile {
    static var url: URL { SubscriptionFile.url.deletingLastPathComponent().appending(path: "quota.json") }

    static func load() -> [AccountQuota] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (try? d.decode([AccountQuota].self, from: data)) ?? []
    }

    static func save(_ value: [AccountQuota]) throws {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try e.encode(value).write(to: url, options: .atomic)
    }
}
