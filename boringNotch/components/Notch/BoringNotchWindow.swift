//
//  BoringNotchWindow.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 06/08/24.
//

import Cocoa

class BoringNotchWindow: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false

        NotificationCenter.default.addObserver(self, selector: #selector(onLobsterActivate), name: Notification.Name("lobsterTabDidActivate"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onLobsterDeactivate), name: Notification.Name("lobsterTabDidDeactivate"), object: nil)
    }

    @objc private func onLobsterActivate() {
        canAcceptKeyInput = true
        makeKey()
    }

    @objc private func onLobsterDeactivate() {
        canAcceptKeyInput = false
    }
    
    var canAcceptKeyInput: Bool = false
    override var canBecomeKey: Bool { canAcceptKeyInput }
    override var canBecomeMain: Bool { false }
}
