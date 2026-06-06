/**
 * @file AppDelegate+FirebasexMessaging.h
 * @brief AppDelegate category that integrates Firebase Cloud Messaging with the application lifecycle.
 *
 * Configures UNUserNotificationCenter and FIRMessaging delegates, handles incoming
 * remote notifications, manages foreground notification display, and processes
 * notification tap responses.
 */

#import <Cordova/CDVAppDelegate.h>
#if __has_include("FirebasexCorePlugin.h")
    // Cordova-ios 7 / CocoaPods: Files are compiled in a flat target structure
    #import "FirebasexCorePlugin.h"
#else
    // Cordova-ios 8+ / SPM: Plugins are isolated Swift Package modules
    @import cordova_plugin_firebasex_core;
#endif

@import UserNotifications;
@import FirebaseMessaging;

/**
 * NSNotification names posted for FCM lifecycle events.
 * These notifications allow other parts of the app to observe messaging events.
 */
/** Posted when an FCM registration token is received or refreshed. */
extern NSString *const FirebasexFCMTokenReceived;
/** Posted when an APNs device token is received. */
extern NSString *const FirebasexAPNSTokenReceived;
/** Posted when a remote notification is received. */
extern NSString *const FirebasexNotificationReceived;
/** Posted when a notification is tapped by the user. */
extern NSString *const FirebasexNotificationTapped;
/** Posted when the user opens notification settings (iOS 12+). */
extern NSString *const FirebasexNotificationSettings;

/**
 * CDVAppDelegate category for Firebase Cloud Messaging.
 *
 * Registers as FIRMessagingDelegate and UNUserNotificationCenterDelegate to handle
 * FCM token events, remote notification delivery, foreground notification display,
 * and notification tap responses including actionable notifications.
 */
@interface CDVAppDelegate (FirebasexMessaging) <UNUserNotificationCenterDelegate, FIRMessagingDelegate>
@end
