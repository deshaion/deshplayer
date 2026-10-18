import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CacheExport") {
      CacheExportPlugin.register(with: registrar)
    }
  }
}


// Keep folder access scoped to the export; copies run off the main thread.
final class CacheExportPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private var pendingResult: FlutterResult?
  private var files: [[String: String]] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = CacheExportPlugin()
    let channel = FlutterMethodChannel(
      name: "deshplayer/cache_export", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "exportTracks" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard pendingResult == nil else {
      result(FlutterError(code: "busy", message: "A copy is already in progress.", details: nil))
      return
    }
    guard let arguments = call.arguments as? [String: Any],
      let selected = arguments["files"] as? [[String: String]], !selected.isEmpty,
      selected.allSatisfy({ !($0["path"] ?? "").isEmpty && !($0["name"] ?? "").isEmpty })
    else {
      result(FlutterError(code: "invalid_files", message: "No valid tracks selected.", details: nil))
      return
    }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard var presenter = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?
      .rootViewController else {
      result(FlutterError(code: "folder_picker", message: "Could not open the folder picker.", details: nil))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    } else {
      picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
    }
    files = selected
    pendingResult = result
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let folder = urls.first else { finish(nil); return }
    let selected = files
    DispatchQueue.global(qos: .userInitiated).async {
      let access = folder.startAccessingSecurityScopedResource()
      defer { if access { folder.stopAccessingSecurityScopedResource() } }
      var copied = 0
      var failed: [String] = []
      var errors: [String] = []
      for entry in selected {
        guard let path = entry["path"], let name = entry["name"] else { continue }
        let source = URL(fileURLWithPath: path)
        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: folder, options: [], error: &coordinationError) { destinationFolder in
          var destination: URL?
          do {
            let existing = try FileManager.default.contentsOfDirectory(atPath: destinationFolder.path)
            let names = Set(existing.map { $0.lowercased() })
            let filename = name as NSString
            let ext = filename.pathExtension
            let stem = ext.isEmpty ? name : filename.deletingPathExtension
            var candidate = name
            var suffix = 1
            while names.contains(candidate.lowercased()) {
              candidate = "\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
              suffix += 1
            }
            let target = destinationFolder.appendingPathComponent(candidate)
            // copyItem refuses to overwrite an existing file.
            destination = target
            try FileManager.default.copyItem(at: source, to: target)
          } catch {
            // Only remove a partial copy if this operation created it.
            if (error as NSError).code != NSFileWriteFileExistsError, let target = destination {
              try? FileManager.default.removeItem(at: target)
            }
            copyError = error
          }
        }
        if coordinationError == nil && copyError == nil { copied += 1 }
        else {
          failed.append(name)
          let reason = coordinationError?.localizedDescription ?? copyError?.localizedDescription ?? "Unknown error"
          errors.append("\(name): \(reason)")
        }
      }
      let response: [String: Any] = ["copied": copied, "failed": failed, "errors": errors]
      DispatchQueue.main.async { self.finish(response) }
    }
  }

  private func finish(_ value: Any?) {
    let result = pendingResult
    pendingResult = nil
    files = []
    result?(value)
  }
}
