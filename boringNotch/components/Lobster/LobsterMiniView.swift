//
//  LobsterMiniView.swift
//  boringNotch
//
//  Pixel-art lobster displayed in the closed notch state.
//  Pure SwiftUI rendering — no external assets.
//

import SwiftUI

// MARK: - Pixel Art Data

/// Each sprite is a 2D array of color indices.
/// 0 = transparent, 1 = body, 2 = claw, 3 = eye-white, 4 = eye-pupil, 5 = belly/highlight
private enum Sprites {

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

private struct Palette {
    let body: Color
    let claw: Color
    let eyeWhite: Color
    let eyePupil: Color
    let belly: Color

    static func forMood(_ mood: LobsterMood) -> Palette {
        switch mood {
        case .idle:
            return Palette(
                body: Color(red: 0.85, green: 0.22, blue: 0.18),
                claw: Color(red: 0.95, green: 0.30, blue: 0.20),
                eyeWhite: .white,
                eyePupil: Color(red: 0.1, green: 0.1, blue: 0.15),
                belly: Color(red: 1.0, green: 0.55, blue: 0.4)
            )
        case .working:
            return Palette(
                body: Color(red: 0.95, green: 0.35, blue: 0.15),
                claw: Color(red: 1.0, green: 0.45, blue: 0.20),
                eyeWhite: .white,
                eyePupil: Color(red: 0.1, green: 0.1, blue: 0.15),
                belly: Color(red: 1.0, green: 0.6, blue: 0.35)
            )
        case .offline:
            return Palette(
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

// MARK: - Pixel Grid View

private struct PixelGrid: View {
    let pixels: [[Int]]
    let palette: Palette
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

struct LobsterMiniView: View {
    @ObservedObject var lobster = LobsterStateManager.shared

    @State private var frame: Int = 0
    @State private var blinking: Bool = false
    @State private var animTimer: Timer?
    @State private var blinkTimer: Timer?

    private let px: CGFloat = 2.0

    var body: some View {
        PixelGrid(
            pixels: currentPixels,
            palette: Palette.forMood(lobster.mood),
            px: px
        )
        .frame(width: 14 * px + 8, height: 9 * px + 4)
        .onAppear { startAnimations() }
        .onChange(of: lobster.mood) { _, _ in startAnimations() }
        .onDisappear { stopTimers() }
    }

    private var currentPixels: [[Int]] {
        let base: [[Int]]
        switch lobster.mood {
        case .idle:
            base = Sprites.idle
        case .working:
            base = frame % 2 == 0 ? Sprites.working : Sprites.workingAlt
        case .offline:
            base = Sprites.idle  // Same sprite as idle, just gray palette
        }
        return blinking ? Sprites.blinked(base) : base
    }

    // MARK: - Animation

    private func startAnimations() {
        stopTimers()

        // Only animate when working
        if lobster.mood == .working {
            animTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                Task { @MainActor in
                    frame += 1
                }
            }
        }

        // Blinking for idle and working (not offline)
        if lobster.mood != .offline {
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                Task { @MainActor in
                    blinking = true
                    try? await Task.sleep(for: .milliseconds(120))
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
        LobsterMiniView()
    }
    .frame(width: 60, height: 40)
}
