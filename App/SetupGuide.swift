import AppKit
import Combine
import SwiftUI

// MARK: - 状态检测

/// 设置向导里每个工具的状态，全部在本机检测，不联网。
struct SetupStatus: Equatable {
    enum Tool: Equatable {
        case notInstalled
        case notSignedIn
        case expired
        case freePlan            // 已登录但没有订阅，没有额度可查
        case ready(String)       // 已登录，附带档位，例如 “ChatGPT Plus”
    }
    var codex: Tool = .notInstalled
    var claude: Tool = .notInstalled
    var hasNPM = false
    var hasBrew = false

    static func check() -> SetupStatus {
        #if DEBUG
        // 仅调试：模拟一台什么都没装的电脑，用来检查向导的提示和按钮
        switch ProcessInfo.processInfo.environment["AISUB_FAKE_SETUP"] {
        case "fresh": return SetupStatus(codex: .notInstalled, claude: .notInstalled, hasNPM: true)
        case "login": return SetupStatus(codex: .notSignedIn, claude: .notSignedIn, hasNPM: true)
        default: break
        }
        #endif
        var s = SetupStatus()
        s.hasNPM = AgentScanner.cliPath("npm") != nil
        s.hasBrew = AgentScanner.cliPath("brew") != nil

        // Codex：命令行或 ChatGPT / Codex 桌面 App 任一存在即可；登录信息在 ~/.codex/auth.json
        let codexInstalled = AgentScanner.cliPath("codex") != nil
            || ["ChatGPT.app", "Codex.app"].contains { FileManager.default.fileExists(atPath: "/Applications/\($0)") }
        if let account = AgentScanner.codexAccount() {
            s.codex = .ready("ChatGPT \(account.plan)")
        } else if AgentScanner.readJSON(".codex/auth.json")?["tokens"] != nil {
            s.codex = .freePlan
        } else {
            s.codex = codexInstalled ? .notSignedIn : .notInstalled
        }

        // Claude Code：只有终端里的 Claude Code 会把订阅登录写进钥匙串，Claude 桌面 App 的登录读不到
        if AgentScanner.cliPath("claude") == nil {
            s.claude = .notInstalled
        } else {
            switch QuotaFetcher.claudeSignIn() {
            case .none: s.claude = .notSignedIn
            case .some(let info) where info.expired: s.claude = .expired
            case .some(let info): s.claude = .ready("Claude \(info.plan)")
            }
        }
        return s
    }
}

// MARK: - 在终端运行命令

enum TerminalRunner {
    /// 写一个 .command 文件交给“终端”打开：不需要“自动化”权限，命令在用户自己的 shell 里运行，能用到 nvm、Homebrew 的 PATH。
    static func run(title: String, notes: [String], command: String, keepOpen: Bool = true) throws {
        var lines = ["#!/bin/zsh", "clear", "echo \"【\(title)】\""]
        lines += notes.map { "echo \"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
        lines += ["echo", "echo \"$ \(command.replacingOccurrences(of: "\"", with: "\\\""))\"", "echo", command]
        if keepOpen {
            lines += ["echo", "echo \"完成后可以关闭这个窗口，回到 AI订阅管家，它会自动重新检测。\""]
        }
        let safeName = title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appending(path: "\(safeName).command")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }
}

/// 向导里用到的命令。只用官方渠道：npm 包或 Homebrew，Claude Code 另有官方安装脚本。
enum SetupCommands {
    static func installClaude(_ s: SetupStatus) -> String {
        s.hasNPM ? "npm install -g @anthropic-ai/claude-code" : "curl -fsSL https://claude.ai/install.sh | bash"
    }
    static let loginClaude = "claude"
    static func installCodex(_ s: SetupStatus) -> String? {
        if s.hasNPM { return "npm install -g @openai/codex" }
        if s.hasBrew { return "brew install --cask codex" }
        return nil
    }
    static let loginCodex = "codex login"
}

// MARK: - 向导界面

struct SetupGuideView: View {
    @EnvironmentObject var discovery: Discovery
    @Environment(\.dismiss) private var dismiss
    @State private var status = SetupStatus.check()
    @State private var error: String?
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("设置向导").font(.title2.weight(.semibold))
                Text("按顺序完成以下几步，就能自动识别订阅，并显示 5 小时和每周额度。只想记账提醒的话，可以跳过。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            ScrollView {
                VStack(spacing: 12) {
                    StepCard(number: 1, title: "允许读取本机登录信息", done: discovery.enabled,
                             detail: discovery.enabled ? "已允许。只在本机读取，查询额度时只连接 OpenAI 与 Anthropic 官方服务器。"
                                                       : "读取 Codex、Claude Code 的本地登录信息来识别订阅档位和额度，不上传到其他地方。") {
                        if !discovery.enabled { Button("允许") { discovery.allow() }.buttonStyle(.borderedProminent) }
                    }

                    StepCard(number: 2, title: "Codex（ChatGPT 订阅）", done: isReady(status.codex),
                             detail: codexDetail) { codexActions }

                    StepCard(number: 3, title: "Claude Code（Claude 订阅）", done: isReady(status.claude),
                             detail: claudeDetail) { claudeActions }

                    StepCard(number: 4, title: "添加桌面小组件（可选）", done: false, optional: true,
                             detail: "在桌面空白处右键 →“编辑小组件”，搜索“AI订阅管家”，把“即将扣费”的中号或大号拖到桌面。") { EmptyView() }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            Divider()
            HStack {
                Button("重新检测") { recheck() }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(16)
            .background(.bar)
        }
        .frame(width: 600, height: 640)
        .onReceive(timer) { _ in recheck() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in recheck() }
    }

    private func recheck() {
        let new = SetupStatus.check()
        if new != status {
            status = new
            // 有新的登录就立刻刷新识别结果和额度
            discovery.scan()
            Task { await discovery.refreshQuota() }
        }
    }

    private func isReady(_ t: SetupStatus.Tool) -> Bool { if case .ready = t { return true } else { return false } }

    private func run(_ title: String, _ notes: [String], _ command: String) {
        do { try TerminalRunner.run(title: title, notes: notes, command: command); error = nil }
        catch { self.error = "无法打开终端：\(error.localizedDescription)" }
    }

    // MARK: Codex

    private var codexDetail: String {
        switch status.codex {
        case .notInstalled: "没有找到 Codex。安装后用 ChatGPT 账号登录一次。"
        case .notSignedIn: "已安装，还没有登录。点“登录 Codex”，在浏览器里用 ChatGPT 账号授权。"
        case .expired: "登录已过期，重新登录一次即可。"
        case .freePlan: "已登录，但这个 ChatGPT 账号没有付费订阅，没有额度可查。"
        case .ready(let plan): "已登录 \(plan)，可以查看额度。"
        }
    }

    @ViewBuilder private var codexActions: some View {
        switch status.codex {
        case .notInstalled:
            if let cmd = SetupCommands.installCodex(status) {
                CommandAction(label: "安装 Codex", command: cmd) {
                    run("安装 Codex", ["正在安装 Codex 命令行，装好后回到 AI订阅管家点“登录 Codex”。"], cmd)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("需要先安装 Node.js（自带 npm），然后回来点“重新检测”。").font(.callout).foregroundStyle(.secondary)
                    Link("打开 Node.js 官网", destination: URL(string: "https://nodejs.org/zh-cn/download")!)
                }
            }
        case .notSignedIn, .expired, .freePlan:
            CommandAction(label: "登录 Codex", command: SetupCommands.loginCodex) {
                run("登录 Codex", ["浏览器会打开 ChatGPT 登录页，授权后回到 AI订阅管家即可。"], SetupCommands.loginCodex)
            }
        case .ready:
            EmptyView()
        }
    }

    // MARK: Claude

    private var claudeDetail: String {
        switch status.claude {
        case .notInstalled: "没有找到终端版 Claude Code。注意：Claude 桌面 App 的登录无法读取，需要装终端版并登录一次。"
        case .notSignedIn: "已安装，还没有用 Claude 订阅账号登录。点“登录 Claude”，在打开的 Claude Code 里输入 /login。"
        case .expired: "登录已过期。Claude Code 平时走其他模型时不会自动续期，重新 /login 一次即可。"
        case .freePlan: "已登录，但没有订阅。"
        case .ready(let plan): "已登录 \(plan)，可以查看额度。"
        }
    }

    @ViewBuilder private var claudeActions: some View {
        switch status.claude {
        case .notInstalled:
            let cmd = SetupCommands.installClaude(status)
            CommandAction(label: "安装 Claude Code", command: cmd) {
                run("安装 Claude Code", ["正在安装终端版 Claude Code，装好后回到 AI订阅管家点“登录 Claude”。"], cmd)
            }
        case .notSignedIn, .expired, .freePlan:
            VStack(alignment: .leading, spacing: 8) {
                CommandAction(label: "登录 Claude", command: SetupCommands.loginClaude) {
                    run("登录 Claude Code", ["1. 在下面的 Claude Code 输入框里输入 /login（前面有斜杠）并回车",
                                             "2. 选择 Claude account with subscription，在浏览器里授权",
                                             "3. 看到 Login successful 后输入 /exit 退出"], SetupCommands.loginClaude)
                }
                Text("用第三方模型的 Claude Code 也可以登录，不会影响原来的模型设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .ready:
            EmptyView()
        }
    }
}

/// 一步：左边序号或对勾，中间标题和说明，下面是操作
private struct StepCard<Actions: View>: View {
    let number: Int
    let title: String
    let done: Bool
    var optional = false
    let detail: String
    @ViewBuilder var actions: Actions

    var body: some View {
        Card(padding: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    if done {
                        Circle().fill(Color.green)
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.2)
                        Text("\(number)").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 26, height: 26)
                .animation(.snappy, value: done)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline)
                        if optional { Text("可选").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 1).background(Color.primary.opacity(0.06), in: Capsule()) }
                    }
                    Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    actions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 一个“在终端运行”按钮，旁边展示命令本身，可复制
private struct CommandAction: View {
    let label: String
    let command: String
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) { Label(label, systemImage: "terminal") }
                .buttonStyle(.borderedProminent)
            HStack(spacing: 6) {
                Text(command).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("复制命令")
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
