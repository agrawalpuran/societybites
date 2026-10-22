import Flutter
import UIKit
import UserNotifications
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    Messaging.messaging().appDidReceiveMessage(notification.request.content.userInfo)
    // Flutter/Firebase often complete with [] while the app is open, so the
    // banner never appears. Union in alert + sound so iOS matches Android.
    super.userNotificationCenter(
      center,
      willPresent: notification,
      withCompletionHandler: { options in
        if #available(iOS 14.0, *) {
          completionHandler(options.union([.banner, .list, .sound, .badge]))
        } else {
          completionHandler(options.union([.alert, .sound, .badge]))
        }
      }
    )
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    UIApplication.shared.registerForRemoteNotifications()
  }
}
