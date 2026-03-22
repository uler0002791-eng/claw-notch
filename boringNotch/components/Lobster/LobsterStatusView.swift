//
//  LobsterStatusView.swift
//  boringNotch
//
//  Large pixel-art lobster for expanded notch. Same sprite style as LobsterMiniView
//  but bigger (px=5) with activity-specific overlays and animations.
//

import SwiftUI

// MARK: - Sprites (same as LobsterMiniView)

/// 0=transparent, 1=body, 2=claw, 3=eye-white, 4=eye-pupil, 5=belly
private enum BigSprites {

    static let idle: [[Int]] = [
        [0,0,2,2,0,0,0,0,0,0,2,2,0,0],
        [0,2,2,0,0,0,0,0,0,0,0,2,2,0],
        [2,2,0,0,0,1,1,1,1,0,0,0,2,2],
        [0,0,0,0,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,1,3,4,1,1,3,4,1,0,0,0],
        [0,0,0,1,1,1,5,5,1,1,1,0,0,0],
        [0,0,0,0,1,5,5,5,5,1,0,0,0,0],
        [0,0,0,0,0,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,1,0,1,1,0,1,0,0,0,0],
    ]

    static let working: [[Int]] = [
        [2,2,0,0,0,0,0,0,0,0,0,0,2,2],
        [0,2,2,0,0,0,0,0,0,0,0,2,2,0],
        [0,0,2,0,0,1,1,1,1,0,0,2,0,0],
        [0,0,0,0,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,1,4,3,1,1,4,3,1,0,0,0],
        [0,0,0,1,1,1,5,5,1,1,1,0,0,0],
        [0,0,0,0,1,5,5,5,5,1,0,0,0,0],
        [0,0,0,0,0,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,1,0,1,1,0,1,0,0,0,0],
    ]

    static let workingAlt: [[Int]] = [
        [0,2,2,0,0,0,0,0,0,0,0,2,2,0],
        [2,2,0,0,0,0,0,0,0,0,0,0,2,2],
        [2,0,0,0,0,1,1,1,1,0,0,0,0,2],
        [0,0,0,0,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,1,4,3,1,1,4,3,1,0,0,0],
        [0,0,0,1,1,1,5,5,1,1,1,0,0,0],
        [0,0,0,0,1,5,5,5,5,1,0,0,0,0],
        [0,0,0,0,0,1,1,1,1,0,0,0,0,0],
        [0,0,0,0,1,0,1,1,0,1,0,0,0,0],
    ]

    static func blinked(_ base: [[Int]]) -> [[Int]] {
        var f = base
        if f.count > 4 {
            for col in f[4].indices {
                if f[4][col] == 3 || f[4][col] == 4 {
                    f[4][col] = 1
                }
            }
        }
        return f
    }
}

// MARK: - Palette

private struct BigPalette {
    let body: Color
    let claw: Color
    let eyeWhite: Color
    let eyePupil: Color
    let belly: Color

    static func forActivity(_ activity: LobsterActivity) -> BigPalette {
        switch activity {
        case .idle, .done:
            return BigPalette(
                body: Color(red: 0.85, green: 0.22, blue: 0.18),
                claw: Color(red: 0.95, green: 0.30, blue: 0.20),
                eyeWhite: .white,
                eyePupil: Color(red: 0.1, green: 0.1, blue: 0.15),
                belly: Color(red: 1.0, green: 0.55, blue: 0.4)
            )
        case .thinking, .typing:
            return BigPalette(
                body: Color(red: 0.95, green: 0.35, blue: 0.15),
                claw: Color(red: 1.0, green: 0.45, blue: 0.20),
                eyeWhite: .white,
                eyePupil: Color(red: 0.1, green: 0.1, blue: 0.15),
                belly: Color(red: 1.0, green: 0.6, blue: 0.35)
            )
        case .toolUse:
            return BigPalette(
                body: Color(red: 0.2, green: 0.5, blue: 0.85),
                claw: Color(red: 0.3, green: 0.6, blue: 0.95),
                eyeWhite: .white,
                eyePupil: Color(red: 0.1, green: 0.1, blue: 0.15),
                belly: Color(red: 0.5, green: 0.7, blue: 1.0)
            )
        case .searching:
            return BigPalette(
                body: Color(red: 0.15, green: 0.65, blue: 0.65),
                claw: Color(red: 0.2, green: 0.75, blue: 0.75),
                eyeWhite: .white,
                eyePupil: Color(red: 0.1, green: 0.1, blue: 0.15),
                belly: Color(red: 0.4, green: 0.8, blue: 0.8)
            )
        case .error:
            return BigPalette(
                body: Color(red: 0.78, green: 0.12, blue: 0.1),
                claw: Color(red: 0.88, green: 0.18, blue: 0.12),
                eyeWhite: .white,
                eyePupil: Color(red: 0.6, green: 0.1, blue: 0.1),
                belly: Color(red: 0.9, green: 0.45, blue: 0.35)
            )
        case .offline:
            return BigPalette(
                body: Color(red: 0.35, green: 0.35, blue: 0.38),
                claw: Color(red: 0.4, green: 0.4, blue: 0.43),
                eyeWhite: Color(red: 0.55, green: 0.55, blue: 0.55),
                eyePupil: Color(red: 0.3, green: 0.3, blue: 0.3),
                belly: Color(red: 0.45, green: 0.45, blue: 0.48)
            )
        }
    }

    func color(for index: Int) -> Color? {
        switch index {
        case 1: return body
        case 2: return claw
        case 3: return eyeWhite
        case 4: return eyePupil
        case 5: return belly
        default: return nil
        }
    }
}

// MARK: - Pixel Grid (large)

private struct BigPixelGrid: View {
    let pixels: [[Int]]
    let palette: BigPalette
    let px: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<pixels.count, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<pixels[row].count, id: \.self) { col in
                        if let c = palette.color(for: pixels[row][col]) {
                            Rectangle().fill(c)
                                .frame(width: px, height: px)
                        } else {
                            Color.clear
                                .frame(width: px, height: px)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Main View

struct LobsterStatusView: View {
    @ObservedObject var lobster = LobsterStateManager.shared

    @State private var frame: Int = 0
    @State private var blinking: Bool = false
    @State private var bounce: CGFloat = 0
    @State private var animTimer: Timer?
    @State private var blinkTimer: Timer?

    private let px: CGFloat = 5.0

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Glow background
                Circle()
                    .fill(glowColor.opacity(0.12))
                    .frame(width: 78, height: 78)

                // Pixel lobster
                BigPixelGrid(
                    pixels: currentPixels,
                    palette: BigPalette.forActivity(lobster.activity),
                    px: px
                )
                .offset(y: bounce)

                // Activity badge overlay
                activityBadge
            }
            .frame(width: 80, height: 70)

            // Label
            Text(activityLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(glowColor)
                .lineLimit(1)
        }
        .onAppear { startAnimations() }
        .onChange(of: lobster.activity) { _, _ in startAnimations() }
        .onDisappear { stopTimers() }
    }

    // MARK: - Sprite selection

    private var currentPixels: [[Int]] {
        let base: [[Int]]
        switch lobster.activity {
        case .idle, .done, .offline:
            base = BigSprites.idle
        case .thinking:
            base = BigSprites.idle
        case .typing, .toolUse, .searching:
            base = frame % 2 == 0 ? BigSprites.working : BigSprites.workingAlt
        case .error:
            base = BigSprites.idle
        }
        return blinking ? BigSprites.blinked(base) : base
    }

    // MARK: - Activity badge (small icon overlay)

    @ViewBuilder
    private var activityBadge: some View {
        switch lobster.activity {
        case .thinking:
            Text("💭")
                .font(.system(size: 12))
                .offset(x: 30, y: -22)
                .opacity(frame % 2 == 0 ? 1.0 : 0.4)
        case .typing:
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 3, height: 3)
                        .opacity(frame % 3 == i ? 1.0 : 0.3)
                }
            }
            .offset(x: 28, y: 14)
        case .toolUse:
            Text("🔧")
                .font(.system(size: 11))
                .offset(x: 30, y: -22)
                .rotationEffect(.degrees(frame % 2 == 0 ? -15 : 15))
        case .searching:
            Text("🔍")
                .font(.system(size: 11))
                .offset(x: frame % 2 == 0 ? 28 : 32, y: -22)
        case .done:
            Text("✅")
                .font(.system(size: 11))
                .offset(x: 30, y: -22)
        case .error:
            Text("❌")
                .font(.system(size: 11))
                .offset(x: 30, y: -22)
        case .idle, .offline:
            EmptyView()
        }
    }

    // MARK: - Labels & Colors

    private var activityLabel: String {
        switch lobster.activity {
        case .idle: return "待命中"
        case .thinking: return "思考中..."
        case .typing: return "回复中..."
        case .toolUse: return "调用工具"
        case .searching: return "搜索中..."
        case .done: return "已完成 ✓"
        case .error: return "出错了"
        case .offline: return "离线"
        }
    }

    private var glowColor: Color {
        switch lobster.activity {
        case .idle, .done: return .green
        case .thinking, .typing: return .orange
        case .toolUse: return .blue
        case .searching: return .cyan
        case .error: return .red
        case .offline: return .gray
        }
    }

    // MARK: - Animation

    private func startAnimations() {
        stopTimers()

        let interval: TimeInterval
        switch lobster.activity {
        case .idle, .offline: interval = 1.0
        case .thinking: interval = 0.8
        case .typing: interval = 0.25
        case .toolUse, .searching: interval = 0.4
        case .done: interval = 0.5
        case .error: interval = 0.6
        }

        animTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                frame += 1
                switch lobster.activity {
                case .idle:
                    withAnimation(.easeInOut(duration: 0.5)) {
                        bounce = bounce == 0 ? -1 : 0
                    }
                case .typing, .toolUse, .searching:
                    withAnimation(.easeInOut(duration: 0.12)) {
                        bounce = bounce == 0 ? -2 : 0
                    }
                case .thinking:
                    withAnimation(.easeInOut(duration: 0.5)) {
                        bounce = bounce == 0 ? -1.5 : 0
                    }
                case .done:
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 5)) {
                        bounce = bounce == 0 ? -4 : 0
                    }
                case .error:
                    withAnimation(.easeInOut(duration: 0.15)) {
                        bounce = CGFloat.random(in: -2...2)
                    }
                case .offline:
                    bounce = 0
                }
            }
        }

        // Blink timer
        if lobster.activity != .offline {
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                Task { @MainActor in
                    blinking = true
                    try? await Task.sleep(for: .milliseconds(150))
                    blinking = false
                }
            }
        }
    }

    private func stopTimers() {
        animTimer?.invalidate()
        animTimer = nil
        blinkTimer?.invalidate()
        blinkTimer = nil
    }
}

#Preview {
    ZStack {
        Color.black
        LobsterStatusView()
    }
    .frame(width: 120, height: 120)
}
