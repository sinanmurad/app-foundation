import Flutter
import UIKit

/// Share Extension ile Flutter arasındaki köprü.
///
/// Share Extension, paylaşılan içeriği App Group UserDefaults içindeki bir
/// kuyruğa yazar. Flutter tarafı (lib/services/share_service.dart) bu
/// kuyruğu `popSharedPayload` ile tek tek boşaltır.
///
/// Yeni uygulamada değiştirmen gereken tek şey bundle ID'dir; tool/rename.dart
/// `com.example.starter` geçen her yeri otomatik değiştirir.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  static let appGroupId = "group.com.example.starter"
  static let sharedQueueKey = "shared_payload_queue"
  static let channelName = "app.starter/share"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      AppDelegate.configureShareChannel(on: controller)
    }

    return didFinish
  }

  static func configureShareChannel(on controller: FlutterViewController) {
    let shareChannel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: controller.binaryMessenger
    )
    shareChannel.setMethodCallHandler { call, result in
      let ud = UserDefaults(suiteName: appGroupId)
      switch call.method {
      case "popSharedPayload":
        var queue = ud?.array(forKey: sharedQueueKey) as? [[String: Any]] ?? []
        if let first = queue.first {
          queue.removeFirst()
          ud?.set(queue, forKey: sharedQueueKey)
          ud?.synchronize()
          result(first)
        } else {
          result(nil)
        }
      case "hasQueuedShares":
        let queue = ud?.array(forKey: sharedQueueKey) as? [[String: Any]] ?? []
        result(!queue.isEmpty)
      case "clearSharedPayloadQueue":
        ud?.removeObject(forKey: sharedQueueKey)
        ud?.synchronize()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      if let controller = self.window?.rootViewController as? FlutterViewController {
        AppDelegate.configureShareChannel(on: controller)
      }
    }
  }
}
