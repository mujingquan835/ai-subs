import SwiftUI
import WidgetKit

@main struct SubscriptionApp: App {
    @StateObject var store = Store()
    @StateObject var discovery = Discovery()
    var body: some Scene {
        WindowGroup("AI 订阅管家") {
            ContentView()
                .environmentObject(store)
                .environmentObject(discovery)
                .onAppear {
                    store.onSave = { WidgetCenter.shared.reloadAllTimelines() }
                    WidgetCenter.shared.reloadAllTimelines()
                }
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 900, height: 680)
        .windowToolbarStyle(.unified)
    }
}

/// 打开编辑器的方式：新增（可带预选服务）或编辑已有记录。
enum EditorRoute: Identifiable {
    case new(Service?)
    case edit(Subscription)
    case prefill(Subscription)   // 本机识别导入：已填好服务、档位和日期，待确认金额
    case guide                   // 设置向导（与表单共用一个弹出面板：macOS 上同一页面挂两个 sheet 会失效）
    var id: String {
        switch self {
        case .new(let s): "new-\(s?.id ?? "")"
        case .edit(let item): item.id.uuidString
        case .prefill(let item): "prefill-\(item.id.uuidString)"
        case .guide: "guide"
        }
    }
}
