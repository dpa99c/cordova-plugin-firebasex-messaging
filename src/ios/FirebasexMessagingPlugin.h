/**
 * @file FirebasexMessagingPlugin.h
 * @brief Cordova plugin interface for Firebase Cloud Messaging on iOS.
 *
 * Provides APIs for FCM token management, push notification permissions
 * (including critical alerts), topic subscriptions, badge control,
 * auto-init configuration, and notification delivery to JavaScript.
 * Notification channel methods are present as no-op stubs for Android API compatibility.
 */
#import <Cordova/CDV.h>
#if __has_include("FirebasexCorePlugin.h")
    // Cordova-ios 7 / CocoaPods: Files are compiled in a flat target structure
    #import "FirebasexCorePlugin.h"
#else
    // Cordova-ios 8+ / SPM: Plugins are isolated Swift Package modules
    @import cordova_plugin_firebasex_core;
#endif

@import UserNotifications;

/**
 * @interface FirebasexMessagingPlugin
 * @abstract Cordova plugin for Firebase Cloud Messaging on iOS.
 *
 * Manages FCM and APNs token lifecycle, push notification permissions,
 * topic subscriptions, badge numbers, auto-initialization, and message
 * delivery to the JavaScript layer. Supports actionable notifications
 * via pn-actions.json configuration and immediate message payload
 * delivery in background when enabled.
 */
@interface FirebasexMessagingPlugin : CDVPlugin

/** Returns the singleton plugin instance. */
+ (FirebasexMessagingPlugin *)instance;

/** Delivers any queued notifications to the JavaScript callback. */
- (void)sendPendingNotifications;
/**
 * Delivers a notification to the JavaScript callback, or queues it if no callback is registered.
 * @param userInfo The notification payload dictionary.
 */
- (void)sendNotification:(NSDictionary *)userInfo;
/**
 * Delivers an FCM token to the JavaScript token-refresh callback.
 * @param token The FCM registration token.
 */
- (void)sendToken:(NSString *)token;
/**
 * Delivers an APNs token to the JavaScript APNs-token callback.
 * @param token The APNs token as a hex string.
 */
- (void)sendApnsToken:(NSString *)token;
/** Notifies JavaScript that the user opened notification settings. */
- (void)sendOpenNotificationSettings;

// Plugin API

/** Retrieves the current FCM registration token. */
- (void)getToken:(CDVInvokedUrlCommand *)command;
/** Retrieves the APNs device token as a hex string. Cordova API entry point. */
- (void)getAPNSToken:(CDVInvokedUrlCommand *)command;
/**
 * Returns the APNs device token as a hexadecimal string.
 *
 * @return The hex token string, or @c nil if no APNs token is available yet.
 */
- (nullable NSString *)getAPNSToken;
/** Registers a persistent callback for FCM token refresh events. */
- (void)onTokenRefresh:(CDVInvokedUrlCommand *)command;
/** Registers a persistent callback for APNs token events. */
- (void)onApnsTokenReceived:(CDVInvokedUrlCommand *)command;
/** Registers a persistent callback for incoming push messages. */
- (void)onMessageReceived:(CDVInvokedUrlCommand *)command;
/** Registers a callback for notification settings open events (iOS 12+). */
- (void)onOpenSettings:(CDVInvokedUrlCommand *)command;
/** Subscribes to an FCM topic. Argument: topic name string. */
- (void)subscribe:(CDVInvokedUrlCommand *)command;
/** Unsubscribes from an FCM topic. Argument: topic name string. */
- (void)unsubscribe:(CDVInvokedUrlCommand *)command;
/** Deletes the FCM token and optionally re-registers if auto-init is enabled. */
- (void)unregister:(CDVInvokedUrlCommand *)command;
/** Checks whether notification permission is granted. Returns boolean. */
- (void)hasPermission:(CDVInvokedUrlCommand *)command;
/** Requests notification permission from the user. Accepts optional ProvidesAppNotificationSettings flag. */
- (void)grantPermission:(CDVInvokedUrlCommand *)command;
/** Checks whether critical alert permission is granted (iOS 12+). Returns boolean. */
- (void)hasCriticalPermission:(CDVInvokedUrlCommand *)command;
/** Requests critical alert permission (iOS 12+). Requires Apple entitlement. */
- (void)grantCriticalPermission:(CDVInvokedUrlCommand *)command;
/** Checks whether FCM auto-init is enabled. Returns boolean. */
- (void)isAutoInitEnabled:(CDVInvokedUrlCommand *)command;
/** Enables or disables FCM auto-initialization. Argument: boolean. */
- (void)setAutoInitEnabled:(CDVInvokedUrlCommand *)command;
/** Sets the app icon badge number. Argument: integer. */
- (void)setBadgeNumber:(CDVInvokedUrlCommand *)command;
/** Gets the current app icon badge number. Returns integer. */
- (void)getBadgeNumber:(CDVInvokedUrlCommand *)command;
/** Removes all delivered notifications from Notification Center. */
- (void)clearAllNotifications:(CDVInvokedUrlCommand *)command;
/** No-op stub for Android notification channel creation. */
- (void)createChannel:(CDVInvokedUrlCommand *)command;
/** No-op stub for Android default channel configuration. */
- (void)setDefaultChannel:(CDVInvokedUrlCommand *)command;
/** No-op stub for Android channel deletion. */
- (void)deleteChannel:(CDVInvokedUrlCommand *)command;
/** No-op stub for Android channel listing. Returns empty array. */
- (void)listChannels:(CDVInvokedUrlCommand *)command;

/** Whether Firebase Cloud Messaging is enabled (controlled by FIREBASEX_IOS_FCM_ENABLED). */
@property(nonatomic, readonly) BOOL isFCMEnabled;
/** Callback ID for the persistent notification message listener. */
@property(nonatomic, copy) NSString *notificationCallbackId;
/** Callback ID for the notification settings open listener. */
@property(nonatomic, copy) NSString *openSettingsCallbackId;
/** Callback ID for the persistent FCM token refresh listener. */
@property(nonatomic, copy) NSString *tokenRefreshCallbackId;
/** Callback ID for the persistent APNs token refresh listener. */
@property(nonatomic, copy) NSString *apnsTokenRefreshCallbackId;
/** Stack of notification payloads queued for delivery when no JS callback is registered. */
@property(nonatomic, retain) NSMutableArray *notificationStack;

@end
