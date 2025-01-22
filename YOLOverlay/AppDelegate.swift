import AppKit
import Combine
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var preferencesWindow: NSWindow?
  private var logWindowController: LogWindowController?
  private var statsTimer: Timer?
  private let captureManager = ScreenCaptureManager.shared
  private var cancellables = Set<AnyCancellable>()

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Create status item
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "YOLO Detection")
    }

    setupMenu()
    setupObservers()

    // Create menu items
    if let mainMenu = NSApp.mainMenu {
      let appMenuItem = mainMenu.items.first

      // Add Preferences menu item
      let prefSeparator = NSMenuItem.separator()
      appMenuItem?.submenu?.insertItem(prefSeparator, at: 1)

      let preferencesItem = NSMenuItem(
        title: "Preferences...",
        action: #selector(showPreferences),
        keyEquivalent: ","
      )
      appMenuItem?.submenu?.insertItem(preferencesItem, at: 2)

      let postPrefSeparator = NSMenuItem.separator()
      appMenuItem?.submenu?.insertItem(postPrefSeparator, at: 3)
    }

    // Show preferences window at launch
    showPreferences()

    // Restore log window state if it was open
    if UserDefaults.standard.bool(forKey: "LogWindowVisible") {
      showLogs()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Save log window state
    UserDefaults.standard.set(
      logWindowController?.window?.isVisible ?? false, forKey: "LogWindowVisible")
  }

  private func setupObservers() {
    captureManager.$isRecording
      .receive(on: RunLoop.main)
      .sink { [weak self] isRecording in
        self?.updateMenuState(isRecording: isRecording)
      }
      .store(in: &cancellables)
  }

  private func updateMenuState(isRecording: Bool) {
    statusItem.button?.image = NSImage(
      systemSymbolName: isRecording ? "eye.fill" : "eye",
      accessibilityDescription: isRecording ? "YOLO Detection Active" : "YOLO Detection"
    )

    if let menuItem = statusItem.menu?.item(at: 0) {
      menuItem.title = isRecording ? "Stop Detection" : "Start Detection"
    }

    if isRecording {
      startStatsTimer()
    } else {
      stopStatsTimer()
    }
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

    // Add log window item
    let logsItem = NSMenuItem(
      title: "Show Logs",
      action: #selector(showLogs),
      keyEquivalent: "l"
    )
    logsItem.target = self
    menu.addItem(logsItem)

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
    Task {
      let isRecording = await captureManager.isRecording
      if isRecording {
        await captureManager.stopCapture()
      } else {
        await captureManager.startCapture()
      }
    }
  }

  @objc func showPreferences() {
    if preferencesWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.title = "Preferences"
      window.center()

      let hostingView = NSHostingView(rootView: PreferencesView())
      window.contentView = hostingView

      preferencesWindow = window
    }

    preferencesWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc func showLogs() {
    if logWindowController == nil {
      logWindowController = LogWindowController()
    }
    logWindowController?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func startStatsTimer() {
    statsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      Task { @MainActor in
        if let statsItem = self.statusItem.menu?.item(at: 1) {
          statsItem.title = self.captureManager.stats
        }
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
