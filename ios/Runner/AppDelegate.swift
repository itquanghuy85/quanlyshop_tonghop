import Flutter
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

// Mark AppDelegate as @MainActor to fix Sendable warnings in Xcode 16.2
@main
@MainActor
@objc class AppDelegate: FlutterAppDelegate {
  private(set) static var lastApnsRegistrationError: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Firebase
    FirebaseApp.configure()
    
    // Register for remote notifications
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { _, _ in }
      )
    } else {
      let settings: UIUserNotificationSettings =
        UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      application.registerUserNotificationSettings(settings)
    }
    
    application.registerForRemoteNotifications()
    
    // Set Firebase Messaging delegate
    Messaging.messaging().delegate = self
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Handle APNs token registration
  override func application(_ application: UIApplication,
                           didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    AppDelegate.lastApnsRegistrationError = nil
    #if DEBUG
    Messaging.messaging().setAPNSToken(deviceToken, type: .sandbox)
    #else
    Messaging.messaging().setAPNSToken(deviceToken, type: .prod)
    #endif
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    AppDelegate.lastApnsRegistrationError = error.localizedDescription
    NSLog("APNs registration failed: %@", error.localizedDescription)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
  nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    let dataDict: [String: String] = ["token": fcmToken ?? ""]
    // Use MainActor to post notification safely
    Task { @MainActor in
      NotificationCenter.default.post(
        name: Notification.Name("FCMToken"),
        object: nil,
        userInfo: dataDict
      )
    }
  }
}
