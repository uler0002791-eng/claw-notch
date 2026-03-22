//
//  TabOrderSettings.swift
//  boringNotch
//
//  Tab order customization for the notch.
//

import Defaults
import SwiftUI

struct TabOrderSection: View {
    @Default(.tabOrder) var tabOrder
    @Default(.showLobster) var showLobster

    private var tabInfo: [NotchViews: (label: String, icon: String)] {
        [
            .home: ("Home", "house.fill"),
            .shelf: ("Shelf", "tray.fill"),
            .lobster: ("OpenClaw", "bubble.left.fill"),
        ]
    }

    var body: some View {
        Section {
            ForEach(Array(tabOrder.enumerated()), id: \.element) { index, tab in
                if tab != .lobster || showLobster {
                    HStack {
                        Image(systemName: tabInfo[tab]?.icon ?? "questionmark")
                            .frame(width: 20)
                            .foregroundColor(.secondary)
                        Text(tabInfo[tab]?.label ?? "")
                        Spacer()
                        // Move up button
                        Button {
                            moveTab(at: index, direction: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isFirstVisible(index: index))
                        // Move down button
                        Button {
                            moveTab(at: index, direction: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isLastVisible(index: index))
                    }
                    .padding(.vertical, 2)
                }
            }

            Text("展开灵动岛时默认显示排在第一位的标签页")
                .font(.caption)
                .foregroundColor(.secondary)
        } header: {
            Text("Tab order")
        }
    }

    private func moveTab(at index: Int, direction: Int) {
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < tabOrder.count else { return }
        withAnimation(.smooth) {
            tabOrder.swapAt(index, newIndex)
        }
    }

    private func isFirstVisible(index: Int) -> Bool {
        for i in 0..<index {
            let tab = tabOrder[i]
            if tab != .lobster || showLobster {
                return false
            }
        }
        return true
    }

    private func isLastVisible(index: Int) -> Bool {
        for i in (index + 1)..<tabOrder.count {
            let tab = tabOrder[i]
            if tab != .lobster || showLobster {
                return false
            }
        }
        return true
    }
}

#Preview {
    Form {
        TabOrderSection()
    }
    .formStyle(.grouped)
    .frame(width: 400)
}
