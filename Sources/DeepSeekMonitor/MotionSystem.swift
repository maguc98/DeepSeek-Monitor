import SwiftUI

enum DSMotion {
    static let page = Animation.spring(response: 0.42, dampingFraction: 0.90)
    static let selection = Animation.spring(response: 0.30, dampingFraction: 0.78)
    static let data = Animation.spring(response: 0.56, dampingFraction: 0.88)
    static let entrance = Animation.spring(response: 0.52, dampingFraction: 0.88)
}

struct DSGlobalButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .opacity(configuration.isPressed && !reduceMotion ? 0.84 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.10) : .spring(response: 0.24, dampingFraction: 0.62),
                value: configuration.isPressed
            )
    }
}

struct DSEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didAppear = false
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(didAppear || reduceMotion ? 1 : 0)
            .offset(y: didAppear || reduceMotion ? 0 : 11)
            .scaleEffect(didAppear || reduceMotion ? 1 : 0.99)
            .onAppear {
                guard !reduceMotion else {
                    didAppear = true
                    return
                }
                withAnimation(DSMotion.entrance.delay(delay)) {
                    didAppear = true
                }
            }
            .onChange(of: reduceMotion) { _, shouldReduce in
                if shouldReduce { didAppear = true }
            }
    }
}

extension View {
    func dsEntrance(delay: Double = 0) -> some View {
        modifier(DSEntranceModifier(delay: delay))
    }
}


/// Reveals a chart from left to right while keeping the chart's own layout intact.
struct DSChartRevealModifier: ViewModifier {
    @Environment(\\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    let key: String

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { geometry in
                    Rectangle()
                        .frame(width: max(1, geometry.size.width * progress))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
            .onAppear(perform: replay)
            .onChange(of: key) { _, _ in replay() }
            .onChange(of: reduceMotion) { _, shouldReduce in
                if shouldReduce { progress = 1 }
            }
    }

    private func replay() {
        guard !reduceMotion else {
            progress = 1
            return
        }
        progress = 0
        withAnimation(.easeOut(duration: 0.86)) {
            progress = 1
        }
    }
}

/// A clockwise radial sweep for donut and pie charts.
struct DSRingSweepShape: Shape {
    var progress: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let amount = min(max(progress, 0), 1)
        var path = Path()
        path.move(to: center)
        guard amount > 0 else { return path }
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * Double(amount)),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

struct DSSweepRevealModifier: ViewModifier {
    @Environment(\\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    let key: String

    func body(content: Content) -> some View {
        content
            .mask {
                GeometryReader { geometry in
                    DSRingSweepShape(progress: progress)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .onAppear(perform: replay)
            .onChange(of: key) { _, _ in replay() }
            .onChange(of: reduceMotion) { _, shouldReduce in
                if shouldReduce { progress = 1 }
            }
    }

    private func replay() {
        guard !reduceMotion else {
            progress = 1
            return
        }
        progress = 0
        withAnimation(.easeInOut(duration: 0.92)) {
            progress = 1
        }
    }
}

extension View {
    func dsChartReveal(key: String) -> some View {
        modifier(DSChartRevealModifier(key: key))
    }

    func dsSweepReveal(key: String) -> some View {
        modifier(DSSweepRevealModifier(key: key))
    }
}
