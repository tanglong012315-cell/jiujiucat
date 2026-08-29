import SwiftUI
import UIKit

// Web 的总资产走势图是手绘 canvas，不是图表库画的：曲线下方铺一层**点阵**，
// 区间最高值标在它自己的位置上方。Swift Charts 做不出这两样，所以这里同样自绘。
// 数值对照 `app.js` 的 `drawMiniSparkline` / `drawPortfolioChartDetail`。

/// `chartScale`：按数据跨度上下各留一段空白，返回「值 → y」的映射。
struct PawChartScale {
    private let top: CGFloat
    private let bottom: CGFloat
    private let low: Double
    private let high: Double
    private let isFlat: Bool

    init(values: [Double], top: CGFloat, bottom: CGFloat, padLow: Double = 0.30, padHigh: Double = 0.12) {
        self.top = top
        self.bottom = bottom

        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let span = maximum - minimum

        if span > 0 {
            low = minimum - span * padLow
            high = maximum + span * padHigh
            isFlat = false
        } else {
            low = 0
            high = 1
            isFlat = true
        }
    }

    func y(_ value: Double) -> CGFloat {
        // 一条水平线的数据没有跨度可言，Web 把它摆在 42% 的位置。
        guard !isFlat else { return top + (bottom - top) * 0.42 }
        return bottom - CGFloat((value - low) / (high - low)) * (bottom - top)
    }
}

enum PawChartCanvas {
    /// `fillDotMatrix`：从底边往上、每隔 `step` 画一颗 `size` 见方的点，直到曲线高度。
    static func fillDotMatrix(
        context: GraphicsContext,
        color: Color,
        left: CGFloat,
        right: CGFloat,
        bottom: CGFloat,
        step: CGFloat,
        size: CGFloat,
        opacity: Double,
        columnTop: (CGFloat) -> CGFloat
    ) {
        guard step > 0, right > left else { return }

        var path = Path()
        var x = left
        while x <= right {
            let top = max(0, columnTop(x))
            if top.isFinite {
                var y = bottom
                while y > top {
                    path.addRect(CGRect(x: x, y: y, width: size, height: size))
                    y -= step
                }
            }
            x += step
        }

        context.fill(path, with: .color(color.opacity(opacity)))
    }

    /// `columnHeightFn`：把采样点线性插值成「某个像素列上的曲线高度」。
    static func columnTop(
        values: [Double],
        scale: PawChartScale,
        left: CGFloat,
        right: CGFloat
    ) -> (CGFloat) -> CGFloat {
        let inner = right - left
        return { x in
            guard values.count > 1 else { return scale.y(values.first ?? 0) }
            let t = inner > 0 ? Double((x - left) / inner) * Double(values.count - 1) : 0
            let index = max(0, min(values.count - 2, Int(t.rounded(.down))))
            let fraction = t - Double(index)
            return scale.y(values[index]) * (1 - fraction) + scale.y(values[index + 1]) * fraction
        }
    }

    static func linePath(
        values: [Double],
        scale: PawChartScale,
        left: CGFloat,
        right: CGFloat
    ) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }

        for index in values.indices {
            let x = left + CGFloat(Double(index) / Double(values.count - 1)) * (right - left)
            let point = CGPoint(x: x, y: scale.y(values[index]))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Web `.portfolio-sparkline`：收起态里跟在总资产右边的迷你曲线，72 高。
struct PawSparkline: View {
    let values: [Double]
    let tone: Color

    private let padding: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            let left = padding
            let right = size.width - padding
            let bottom = size.height - padding

            guard values.count >= 2, right > left else {
                // 没有数据时 Web 画一条 35% 的中线占位。
                var line = Path()
                line.move(to: CGPoint(x: left, y: size.height / 2))
                line.addLine(to: CGPoint(x: right, y: size.height / 2))
                context.stroke(
                    line,
                    with: .color(tone.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
                return
            }

            let scale = PawChartScale(
                values: values, top: padding, bottom: bottom, padLow: 0.26, padHigh: 0.10
            )

            PawChartCanvas.fillDotMatrix(
                context: context, color: tone,
                left: left, right: right, bottom: bottom,
                step: 4, size: 1.1, opacity: 0.30,
                columnTop: PawChartCanvas.columnTop(values: values, scale: scale, left: left, right: right)
            )

            context.stroke(
                PawChartCanvas.linePath(values: values, scale: scale, left: left, right: right),
                with: .color(tone),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: 72)
        .accessibilityHidden(true)
    }
}

/// Web `#pf-chart`：展开后的大图，188 高，曲线下方铺点阵，区间最高值标在自己位置上方。
struct PawPortfolioChart: View {
    let values: [Double]
    let tone: Color
    /// 峰值标注的文案由调用方格式化，保持和别处同一套金额写法。
    let peakLabel: (Double) -> String
    @Binding var scrubIndex: Int?
    /// 画布高度。投资组合是 188，计算页的预测图矮一些。
    var height: CGFloat = 188

    @State private var haptics = UISelectionFeedbackGenerator()
    @State private var lastHapticTime: TimeInterval = 0

    private let padTop: CGFloat = 18
    private let padSide: CGFloat = 6
    private let padBottom: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
            guard values.count >= 2 else { return }

            let left = padSide
            let right = size.width - padSide
            let bottom = size.height - padBottom
            guard right > left else { return }

            let scale = PawChartScale(values: values, top: padTop, bottom: bottom)

            let cursorIndex = scrubIndex.map { $0.clamped(to: 0...(values.count - 1)) }
            let cursorX = cursorIndex.map {
                left + CGFloat(Double($0) / Double(values.count - 1)) * (right - left)
            }
            let passes: [(CGFloat, CGFloat, Double)] = cursorX.map {
                [(left, $0, 1), ($0, right, 0.32)]
            } ?? [(left, right, 1)]

            for (from, to, opacity) in passes where to - from >= 0.5 {
                var clipped = context
                clipped.clip(to: Path(CGRect(x: from, y: 0, width: to - from, height: size.height)))

                PawChartCanvas.fillDotMatrix(
                    context: clipped, color: tone,
                    left: left, right: right, bottom: bottom,
                    step: 6, size: 1.4, opacity: opacity * 0.34,
                    columnTop: PawChartCanvas.columnTop(values: values, scale: scale, left: left, right: right)
                )

                clipped.stroke(
                    PawChartCanvas.linePath(values: values, scale: scale, left: left, right: right),
                    with: .color(tone.opacity(opacity)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }

            // 区间最高值标在它自己的位置上方。不写「最高」二字——点在哪儿本身
            // 就说明了是哪个时刻。
            guard let peakIndex = values.indices.max(by: { values[$0] < values[$1] }) else { return }
            let peakX = left + CGFloat(Double(peakIndex) / Double(values.count - 1)) * (right - left)
            let text = context.resolve(
                Text(peakLabel(values[peakIndex]))
                    .font(PawFont.inter(11))
                    .foregroundStyle(PawTheme.ink40)
            )
            let textSize = text.measure(in: size)
            let half = textSize.width / 2 + 2
            context.draw(
                text,
                at: CGPoint(
                    x: min(max(peakX, left + half), right - half),
                    y: max(12, scale.y(values[peakIndex]) - 8)
                ),
                anchor: .bottom
            )

            if let cursorIndex, let cursorX {
                let cursorY = scale.y(values[cursorIndex])
                var cursor = Path()
                cursor.move(to: CGPoint(x: cursorX, y: 0))
                cursor.addLine(to: CGPoint(x: cursorX, y: bottom))
                context.stroke(
                    cursor,
                    with: .color(PawTheme.ink40),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )

                context.fill(
                    Path(ellipseIn: CGRect(x: cursorX - 4.5, y: cursorY - 4.5, width: 9, height: 9)),
                    with: .color(PawTheme.bg1)
                )
                context.stroke(
                    Path(ellipseIn: CGRect(x: cursorX - 4.5, y: cursorY - 4.5, width: 9, height: 9)),
                    with: .color(tone),
                    lineWidth: 2.5
                )
            }
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture(width: geometry.size.width))
        }
        .frame(height: height)
        .onAppear { haptics.prepare() }
        .onChange(of: values.count) { _, _ in scrubIndex = nil }
        .accessibilityLabel("总资产走势图，长按后左右滑动可查看历史数值")
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.18, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { phase in
                guard case let .second(true, drag?) = phase else { return }
                updateScrubIndex(at: drag.location.x, width: width)
            }
            .onEnded { _ in scrubIndex = nil }
    }

    private func updateScrubIndex(at x: CGFloat, width: CGFloat) {
        guard values.count >= 2 else { return }
        let inner = max(width - padSide * 2, 1)
        let ratio = ((x - padSide) / inner).clamped(to: 0...1)
        let next = Int((ratio * CGFloat(values.count - 1)).rounded())
        guard next != scrubIndex else { return }
        scrubIndex = next
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastHapticTime >= 0.045 {
            haptics.selectionChanged()
            haptics.prepare()
            lastHapticTime = now
        }
    }
}
