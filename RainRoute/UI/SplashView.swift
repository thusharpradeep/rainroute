import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineProgress: CGFloat = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Theme.launchBackground,
                    Color(red: 0.02, green: 0.05, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 154, height: 154)
                    Circle()
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        .frame(width: 154, height: 154)
                    rainCloud
                }

                VStack(spacing: 8) {
                    Text("RainRoute")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Know the rain before the ride.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                }

                routeLine
                    .frame(width: 190, height: 46)
            }
            .padding(32)
            .opacity(contentOpacity)
        }
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                contentOpacity = 1
                lineProgress = 1
            } else {
                withAnimation(.easeOut(duration: 0.5)) {
                    contentOpacity = 1
                }
                withAnimation(.easeInOut(duration: 1.25).delay(0.15)) {
                    lineProgress = 1
                }
            }
        }
    }

    private var rainCloud: some View {
        ZStack {
            Image(systemName: "cloud.fill")
                .font(.system(size: 72, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.10))
                .offset(y: -4)

            Image(systemName: "cloud.rain.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Theme.lightRain)

            TimelineView(
                .animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)
            ) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ForEach(0..<3, id: \.self) { drop in
                    Capsule()
                        .fill(Theme.lightRain.opacity(0.8))
                        .frame(width: 2, height: 8)
                        .offset(
                            x: CGFloat(drop - 1) * 12,
                            y: 24 + CGFloat(phase(drop, time: time) * 16)
                        )
                        .opacity(1 - phase(drop, time: time))
                }
            }
            .frame(width: 80, height: 80)
        }
        .frame(width: 130, height: 130)
    }

    private var routeLine: some View {
        ZStack {
            RouteLineShape()
                .trim(from: 0, to: lineProgress)
                .stroke(
                    Theme.lightRain,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: Theme.lightRain.opacity(0.45), radius: 6)

            GeometryReader { proxy in
                let size = proxy.size
                Circle()
                    .fill(.white)
                    .frame(width: 9, height: 9)
                    .position(x: 6, y: size.height - 10)
                    .opacity(lineProgress > 0.05 ? 1 : 0)

                Circle()
                    .fill(Theme.safe)
                    .frame(width: 11, height: 11)
                    .position(x: size.width - 6, y: 10)
                    .opacity(lineProgress > 0.95 ? 1 : 0)
            }
        }
    }

    private func phase(_ drop: Int, time: TimeInterval) -> Double {
        let raw = time * 0.75 + Double(drop) * 0.33
        return raw.truncatingRemainder(dividingBy: 1)
    }
}

private struct RouteLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 6, y: rect.maxY - 10))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 6, y: rect.minY + 10),
            control1: CGPoint(x: rect.width * 0.28, y: rect.minY - 8),
            control2: CGPoint(x: rect.width * 0.70, y: rect.maxY + 8)
        )
        return path
    }
}
