import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    bindShareChannelIfPossible()
  }
  
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    bindShareChannelIfPossible()
  }
  
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      if let controller = self.window?.rootViewController as? FlutterViewController {
        AppDelegate.configureShareChannel(on: controller)
      }
    }
  }
  
  private func bindShareChannelIfPossible() {
    if let flutterController = window?.rootViewController as? FlutterViewController {
      AppDelegate.configureShareChannel(on: flutterController)
    }
  }
}