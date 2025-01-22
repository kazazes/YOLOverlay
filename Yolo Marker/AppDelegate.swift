import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var captureManager: ScreenCaptureManager!

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Create status item
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "YOLO Detection")
    }

    setupMenu()

    // Initialize capture manager
    captureManager = ScreenCaptureManager()
  }

  private func setupMenu() {
    let menu = NSMenu()

    let startStopItem = NSMenuItem(
      title: "Start Detection",
      action: #selector(toggleDetection),
      keyEquivalent: "s"
    )
    startStopItem.target = self
    menu.addItem(startStopItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
      title: "Quit",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    menu.addItem(quitItem)

    statusItem.menu = menu
  }

  @objc private func toggleDetection() {
    Task { @MainActor in
      if captureManager.isRecording {
        await captureManager.stopCapture()
        statusItem.button?.image = NSImage(
          systemSymbolName: "eye", accessibilityDescription: "YOLO Detection")
        if let menuItem = statusItem.menu?.item(at: 0) {
          menuItem.title = "Start Detection"
        }
      } else {
        await captureManager.startCapture()
        statusItem.button?.image = NSImage(
          systemSymbolName: "eye.fill", accessibilityDescription: "YOLO Detection Active")
        if let menuItem = statusItem.menu?.item(at: 0) {
          menuItem.title = "Stop Detection"
        }
      }
    }
  }
}
