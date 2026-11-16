import SwiftUI

/// 快捷录入用的服务目录。图标为本地绘制的“色块＋字母”占位，不使用品牌素材。
struct Service: Identifiable, Hashable {
    enum Group: String, CaseIterable { case global = "国际服务", domestic = "国内服务" }
    let id: String
    let name: String
    let mark: String
    let group: Group
    let hex: UInt32
    var tint: Color { Color(hex: hex) }
    /// 目录内的服务都带有官方图标（见 Resources/ICON_SOURCES.md），自定义项目没有
    var hasLogo: Bool { id != "custom" }
}

enum ServiceCatalog {
    static let all: [Service] = [
        .init(id: "chatgpt", name: "ChatGPT / Codex", mark: "G", group: .global, hex: 0x10A37F),
        .init(id: "claude", name: "Claude", mark: "C", group: .global, hex: 0xD97757),
        .init(id: "gemini", name: "Gemini", mark: "G", group: .global, hex: 0x4285F4),
        .init(id: "cursor", name: "Cursor", mark: "Cu", group: .global, hex: 0x2B2B2E),
        .init(id: "copilot", name: "GitHub Copilot", mark: "Co", group: .global, hex: 0x6E40C9),
        .init(id: "perplexity", name: "Perplexity", mark: "P", group: .global, hex: 0x20808D),
        .init(id: "grok", name: "Grok", mark: "X", group: .global, hex: 0x3A3A3C),
        .init(id: "midjourney", name: "Midjourney", mark: "M", group: .global, hex: 0x4B4FD1),
        .init(id: "runway", name: "Runway", mark: "R", group: .global, hex: 0x7A5AF8),
        .init(id: "elevenlabs", name: "ElevenLabs", mark: "11", group: .global, hex: 0x1F1F22),
        .init(id: "deepseek", name: "DeepSeek", mark: "D", group: .domestic, hex: 0x4D6BFE),
        .init(id: "doubao", name: "豆包", mark: "豆", group: .domestic, hex: 0x3C7BF6),
        .init(id: "tongyi", name: "通义千问", mark: "通", group: .domestic, hex: 0x615CED),
        .init(id: "kimi", name: "Kimi", mark: "K", group: .domestic, hex: 0x1C1C1E),
        .init(id: "zhipu", name: "智谱", mark: "智", group: .domestic, hex: 0x2E5BFF),
        .init(id: "wenxin", name: "文心", mark: "文", group: .domestic, hex: 0x2932E1),
        .init(id: "jimeng", name: "即梦", mark: "即", group: .domestic, hex: 0x00A896),
        .init(id: "kling", name: "可灵", mark: "可", group: .domestic, hex: 0xF0660A),
        .init(id: "yuanbao", name: "腾讯元宝", mark: "元", group: .domestic, hex: 0x00B96B),
    ]
    static let popular = ["chatgpt", "claude", "gemini", "cursor", "deepseek", "doubao"].compactMap(service(id:))

    static func service(id: String?) -> Service? { all.first { $0.id == id } }
    static func match(name: String) -> Service? { all.first { $0.name == name } }

    /// 自定义项目的占位图标：取首字，颜色由名称稳定生成。
    static func custom(name: String) -> Service {
        let palette: [UInt32] = [0x5E5CE6, 0x0A84FF, 0x30B0C7, 0x34C759, 0xFF9F0A, 0xFF375F, 0xBF5AF2, 0x8E8E93]
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let mark = name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
        return Service(id: "custom", name: name, mark: mark, group: .global, hex: palette[sum % palette.count])
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
