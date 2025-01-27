import Foundation
import Python
import PythonKit

class PythonManager {
  static let shared = PythonManager()

  private(set) var isInitialized = false
  private(set) var sys: PythonObject?
  private(set) var yoloWrapper: PythonObject?
  private(set) var model: PythonObject?

  private init() {}

  func initialize() throws {
    guard !isInitialized else { return }

    // Initialize Python paths
    guard let stdLibPath = Bundle.main.path(forResource: "python-stdlib", ofType: nil) else {
      throw PythonError.resourceNotFound("python-stdlib not found")
    }
    guard
      let libDynloadPath = Bundle.main.path(forResource: "python-stdlib/lib-dynload", ofType: nil)
    else {
      throw PythonError.resourceNotFound("lib-dynload not found")
    }
    guard let scriptsPath = Bundle.main.path(forResource: "python-scripts", ofType: nil) else {
      throw PythonError.resourceNotFound("python-scripts not found")
    }

    let sitePackagesPath = "\(stdLibPath)/site-packages"

    // Set Python environment
    setenv("PYTHONHOME", stdLibPath, 1)
    setenv("PYTHONPATH", "\(stdLibPath):\(libDynloadPath):\(sitePackagesPath):\(scriptsPath)", 1)
    Py_Initialize()

    // Import and verify core modules
    sys = Python.import("sys")
    print("Python Version: \(sys!.version_info.major).\(sys!.version_info.minor)")
    print("Python Encoding: \(sys!.getdefaultencoding().upper())")
    print("Python Path: \(sys!.path)")

    // Import our wrapper
    do {
      yoloWrapper = Python.import("yolo_wrapper")
      print("Successfully imported YOLO wrapper")

      // Try to initialize numpy through our wrapper
      let initResult = yoloWrapper!.init_numpy()
      if Python.bool(initResult) == false {
        throw PythonError.importError("Failed to initialize numpy")
      }

      // Try to initialize YOLO
      let yoloClass = yoloWrapper!.init_ultralytics()
      if yoloClass == Python.None {
        throw PythonError.importError("Failed to initialize YOLO")
      }

    } catch {
      print("Warning: Failed to initialize Python components: \(error)")
      throw PythonError.importError("Failed to initialize Python components: \(error)")
    }

    isInitialized = true
  }

  func loadModel(_ path: String) throws {
    guard isInitialized else { throw PythonError.notInitialized }
    guard let wrapper = yoloWrapper else {
      throw PythonError.importError("YOLO wrapper not loaded")
    }

    model = wrapper.load_model(path)
  }

  func predictImage(_ imagePath: String) throws -> PythonObject {
    guard isInitialized else { throw PythonError.notInitialized }
    guard let wrapper = yoloWrapper else {
      throw PythonError.importError("YOLO wrapper not loaded")
    }
    guard let model = model else { throw PythonError.notInitialized }

    return wrapper.predict_image(model, imagePath)
  }

  func cleanup() {
    guard isInitialized else { return }
    Py_Finalize()
    isInitialized = false
    sys = nil
    yoloWrapper = nil
    model = nil
  }
}

enum PythonError: Error {
  case resourceNotFound(String)
  case importError(String)
  case notInitialized
}
