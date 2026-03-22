//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.showLobster) var showLobster
    @Default(.tabOrder) var tabOrder
    @Namespace var animation

    static let allTabDefs: [NotchViews: TabModel] = [
        .home: TabModel(label: "Home", icon: "house.fill", view: .home),
        .shelf: TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
        .lobster: TabModel(label: "Lobster", icon: "bubble.left.fill", view: .lobster),
    ]

    var visibleTabs: [TabModel] {
        // Use stored order, filter out hidden tabs
        return tabOrder.compactMap { view in
            if view == .lobster && !showLobster { return nil }
            return Self.allTabDefs[view]
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
