import SwiftUI
import AppKit

/// 服务图标，App 与小组件共用：有官方图标时白底显示，否则用首字色块。
struct ServiceIcon: View {
    let service: Service
    var size: CGFloat = 36
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Group {
            if service.hasLogo {
                // 官方图标：白底圆角，和 macOS App 图标一致，深色模式下也保持白底以保证黑色标志可见。
                // 用 SwiftUI 按名称加载资源目录里的图片：小组件里只有这种写法能可靠显示
                shape.fill(.white)
                    .overlay { Image("svc-\(service.id)").resizable().interpolation(.high).scaledToFit().padding(size * 0.18) }
            } else {
                shape.fill(LinearGradient(colors: [service.tint.opacity(0.88), service.tint], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        Text(service.mark)
                            .font(.system(size: size * (service.mark.count > 1 ? 0.36 : 0.46), weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6)
                    }
            }
        }
            .overlay(shape.strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }
}

