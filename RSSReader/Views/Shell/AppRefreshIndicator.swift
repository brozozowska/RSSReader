import SwiftUI

enum AppRefreshIndicatorState: Equatable {
    case idle
    case pulling(progress: Double)
    case ready
    case refreshing

    var isVisible: Bool {
        switch self {
        case .idle:
            false
        case .pulling, .ready, .refreshing:
            true
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle:
            "Refresh idle"
        case .pulling:
            "Pulling to refresh"
        case .ready:
            "Release to refresh"
        case .refreshing:
            "Refreshing"
        }
    }
}

struct AppRefreshIndicator: View {
    let state: AppRefreshIndicatorState
    var size: CGFloat = 18
    var lineWidth: CGFloat = 2
    var tint: AnyShapeStyle = AnyShapeStyle(.primary)
    var accessibilityLabel: String?

    var body: some View {
        TimelineView(.animation) { timeline in
            RefreshRing(progress: ringProgress)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(rotation(at: timeline.date))
                .opacity(state.isVisible ? ringOpacity : 0)
                .animation(.snappy(duration: 0.2), value: state)
                .accessibilityLabel(accessibilityLabel ?? state.accessibilityLabel)
                .accessibilityHidden(state == .idle)
        }
    }

    private var ringProgress: Double {
        switch state {
        case .idle:
            0
        case .pulling(let progress):
            min(max(progress, 0), 1)
        case .ready:
            1
        case .refreshing:
            0.78
        }
    }

    private var ringOpacity: Double {
        switch state {
        case .idle:
            0
        case .pulling(let progress):
            0.25 + 0.75 * min(max(progress, 0), 1)
        case .ready, .refreshing:
            1
        }
    }

    private func rotation(at date: Date) -> Angle {
        switch state {
        case .ready:
            .degrees(45)
        case .refreshing:
            .degrees(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360)
        case .idle, .pulling:
            .zero
        }
    }
}

private struct RefreshRing: Shape {
    let progress: Double

    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        let radius = diameter / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let startAngle = Angle.degrees(-90)
        let endAngle = Angle.degrees(-90 + 360 * progress)

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

#Preview("Refresh Indicator") {
    HStack(spacing: 16) {
        AppRefreshIndicator(state: .idle)
        AppRefreshIndicator(state: .pulling(progress: 0.35))
        AppRefreshIndicator(state: .ready)
        AppRefreshIndicator(state: .refreshing)
    }
    .padding()
}
