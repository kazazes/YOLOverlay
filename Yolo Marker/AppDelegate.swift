import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var captureManager: ScreenCaptureManager!
  private var statsTimer: Timer?
  private var preferencesWindow: NSWindow?

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

    // Add stats item
    let statsItem = NSMenuItem(title: "No stats available", action: nil, keyEquivalent: "")
    statsItem.isEnabled = false
    menu.addItem(statsItem)

    menu.addItem(NSMenuItem.separator())

    // Add preferences item
    let preferencesItem = NSMenuItem(
      title: "Preferences...",
      action: #selector(showPreferences),
      keyEquivalent: ","
    )
    preferencesItem.target = self
    menu.addItem(preferencesItem)

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
        stopStatsTimer()
      } else {
        await captureManager.startCapture()
        statusItem.button?.image = NSImage(
          systemSymbolName: "eye.fill", accessibilityDescription: "YOLO Detection Active")
        if let menuItem = statusItem.menu?.item(at: 0) {
          menuItem.title = "Stop Detection"
        }
        startStatsTimer()
      }
    }
  }

  @objc private func showPreferences() {
    if preferencesWindow == nil {
      let preferencesView = PreferencesView()
      let hostingController = NSHostingController(rootView: preferencesView)

      preferencesWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 350, height: 250),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )

      preferencesWindow?.title = "Preferences"
      preferencesWindow?.contentViewController = hostingController
      preferencesWindow?.center()
      preferencesWindow?.isReleasedWhenClosed = false
    }

    preferencesWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func startStatsTimer() {
    statsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      if let statsItem = self.statusItem.menu?.item(at: 1) {
        statsItem.title = self.captureManager.stats
      }
    }
  }

  private func stopStatsTimer() {
    statsTimer?.invalidate()
    statsTimer = nil
    if let statsItem = statusItem.menu?.item(at: 1) {
      statsItem.title = "No stats available"
    }
  }
}
