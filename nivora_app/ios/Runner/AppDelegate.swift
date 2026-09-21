import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // WITHOUT THIS, A NOTIFICATION THAT ARRIVES WHILE NIVORA IS OPEN IS NEVER SHOWN. iOS asks the
    // notification center's delegate whether to present a banner in the foreground, and nobody
    // sets that delegate for us: FlutterPlugin.h says plugins receive these events only when the
    // app delegate is registered as the UNUserNotificationCenterDelegate, and the engine never
    // assigns it itself. FlutterAppDelegate already conforms and forwards each call to every
    // plugin, including flutter_local_notifications, whose README and example both do this.
    //
    // It belongs HERE, before super, not in didInitializeImplicitFlutterEngine below. Plugins
    // register later, when the scene connects, so firebase_messaging then finds a delegate that
    // already forwards to plugins and chains onto it instead of replacing it.
    //
    // Written exactly as the plugin's own example (flutter_local_notifications 22.3.0,
    // example/ios/Runner/AppDelegate.swift), which uses this same FlutterImplicitEngineDelegate
    // pattern. The example also calls setPluginRegistrantCallback; that is only for notification
    // action buttons handled in a background isolate, which this app does not have.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
