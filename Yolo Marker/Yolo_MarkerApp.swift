//
//  Yolo_MarkerApp.swift
//  Yolo Marker
//
//  Created by p on 1/22/25.
//

import SwiftUI

@main
struct Yolo_MarkerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}
