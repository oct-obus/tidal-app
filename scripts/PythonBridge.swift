import Flutter
import UIKit

// Python C API
@_silgen_name("Py_Initialize")
func Py_Initialize()

@_silgen_name("Py_IsInitialized")
func Py_IsInitialized() -> Int32

@_silgen_name("PyRun_SimpleString")
func PyRun_SimpleString(_ command: UnsafePointer<CChar>) -> Int32

@_silgen_name("Py_FinalizeEx")
func Py_FinalizeEx() -> Int32

@_silgen_name("setenv")
func c_setenv(_ name: UnsafePointer<CChar>, _ value: UnsafePointer<CChar>, _ overwrite: Int32) -> Int32

class PythonBridge: NSObject {
    static let shared = PythonBridge()
    private var isInitialized = false

    func initialize() {
        guard !isInitialized else { return }

        let resourcePath = Bundle.main.resourcePath!
        let pythonHome = "\(resourcePath)/python"
        let appPath = "\(resourcePath)/python/app"
        let appPackages = "\(resourcePath)/python/app_packages"
        let pythonPath = "\(appPath):\(appPackages)"

        _ = c_setenv("PYTHONHOME", pythonHome, 1)
        _ = c_setenv("PYTHONPATH", pythonPath, 1)
        // Prevent writing .pyc files (read-only bundle)
        _ = c_setenv("PYTHONDONTWRITEBYTECODE", "1", 1)

        Py_Initialize()
        isInitialized = Py_IsInitialized() != 0

        if isInitialized {
            NSLog("PythonBridge: Python initialized successfully")
        } else {
            NSLog("PythonBridge: Failed to initialize Python")
        }
    }

    func run(_ code: String) -> Bool {
        guard isInitialized else { return false }
        let result = PyRun_SimpleString(code)
        return result == 0
    }
}

public class PythonBridgePlugin: NSObject, FlutterPlugin {
    private let bridge = PythonBridge.shared

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.obus.tidal_app/python",
            binaryMessenger: registrar.messenger()
        )
        let instance = PythonBridgePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Initialize Python early
        instance.bridge.initialize()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "runPython":
            guard let args = call.arguments as? [String: Any],
                  let code = args["code"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'code' argument", details: nil))
                return
            }
            let success = bridge.run(code)
            result(success)

        case "download":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'url' argument", details: nil))
                return
            }
            // TODO: Phase 3 — call tiddl download via Python bridge
            result(FlutterError(code: "NOT_IMPLEMENTED", message: "Tiddl download not yet implemented", details: nil))

        case "pythonVersion":
            let success = bridge.run("""
                import sys
                print(f"Python {sys.version}")
            """)
            result(success ? "OK" : "Failed")

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
