import Flutter
import UIKit
import nextbell_platform

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    let unhandled = contexts.filter { !NextbellPlatformPlugin.handleURL($0.url) }
    if !unhandled.isEmpty { super.scene(scene, openURLContexts: Set(unhandled)) }
  }
}
