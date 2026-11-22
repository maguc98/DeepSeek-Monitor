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
