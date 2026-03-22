//
//  OpenClawSettings.swift
//  boringNotch
//
//  OpenClaw / Lobster settings panel.
//

import Defaults
import SwiftUI

struct OpenClawSettings: View {
    @Default(.showLobster) var showLobster

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showLobster) {
                    HStack {
                        Text("启用小龙虾")
                        Spacer()
                        Text("在刘海中显示小龙虾标签页和迷你视图")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    Text("🦞")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenClaw")
                            .font(.headline)
                        Text("由 OpenClaw 驱动的 AI 助手")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    OpenClawSettings()
        .frame(width: 500, height: 300)
}
