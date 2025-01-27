import AppKit
import SwiftUI

class LogWindowController: NSWindowController {
  convenience init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Application Logs"
    window.contentView = NSHostingView(rootView: LogWindow())
    window.center()

    self.init(window: window)
  }

  override func windowDidLoad() {
    super.windowDidLoad()
    window?.setFrameAutosaveName("LogWindow")
  }
}
