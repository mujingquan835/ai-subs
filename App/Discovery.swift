import AppKit
import WidgetKit

/// 本机识别到的订阅账号信息（来自 AI 工具的本地登录文件）。不含价格：凭证里没有这项。
struct DetectedAccount: Hashable {
    var plan: String              // “Plus”“Pro”
    var email: String?
    var channel: String?          // “Apple App Store”“官网”
    var anchor: Date?             // 扣费锚点：续费日或开通日
    var anchorIsRenewal = false   // true 表示 anchor 是“本期到期 / 下次续费”日
}

struct DetectedAgent: Identifiable, Hashable {
    var id: String { serviceID }
    let serviceID: String
    var sources: [String]         // “Claude.app”“Claude Code 命令行”
    var account: DetectedAccount?
    var service: Service { ServiceCatalog.service(id: serviceID) ?? ServiceCatalog.custom(name: serviceID) }
    var title: String { account.map { "\(service.name.components(separatedBy: " /").first ?? service.name) \($0.plan)" } ?? service.name }
}

@MainActor final class Discovery: ObservableObject {
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) } }
    @Published var dismissed: Bool { didSet { UserDefaults.standard.set(dismissed, forKey: Self.dismissedKey) } }
    @Published private(set) var agents: [DetectedAgent] = []
    @Published private(set) var quotas: [AccountQuota] = QuotaFile.load()
    @Published private(set) var refreshing = false
    private static let enabledKey = "discoveryEnabled", dismissedKey = "discoveryDismissed"
    /// 目前能查额度的服务
    static let quotaServices: Set<String> = ["chatgpt", "claude"]
    /// 用于把手动添加的订阅也纳入额度查询
    weak var store: Store?
    private var timer: Timer?

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        dismissed = UserDefaults.standard.bool(forKey: Self.dismissedKey)
        if enabled { start() }
    }

    func allow() {
        enabled = true
        start()
        // 第一次允许时，如果还有工具没装好或没登录，直接打开设置向导
        let st = SetupStatus.check()
        if case .ready = st.claude, case .ready = st.codex {} else { showGuide = true }
    }

    func turnOff() {
        enabled = false
        timer?.invalidate(); timer = nil
        agents = []; quotas = []
        try? QuotaFile.save([])
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func start() {
        scan()
        Task { await refreshQuota() }
        timer?.invalidate()
        // 额度每 5 分钟更新一次；只读查询，不会消耗额度
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshQuota() }
        }
    }

    func quota(for serviceID: String) -> AccountQuota? { quotas.first { $0.id == serviceID } }

    /// 订阅行上的“获取额度”：还没授权时先走授权，之后直接刷新
    func requestQuota() {
        if enabled { Task { await refreshQuota() } } else { allow() }
    }

    /// 打开终端启动 Claude Code，用户输入 /login 用订阅账号登录后，钥匙串里就有可读的登录项
    func loginClaude() {
        do {
            try TerminalRunner.run(title: "登录 Claude Code",
                                   notes: ["1. 在下面的 Claude Code 输入框里输入 /login（前面有斜杠）并回车",
                                           "2. 选择 Claude account with subscription，在浏览器里授权",
                                           "3. 看到 Login successful 后输入 /exit 退出，回到 AI订阅管家点刷新"],
                                   command: SetupCommands.loginClaude)
        } catch {
            store?.error = "无法打开终端：\(error.localizedDescription)"
        }
    }

    /// 由各处的“设置向导…”打开
    @Published var showGuide = false

    // MARK: 扫描

    func scan() {
        agents = AgentScanner.scan()
    }

    // MARK: 额度

    func refreshQuota() async {
        guard enabled, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        // 本机识别到订阅的服务 + 手动添加的订阅里能查额度的服务
        var ids = Set(agents.filter { $0.account != nil }.map(\.serviceID))
        ids.formUnion(store?.items.map { $0.catalogService.id } ?? [])
        ids.formIntersection(Self.quotaServices)
        var result: [AccountQuota] = []
        for id in ids.sorted() {
            let name = agents.first { $0.serviceID == id && $0.account != nil }?.title
                ?? ServiceCatalog.service(id: id)?.name ?? id
            do {
                let windows = id == "chatgpt" ? try await QuotaFetcher.codex() : try await QuotaFetcher.claude()
                result.append(AccountQuota(id: id, name: name, windows: windows, fetchedAt: Date()))
            } catch {
                // 失败时保留上一次的窗口数据，只附上原因
                var old = quota(for: id) ?? AccountQuota(id: id, name: name, windows: [], fetchedAt: Date())
                old.error = error.localizedDescription
                if let e = error as? QuotaError {
                    switch e { case .notSignedIn, .expired: old.needsLogin = true; default: old.needsLogin = nil }
                }
                result.append(old)
            }
        }
        quotas = result
        try? QuotaFile.save(result)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - 本机扫描

enum AgentScanner {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private struct Rule { let service: String; let apps: [String]; let clis: [(String, String)]; let files: [(String, String)] }
    private static let rules: [Rule] = [
        Rule(service: "chatgpt", apps: ["ChatGPT.app", "ChatGPT Classic.app", "Codex.app"], clis: [("codex", "Codex 命令行")], files: [(".codex/auth.json", "Codex 登录")]),
        Rule(service: "claude", apps: ["Claude.app"], clis: [("claude", "Claude Code 命令行")], files: [(".claude.json", "Claude Code 登录")]),
        Rule(service: "gemini", apps: ["Gemini.app"], clis: [("gemini", "Gemini CLI")], files: [(".gemini/oauth_creds.json", "Gemini CLI 登录")]),
        Rule(service: "copilot", apps: ["GitHub Copilot.app"], clis: [("copilot", "Copilot CLI")], files: []),
        Rule(service: "cursor", apps: ["Cursor.app"], clis: [("cursor-agent", "Cursor CLI")], files: []),
        Rule(service: "perplexity", apps: ["Perplexity.app"], clis: [], files: []),
        Rule(service: "grok", apps: ["Grok.app"], clis: [], files: []),
        Rule(service: "deepseek", apps: ["DeepSeek.app"], clis: [], files: []),
        Rule(service: "doubao", apps: ["Doubao.app", "豆包.app"], clis: [], files: []),
        Rule(service: "kimi", apps: ["Kimi.app"], clis: [("kimi", "Kimi CLI")], files: []),
        Rule(service: "tongyi", apps: ["Qwen.app", "通义.app"], clis: [("qwen", "Qwen Code")], files: []),
        Rule(service: "yuanbao", apps: ["Yuanbao.app", "元宝.app", "腾讯元宝.app"], clis: [], files: []),
        Rule(service: "jimeng", apps: ["Jimeng.app", "即梦.app"], clis: [], files: []),
    ]

    static func scan() -> [DetectedAgent] {
        rules.compactMap { r in
            var sources: [String] = []
            for app in r.apps where appExists(app) { sources.append(app.replacingOccurrences(of: ".app", with: "") + " App") }
            for (cli, label) in r.clis where cliExists(cli) { sources.append(label) }
            for (file, label) in r.files where FileManager.default.fileExists(atPath: home.appending(path: file).path) { sources.append(label) }
            guard !sources.isEmpty else { return nil }
            let account: DetectedAccount? = switch r.service {
                case "chatgpt": codexAccount()
                case "claude": claudeAccount()
                default: nil
            }
            return DetectedAgent(serviceID: r.service, sources: sources, account: account)
        }
    }

    private static func appExists(_ name: String) -> Bool {
        ["/Applications", home.appending(path: "Applications").path].contains { FileManager.default.fileExists(atPath: "\($0)/\(name)") }
    }

    private static func cliExists(_ name: String) -> Bool { cliPath(name) != nil }

    /// 从 Finder 打开的 App 拿不到终端的 PATH，所以逐个检查常见安装位置
    static func cliPath(_ name: String) -> String? {
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "\(home.path)/.local/bin", "\(home.path)/.bun/bin", "\(home.path)/.npm-global/bin", "\(home.path)/.claude/local"]
        let nvm = home.appending(path: ".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm.path) {
            dirs += versions.map { nvm.appending(path: "\($0)/bin").path }
        }
        return dirs.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // ChatGPT / Codex：~/.codex/auth.json 里 id_token 的声明带有档位与本期订阅起止日期
    static func codexAccount() -> DetectedAccount? {
        guard let json = readJSON(".codex/auth.json"),
              let tokens = json["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String,
              let claims = jwtClaims(idToken),
              let auth = claims["https://api.openai.com/auth"] as? [String: Any],
              let plan = auth["chatgpt_plan_type"] as? String, plan != "free" else { return nil }
        let until = (auth["chatgpt_subscription_active_until"] as? String).flatMap(parseDate)
        return DetectedAccount(plan: plan.capitalized, email: claims["email"] as? String, channel: nil, anchor: until, anchorIsRenewal: until != nil)
    }

    // Claude：~/.claude.json 的 oauthAccount 带有组织类型、计费方式和开通时间
    static func claudeAccount() -> DetectedAccount? {
        guard let json = readJSON(".claude.json"), let acct = json["oauthAccount"] as? [String: Any] else { return nil }
        let org = (acct["organizationType"] as? String) ?? ""
        let tier = (acct["userRateLimitTier"] as? String) ?? (acct["organizationRateLimitTier"] as? String) ?? ""
        let plan: String
        if org.contains("max") || tier.contains("max") { plan = tier.contains("20x") ? "Max 20x" : tier.contains("5x") ? "Max 5x" : "Max" }
        else if org.contains("pro") { plan = "Pro" }
        else if org.contains("team") || org.contains("enterprise") { plan = org.contains("team") ? "Team" : "Enterprise" }
        else { return nil }
        let billing = (acct["billingType"] as? String) ?? ""
        let channel = billing.contains("apple") ? "Apple App Store" : billing.contains("google") ? "Google Play" : billing.contains("stripe") ? "官网" : nil
        let created = (acct["subscriptionCreatedAt"] as? String).flatMap(parseDate)
        return DetectedAccount(plan: plan, email: acct["emailAddress"] as? String, channel: channel, anchor: created)
    }

    static func readJSON(_ path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: home.appending(path: path)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 只解码 JWT 的声明部分，不校验签名：这里只用来读档位，不用于鉴权
    static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var s = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        guard let data = Data(base64Encoded: s) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - 额度查询（只读）

enum QuotaError: LocalizedError {
    case notSignedIn(String), expired(String), http(Int), format
    var errorDescription: String? {
        switch self {
        case .notSignedIn(let app): "\(app) 没有用订阅账号登录"
        case .expired(let app): "登录已过期，打开 \(app) 用一次即可刷新"
        case .http(let code): code == 401 || code == 403 ? "登录已失效，请在原工具里重新登录" : "服务器返回 \(code)"
        case .format: "返回格式无法识别，接口可能已变更"
        }
    }
}

enum QuotaFetcher {
    /// Codex：与 Codex 自己的 /status 同源的 wham/usage 接口。primary 为 5 小时窗口，secondary 为周窗口。
    /// 不刷新令牌：刷新会让 Codex 本身的登录失效。
    static func codex() async throws -> [QuotaWindow] {
        guard let json = AgentScanner.readJSON(".codex/auth.json"), let tokens = json["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String else { throw QuotaError.notSignedIn("Codex") }
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!, timeoutInterval: 20)
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        if let account = tokens["account_id"] as? String { req.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        req.setValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
        let body = try await get(req)
        guard let limit = body["rate_limit"] as? [String: Any] else { throw QuotaError.format }
        let windows = ["primary_window", "secondary_window"].compactMap { key -> QuotaWindow? in
            guard let w = limit[key] as? [String: Any], let used = number(w["used_percent"]) else { return nil }
            let span = number(w["limit_window_seconds"]) ?? 0
            let reset = number(w["reset_at"]).map { Date(timeIntervalSince1970: $0) }
                ?? number(w["reset_after_seconds"]).map { Date().addingTimeInterval($0) }
            return QuotaWindow(label: label(span: span), usedPercent: used, resetsAt: reset, spanSeconds: span)
        }
        if windows.isEmpty { throw QuotaError.format }
        return windows
    }

    /// Claude：Claude Code 的 /usage 所用的 oauth/usage 接口。令牌由系统 security 工具从钥匙串读取（与 Claude Code 相同）。
    static func claude() async throws -> [QuotaWindow] {
        guard let raw = keychainPassword(service: "Claude Code-credentials"),
              let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String else { throw QuotaError.notSignedIn("Claude Code") }
        if let exp = number(oauth["expiresAt"]), Date(timeIntervalSince1970: exp / 1000) < Date() { throw QuotaError.expired("Claude Code") }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 20)
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let body = try await get(req)
        let windows = [("five_hour", 5 * 3600.0), ("seven_day", 7 * 86400.0)].compactMap { key, span -> QuotaWindow? in
            guard let w = body[key] as? [String: Any], let used = number(w["utilization"]) else { return nil }
            let reset = (w["resets_at"] as? String).flatMap(AgentScanner.parseDate)
            return QuotaWindow(label: label(span: span), usedPercent: used, resetsAt: reset, spanSeconds: span)
        }
        if windows.isEmpty { throw QuotaError.format }
        return windows
    }

    struct ClaudeSignIn { let plan: String; let expired: Bool }

    /// 钥匙串里有没有 Claude Code 的订阅登录（只看字段，不联网）
    static func claudeSignIn() -> ClaudeSignIn? {
        guard let raw = keychainPassword(service: "Claude Code-credentials"),
              let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any], oauth["accessToken"] is String else { return nil }
        let expired = number(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) < Date() } ?? false
        let plan = (oauth["subscriptionType"] as? String).map { $0 == "max" ? "Max" : $0.capitalized } ?? "订阅"
        return ClaudeSignIn(plan: plan, expired: expired)
    }

    private static func label(span: Double) -> String {
        switch span { case 18000: "5 小时"; case 604800: "本周"; case 86400: "今日"; default: span >= 86400 ? "\(Int(span / 86400)) 天" : "\(Int(span / 3600)) 小时" }
    }

    private static func get(_ req: URLRequest) async throws -> [String: Any] {
        var req = req
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 { throw QuotaError.http(code) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QuotaError.format }
        return obj
    }

    private static func number(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap(Double.init) }

    private static func keychainPassword(service: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", service, "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
