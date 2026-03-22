//
//  LighthouseMiniView.swift
//  boringNotch
//
//  Pixel-art lighthouse for OpenClaw connection status.
//  Lit = online, dark = offline. Pure SwiftUI rendering.
//

import SwiftUI

// MARK: - Pixel Art Data

private enum LighthouseSprites {

    // 11 rows × 12 cols
    // 0=transparent, 1=white body, 2=structure gray, 3=light(yellow),
    // 4=red stripe, 5=base rock, 6=ray beam, 7=bright ray

    static let lit: [[Int]] = [
        [6,0,0,0,0,7,7,0,0,0,0,6],
        [0,6,0,0,7,3,3,7,0,0,6,0],
        [0,0,6,0,7,3,3,7,0,6,0,0],
        [0,0,0,6,2,3,3,2,6,0,0,0],
        [0,0,0,0,0,2,2,0,0,0,0,0],
        [0,0,0,0,1,4,4,1,0,0,0,0],
        [0,0,0,0,4,1,1,4,0,0,0,0],
        [0,0,0,1,1,4,4,1,1,0,0,0],
        [0,0,0,4,4,1,1,4,4,0,0,0],
        [0,0,1,1,1,4,4,1,1,1,0,0],
        [0,5,5,5,5,5,5,5,5,5,5,0],
    ]

    static let dark: [[Int]] = [
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,2,2,2,2,0,0,0,0],
        [0,0,0,0,0,2,2,0,0,0,0,0],
        [0,0,0,0,1,4,4,1,0,0,0,0],
        [0,0,0,0,4,1,1,4,0,0,0,0],
        [0,0,0,1,1,4,4,1,1,0,0,0],
        [0,0,0,4,4,1,1,4,4,0,0,0],
        [0,0,1,1,1,4,4,1,1,1,0,0],
        [0,5,5,5,5,5,5,5,5,5,5,0],
    ]
}

// MARK: - Palette

private struct LighthousePalette {
    let white: Color
    let structure: Color
    let light: Color
    let red: Color
    let base: Color
    let ray: Color
    let brightRay: Color

    static let online = LighthousePalette(
        white: Color(red: 0.95, green: 0.95, blue: 0.95),
        structure: Color(red: 0.4, green: 0.4, blue: 0.45),
        light: Color(red: 1.0, green: 0.9, blue: 0.3),
        red: Color(red: 0.85, green: 0.2, blue: 0.15),
        base: Color(red: 0.45, green: 0.4, blue: 0.35),
        ray: Color(red: 1.0, green: 0.85, blue: 0.3).opacity(0.5),
        brightRay: Color(red: 1.0, green: 0.95, blue: 0.6)
    )

    static let offline = LighthousePalette(
        white: Color(red: 0.45, green: 0.45, blue: 0.45),
        structure: Color(red: 0.3, green: 0.3, blue: 0.35),
        light: Color(red: 0.3, green: 0.3, blue: 0.35),
        red: Color(red: 0.4, green: 0.18, blue: 0.15),
        base: Color(red: 0.3, green: 0.28, blue: 0.25),
        ray: .clear,
        brightRay: .clear
    )

    func color(for index: Int) -> Color? {
        switch index {
        case 1: return white
        case 2: return structure
        case 3: return light
        case 4: return red
        case 5: return base
        case 6: return ray
        case 7: return brightRay
        default: return nil
        }
    }
}

// MARK: - Pixel Grid

private struct LighthousePixelGrid: View {
    let pixels: [[Int]]
    let palette: LighthousePalette
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

struct LighthouseMiniView: View {
    @ObservedObject var lobster = LobsterStateManager.shared

    @State private var glowPulse: Bool = false
    @State private var rayRotation: Double = 0
    @State private var animTimer: Timer?

    private let px: CGFloat = 2.0

    var isOnline: Bool {
        lobster.mood != .offline
    }

    var body: some View {
        ZStack {
            LighthousePixelGrid(
                pixels: isOnline ? LighthouseSprites.lit : LighthouseSprites.dark,
                palette: isOnline ? .online : .offline,
                px: px
            )

            // Animated glow around the lamp when online
            if isOnline {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.0, green: 0.9, blue: 0.3).opacity(glowPulse ? 0.6 : 0.25),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: 10
                        )
                    )
                    .frame(width: 20, height: 20)
                    .offset(y: -8)
            }
        }
        .frame(width: 12 * px + 4, height: 11 * px + 4)
        .onAppear { startAnimation() }
        .onChange(of: isOnline) { _, _ in startAnimation() }
        .onDisappear { stopAnimation() }
    }

    private func startAnimation() {
        stopAnimation()
        guard isOnline else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.8)) {
                    glowPulse.toggle()
                }
            }
        }
    }

    private func stopAnimation() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

#Preview {
    ZStack {
        Color.black
        HStack(spacing: 20) {
            LighthouseMiniView()
        }
    }
    .frame(width: 60, height: 40)
}
