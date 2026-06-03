import AppKit

/// An always-on-top, non-activating, borderless panel that floats over all
/// Spaces and fullscreen apps without stealing keyboard focus. Borderless so the
/// window sizes exactly to its SwiftUI content (needed for collapse/expand).
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Transparent so SwiftUI draws the rounded material background + shadow.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Floating / non-activating
        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow

        // Visible on every Space and over fullscreen apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    // Borderless windows can't become key by default; allow it so the row/header
    // buttons receive clicks. Never become main (don't steal app focus).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
