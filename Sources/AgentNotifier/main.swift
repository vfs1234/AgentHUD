import AppKit

// Menu-bar-only app: no Dock icon, no main window. LSUIElement in Info.plist is
// the real driver; setting .accessory here too makes it explicit. We use a
// manual NSApplication run loop (not @main / NSApplicationMain) so the
// hand-assembled SwiftPM bundle behaves predictably.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
