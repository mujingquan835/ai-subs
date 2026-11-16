import Foundation

/// 汇率：以人民币为基准，rates[币种] = 1 人民币可兑换的该币种数量。
/// 内置一份汇率保证离线可用；允许联网时每 12 小时从 Frankfurter（欧洲央行数据，免密钥）更新一次。
@MainActor final class ExchangeRates: ObservableObject {
    struct Snapshot: Codable, Equatable {
        var date: String            // 汇率日期，例如 2026-11-13
        var rates: [String: Double]
        var online: Bool            // true = 联网获取，false = 内置
        var fetchedAt: Date?
    }

    /// 内置汇率：2026-11-13 欧洲央行参考汇率（经 Frankfurter 获取）
    static let builtIn = Snapshot(date: "2026-11-13", rates: [
        "CNY": 1, "USD": 0.14988, "HKD": 1.176, "JPY": 23.981, "EUR": 0.13562,
        "GBP": 0.11332, "KRW": 200.41, "TRY": 7.5493, "CAD": 0.2137,
    ], online: false, fetchedAt: nil)

    @Published private(set) var snapshot: Snapshot
    @Published var autoUpdate: Bool { didSet { UserDefaults.standard.set(autoUpdate, forKey: Self.autoKey); if autoUpdate { Task { await refresh(force: true) } } } }
    @Published private(set) var lastError: String?

    private static let cacheKey = "exchangeRatesCache", autoKey = "exchangeRatesAutoUpdate"
    private static let endpoint = URL(string: "https://api.frankfurter.dev/v1/latest?from=CNY")!

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(Snapshot.self, from: data), cached.date >= Self.builtIn.date {
            snapshot = cached
        } else {
            snapshot = Self.builtIn
        }
        // 默认允许联网更新；用户关闭后只用内置或上次缓存的汇率
        autoUpdate = UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true
        Task { await refresh() }
    }

    /// 把某币种金额换算成人民币；没有该币种汇率时返回 nil
    func toCNY(_ amount: Decimal, currency: String) -> Decimal? {
        if currency == "CNY" { return amount }
        guard let rate = snapshot.rates[currency], rate > 0 else { return nil }
        return amount / Decimal(rate)
    }

    func refresh(force: Bool = false) async {
        guard autoUpdate else { return }
        if !force, let last = snapshot.fetchedAt, Date().timeIntervalSince(last) < 12 * 3600 { return }
        do {
            var req = URLRequest(url: Self.endpoint, timeoutInterval: 15)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            struct Reply: Decodable { let date: String; let rates: [String: Double] }
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            var rates = reply.rates
            rates["CNY"] = 1
            // 只接受包含我们支持的主要币种的结果，避免接口变化后写入残缺数据
            guard rates["USD"] != nil else { throw URLError(.cannotParseResponse) }
            snapshot = Snapshot(date: reply.date, rates: rates, online: true, fetchedAt: Date())
            UserDefaults.standard.set(try? JSONEncoder().encode(snapshot), forKey: Self.cacheKey)
            lastError = nil
        } catch {
            // 联网失败时继续使用当前汇率（缓存或内置），只记录原因
            lastError = error.localizedDescription
        }
    }

    var sourceText: String {
        snapshot.online ? "按 \(snapshot.date) 汇率（欧洲央行）" : "按内置 \(snapshot.date) 汇率"
    }
}
