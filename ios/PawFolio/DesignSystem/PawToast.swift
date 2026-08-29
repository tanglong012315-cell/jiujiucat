import SwiftUI

/// Web `.toast`：贴在底部导航上方的一枚药丸，`--ink-80` 底配 `--bg-1` 字，
/// 2.4 秒后淡出。Web 里有 33 处调用，是主要的操作反馈机制。
@MainActor
final class PawToastCenter: ObservableObject {
    static let shared = PawToastCenter()

    @Published private(set) var message: String?

    private var dismissTask: Task<Void, Never>?

    func show(_ message: String) {
        self.message = message
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2_400))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}

private struct PawToastOverlay: ViewModifier {
    @ObservedObject private var center = PawToastCenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = center.message {
                Text(message)
                    .font(PawFont.inter(13, weight: .medium))
                    .foregroundStyle(PawTheme.bg1)
                    .lineLimit(1)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(PawTheme.ink80, in: Capsule())
                    // Web 把它放在贴底导航上方 80pt 处。
                    .padding(.bottom, 80)
                    // 进场从下方推上来并轻微放大，出场只是淡掉、不再往下掉：
                    // 反馈出现时值得被看见，消失时不该再吸引一次注意。
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: 12)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.96)),
                            removal: .opacity
                        )
                    )
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(center.message == nil ? PawMotion.disappear : PawMotion.appear, value: center.message)
    }
}

extension View {
    /// 挂一次即可，全 App 共用同一个 toast 出口。
    func pawToast() -> some View {
        modifier(PawToastOverlay())
    }
}
