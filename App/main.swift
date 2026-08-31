import AppKit

// A menu bar app, so no Dock icon and no main window — .accessory is the
// runtime half of LSUIElement in Info.plist.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
