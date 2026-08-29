import Cocoa
import FlutterMacOS

/// Bridges macOS App Sandbox security-scoped bookmarks to Flutter.
///
/// `FilePicker.platform.getDirectoryPath()` (Dart side) grants access to a
/// user-chosen directory that is only valid for the current process
/// lifetime under App Sandbox. To keep writing to that directory across app
/// relaunches, the chosen folder's URL must be persisted as a
/// security-scoped bookmark (`NSURL.bookmarkData(options: .withSecurityScope)`)
/// and re-resolved (`URL(resolvingBookmarkData:...)` +
/// `startAccessingSecurityScopedResource()`) on every subsequent launch.
///
/// Exposes MethodChannel `com.comicreader.comicReader/download_bookmark`
/// with two methods:
/// - `saveBookmark({"path": String})` -> `Bool`
/// - `resolveBookmark()` -> `String?`
class DownloadDirectoryBookmark: NSObject {
  private static let channelName = "com.comicreader.comicReader/download_bookmark"
  private static let bookmarkDefaultsKey = "download_directory_bookmark"

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "saveBookmark":
        handleSaveBookmark(call: call, result: result)
      case "resolveBookmark":
        handleResolveBookmark(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func handleSaveBookmark(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
      result(FlutterError(code: "bad_args", message: "path required", details: nil))
      return
    }
    let url = URL(fileURLWithPath: path)
    do {
      let bookmark = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      UserDefaults.standard.set(bookmark, forKey: bookmarkDefaultsKey)
      result(true)
    } catch {
      result(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
    }
  }

  private static func handleResolveBookmark(result: @escaping FlutterResult) {
    guard let bookmark = UserDefaults.standard.data(forKey: bookmarkDefaultsKey) else {
      result(nil)
      return
    }
    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      if isStale {
        // The bookmark still resolved, but macOS considers the underlying
        // reference (e.g. volume/inode metadata) stale. Re-save a fresh
        // bookmark for the resolved URL so the *next* resolution is clean,
        // while still returning the (currently valid) resolved path now.
        NSLog("DownloadDirectoryBookmark: resolved bookmark is stale, re-saving")
        if let refreshed = try? url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        ) {
          UserDefaults.standard.set(refreshed, forKey: bookmarkDefaultsKey)
        }
      }
      _ = url.startAccessingSecurityScopedResource()
      result(url.path)
    } catch {
      NSLog("DownloadDirectoryBookmark: failed to resolve bookmark: \(error.localizedDescription)")
      result(nil)
    }
  }
}
