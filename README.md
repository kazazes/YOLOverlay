# 🎯 YOLOverlay

> Real-time object detection overlay for macOS using YOLO models with smooth tracking, performance monitoring, and configurable settings.

[HERO GIF/VIDEO PLACEHOLDER - Show the app in action with bounding boxes tracking objects]

[![GitHub stars](https://img.shields.io/github/stars/kazazes/YOLOverlay.svg?style=social&label=Star&maxAge=2592000)](https://github.com/kazazes/YOLOverlay/stargazers/)
[![macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![YOLO](https://img.shields.io/badge/YOLO-v8/11-darkgreen.svg)](https://docs.ultralytics.com/)

## ✨ Features

### 🚀 Core Detection

- **Real-time Screen Detection**: Instant object detection on any screen area
- **Multiple YOLO Models**: Support for YOLO11 (s, l) and YOLOv8 (l, x)
- **GPU Acceleration**: CoreML-powered inference on Apple Silicon
- **Smart Capture**: Mouse cursor exclusion and frame optimization
- **Configurable Detection**: Adjustable confidence thresholds

### 🎨 Visual Experience

- **Transparent Overlay**: Non-intrusive detection visualization
- **Customizable Display**:
  - Bounding box colors and styles
  - Label font size and opacity
  - Confidence score visibility
  - Class filtering options

### ⚡️ Performance

- **Real-time Monitoring**:
  - FPS and detection latency
  - CPU/GPU utilization
  - Dropped frame detection
  - Performance logging
- **Optimization Controls**:
  - Configurable frame rate
  - Resource usage management
  - Detection throttling

### 🎛️ User Interface

- **Quick Controls**:
  - Status bar menu access
  - Global keyboard shortcuts
    - ⌘S: Start/Stop detection
    - ⌘L: Show performance logs
    - ⌘,: Open preferences
- **Comprehensive Settings**:
  - Model selection
  - Detection parameters
  - Visual customization
  - Performance tuning
  - Class management

### 🔧 Developer Tools

- **Advanced Logging**:
  - Real-time log streaming
  - Log level filtering
  - Millisecond precision
  - Subsystem isolation
- **Performance Metrics**:
  - Detection statistics
  - Resource monitoring
  - Debug information

## 🖥️ Requirements

- macOS 15.1 or later
- Apple Silicon Mac (M1 or newer)
- Screen Recording permission

## 🚀 Installation

1. Download latest release
2. Move to Applications
3. Grant Screen Recording permission
4. Launch and customize

## 📖 Usage

1. Click menu bar eye icon or ⌘S to start
2. Adjust settings with ⌘,
3. Monitor performance with ⌘L
4. Filter and customize as needed

## 🏆 Credits

This project is built on powerful technologies:

### Object Detection

- **YOLO11** by Ultralytics (Glenn Jocher & Jing Qiu)
  - State-of-the-art object detection
  - Version 11.0.0 (2024)
  - [View on GitHub](https://github.com/ultralytics/ultralytics)

### Apple Technologies

- **[Vision Framework](https://developer.apple.com/documentation/vision)**: Advanced computer vision and image analysis
- **[Core ML](https://developer.apple.com/documentation/coreml)**: On-device machine learning inference
- **[ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)**: High-performance screen capture

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/kazazes">kazazes</a>
</p>
