import AppIntents
import SwiftUI
import WidgetKit

/// 小组件背景，在桌面右键小组件 →“编辑”里切换。
enum WidgetBackground: String, AppEnum {
    case white, glass

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "背景" }
    static var caseDisplayRepresentations: [WidgetBackground: DisplayRepresentation] {
        [.white: "纯白", .glass: "玻璃"]
    }
}

struct StyleIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "小组件样式" }
    static var description: IntentDescription { IntentDescription("选择小组件的背景") }

    @Parameter(title: "背景", default: .white)
    var background: WidgetBackground

    init() {}
}

extension View {
    @ViewBuilder func widgetBackground(_ style: WidgetBackground) -> some View {
        switch style {
        case .white:
            // 浅色纯白，深色用接近系统深色面板的近黑
            containerBackground(for: .widget) { Color(nsColor: .widgetWhite) }
        case .glass:
            containerBackground(for: .widget) {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    // 顶部一道淡淡的高光，模拟玻璃的反光边缘
                    LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0)], startPoint: .top, endPoint: .center)
                }
            }
        }
    }
}

extension NSColor {
    static let widgetWhite = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.12, alpha: 1) : .white
    }
}
