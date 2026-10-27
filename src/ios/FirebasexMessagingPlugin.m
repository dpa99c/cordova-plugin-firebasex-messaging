/**
 * @file FirebasexMessagingPlugin.m
 * @brief Cordova plugin implementation for Firebase Cloud Messaging on iOS.
 *
 * Handles FCM token management, APNs token retrieval, push notification
 * permissions (standard and critical alerts), topic subscriptions, badge
 * control, auto-init configuration, actionable notifications from
 * pn-actions.json, and message delivery queueing/forwarding to JavaScript.
 */
#import "FirebasexMessagingPlugin.h"
#import "AppDelegate+FirebasexMessaging.h"
#import "FirebasePluginMessageReceiverManager.h"
#import <Cordova/CDV.h>
#if __has_include("FirebasexCorePlugin.h")
    // Cordova-ios 7 / CocoaPods: Files are compiled in a flat target structure
    #import "AppDelegate+FirebasexCore.h"
#else
    // Cordova-ios 8+ / SPM: Plugins are isolated Swift Package modules
    @import cordova_plugin_firebasex_core;
#endif
@import FirebaseMessaging;
@import UserNotifications;

@interface FirebasexMessagingPlugin ()
/** Stable fingerprint of a payload, ignoring the keys this plugin adds on delivery. */
+ (NSString *)fingerprintForPayload:(NSDictionary *)userInfo;
/** Whether a payload with this fingerprint was already handed to JS or queued for it. */
+ (BOOL)wasDelivered:(NSDictionary *)userInfo;
/** Records a payload as handed to JS or queued for it. */
+ (void)rememberDelivered:(NSDictionary *)userInfo;
@end

@implementation FirebasexMessagingPlugin

@synthesize openSettingsCallbackId;
@synthesize notificationCallbackId;
@synthesize tokenRefreshCallbackId;
@synthesize apnsTokenRefreshCallbackId;
@synthesize notificationStack;

/** Log tag prefix for this plugin. */
static NSString *const LOG_TAG = @"FirebasexMessaging[native]";
/** Maximum number of notifications that can be queued before the oldest is dropped. */
static NSInteger const kNotificationStackSize = 32;
/** Info.plist key controlling whether FCM is enabled. */
static NSString *const FIREBASEX_IOS_FCM_ENABLED = @"FIREBASEX_IOS_FCM_ENABLED";

/** Singleton instance of this plugin. */
static FirebasexMessagingPlugin *messagingInstance;
/** Whether the app has already registered for remote notifications. */
static BOOL registeredForRemoteNotifications = NO;
/** Whether an openSettings event was emitted before a callback was registered. */
static BOOL openSettingsEmitted = NO;
/** Whether incoming messages should be delivered to JS immediately even when backgrounded. */
static BOOL immediateMessagePayloadDelivery = NO;
/** NSUserDefaults key holding the fingerprints of payloads already handed to JS (or queued for it). */
static NSString *const kDeliveredFingerprintsKey = @"FirebasexMessagingDeliveredFingerprints";
/** How many fingerprints are kept. */
static NSUInteger const kDeliveredFingerprintsLimit = 200;
/** NSUserDefaults key holding the messages queued for JS, so they survive the app being terminated in the background. */
static NSString *const kPendingNotificationsKey = @"FirebasexMessagingPendingNotifications";

+ (FirebasexMessagingPlugin *)instance {
    return messagingInstance;
}

/**
 * Initialises the plugin: stores the singleton instance, reads configuration
 * flags, sets up actionable notification categories from pn-actions.json,
 * registers for app lifecycle events, and checks notification permission.
 */
- (void)pluginInitialize {
    NSLog(@"Starting Firebase Messaging plugin");
    messagingInstance = self;

    @try {
        immediateMessagePayloadDelivery = [[[NSBundle mainBundle]
            objectForInfoDictionaryKey:@"FIREBASE_MESSAGING_IMMEDIATE_PAYLOAD_DELIVERY"] boolValue];

        _isFCMEnabled = [[FirebasexCorePlugin sharedInstance]
            getGooglePlistFlagWithDefaultValue:FIREBASEX_IOS_FCM_ENABLED
                                  defaultValue:YES];

        if (!self.isFCMEnabled) {
            [[FirebasexCorePlugin sharedInstance] _logInfo:@"Firebase Cloud Messaging is disabled, see IOS_FCM_ENABLED variable of the plugin"];
        }

        // cordova-ios 8: the core plugin's +load swizzle of
        // application:didFinishLaunchingWithOptions: does not take effect, so
        // FirebasexAppDidFinishLaunching is never posted and the delegates are never
        // installed. Make sure both the core launch setup and our delegate setup ran.
        id appDelegate = [UIApplication sharedApplication].delegate;
        if ([appDelegate isKindOfClass:[CDVAppDelegate class]]) {
            [(CDVAppDelegate *)appDelegate firebasexCoreEnsureLaunched];
            [(CDVAppDelegate *)appDelegate firebasexMessagingSetup];
        }

        // Restore messages that were queued (app in background, no JS callback yet) before the
        // app was terminated; they are delivered once a callback is registered in the foreground.
        NSArray *persisted = [[NSUserDefaults standardUserDefaults] arrayForKey:kPendingNotificationsKey];
        if (persisted.count > 0) {
            self.notificationStack = [persisted mutableCopy];
            NSLog(@"%@ restored %lu queued message(s) from a previous run", LOG_TAG, (unsigned long)persisted.count);
        }

        // Set actionable categories if pn-actions.json exist in bundle
        [self setActionableNotifications];

        // Flush pending notifications when app returns to foreground
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onAppDidBecomeActive)
                                                     name:FirebasexAppDidBecomeActive
                                                   object:nil];

        // Check for permission and register for remote notifications if granted
        if (self.isFCMEnabled) {
            [self _hasPermission:^(BOOL result) {
            }];
        }
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
    }
}

/** Called when the app becomes active; flushes any queued notifications and picks up pushes the app was not woken for. */
- (void)onAppDidBecomeActive {
    [self sendPendingNotifications];
    [self deliverNotificationsFromNotificationCenter];
}

/**
 * Called by Cordova when the web view starts a new page load. Callback ids belong to the
 * page that registered them and are invalid after a reload, so drop them: messages are
 * queued until the new page calls onMessageReceived again (which flushes the queue).
 */
- (void)onReset {
    if (self.notificationCallbackId != nil) {
        [[FirebasexCorePlugin sharedInstance] _logMessage:@"onReset: page is reloading, dropping the onMessageReceived callback until it is registered again"];
    }
    self.notificationCallbackId = nil;
    self.tokenRefreshCallbackId = nil;
    self.apnsTokenRefreshCallbackId = nil;
    self.openSettingsCallbackId = nil;
}

/**
 * Reads pn-actions.json from the app bundle and registers actionable
 * notification categories with UNUserNotificationCenter.
 *
 * Each action in the JSON can specify:
 * - id: action identifier
 * - title: localised button title
 * - foreground: if true, launches the app when tapped
 * - destructive: if true, shows the action in a destructive style
 */
- (void)setActionableNotifications {
    @try {
        if (!self.isFCMEnabled) {
            return;
        }

        NSString *path = [[NSBundle mainBundle] pathForResource:@"pn-actions" ofType:@"json"];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data == nil) return;
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];

        NSMutableSet *categories = [[NSMutableSet alloc] init];
        NSArray *actionsArray = [dict objectForKey:@"PushNotificationActions"];
        for (NSDictionary *item in actionsArray) {
            NSMutableArray *buttons = [NSMutableArray new];
            NSString *category = [item objectForKey:@"category"];

            NSArray *actions = [item objectForKey:@"actions"];
            for (NSDictionary *action in actions) {
                NSString *actionId = [action objectForKey:@"id"];
                NSString *actionTitle = [action objectForKey:@"title"];
                UNNotificationActionOptions options = UNNotificationActionOptionNone;

                id mode = [action objectForKey:@"foreground"];
                if (mode != nil && (([mode isKindOfClass:[NSString class]] && [mode isEqualToString:@"true"]) || [mode boolValue])) {
                    options |= UNNotificationActionOptionForeground;
                }
                id destructive = [action objectForKey:@"destructive"];
                if (destructive != nil && (([destructive isKindOfClass:[NSString class]] && [destructive isEqualToString:@"true"]) || [destructive boolValue])) {
                    options |= UNNotificationActionOptionDestructive;
                }

                [buttons addObject:[UNNotificationAction actionWithIdentifier:actionId
                                                                        title:NSLocalizedString(actionTitle, nil)
                                                                      options:options]];
            }

            [categories addObject:[UNNotificationCategory categoryWithIdentifier:category
                                                                         actions:buttons
                                                               intentIdentifiers:@[]
                                                                         options:UNNotificationCategoryOptionNone]];
        }

        [[UNUserNotificationCenter currentNotificationCenter] setNotificationCategories:categories];

    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
    }
}

#pragma mark - Plugin API

/** Retrieves the current FCM registration token. */
- (void)getToken:(CDVInvokedUrlCommand *)command {
    [self _getToken:^(NSString *token, NSError *error) {
        [[FirebasexCorePlugin sharedInstance] handleStringResultWithPotentialError:error
                                                                          command:command
                                                                           result:token];
    }];
}

/**
 * Internal helper that fetches the FCM token asynchronously.
 * @param completeBlock Called with the token and any error.
 */
- (void)_getToken:(void (^)(NSString *token, NSError *error))completeBlock {
    @try {
        [[FIRMessaging messaging] tokenWithCompletion:^(NSString *token, NSError *error) {
            @try {
                completeBlock(token, error);
            } @catch (NSException *exception) {
                [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
            }
        }];
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
    }
}

/** Retrieves the APNs device token as a hex string. Returns null if unavailable. */
- (void)getAPNSToken:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsString:[self getAPNSToken]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

/**
 * Returns the APNs device token as a hexadecimal string.
 * @return The hex token string, or nil if no token is available.
 */
- (NSString *)getAPNSToken {
    NSString *hexToken = nil;
    NSData *apnsToken = [FIRMessaging messaging].APNSToken;
    if (apnsToken) {
        hexToken = [self hexadecimalStringFromData:apnsToken];
    }
    return hexToken;
}

/**
 * Converts raw NSData to a hexadecimal string representation.
 * @param data The binary data to convert.
 * @return A lowercase hex string, or nil if data is empty.
 */
- (NSString *)hexadecimalStringFromData:(NSData *)data {
    NSUInteger dataLength = data.length;
    if (dataLength == 0) return nil;

    const unsigned char *dataBuffer = data.bytes;
    NSMutableString *hexString = [NSMutableString stringWithCapacity:(dataLength * 2)];
    for (int i = 0; i < dataLength; ++i) {
        [hexString appendFormat:@"%02x", dataBuffer[i]];
    }
    return [hexString copy];
}

/**
 * Registers a persistent callback for FCM token refresh events.
 * Immediately fetches and returns the current token if an APNs token is available.
 */
- (void)onTokenRefresh:(CDVInvokedUrlCommand *)command {
    self.tokenRefreshCallbackId = command.callbackId;
    NSString *apnsToken = [self getAPNSToken];
    if (apnsToken != nil) {
        [self _getToken:^(NSString *token, NSError *error) {
            if (error == nil && token != nil) {
                [self sendToken:token];
            }
        }];
    }
}

/** Registers a persistent callback for APNs token events. Returns the current token immediately if available. */
- (void)onApnsTokenReceived:(CDVInvokedUrlCommand *)command {
    self.apnsTokenRefreshCallbackId = command.callbackId;
    @try {
        NSString *apnsToken = [self getAPNSToken];
        if (apnsToken != nil) {
            [self sendApnsToken:apnsToken];
        }
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
    }
}

/** Registers a persistent callback for incoming push messages. Flushes any queued notifications immediately. */
- (void)onMessageReceived:(CDVInvokedUrlCommand *)command {
    self.notificationCallbackId = command.callbackId;
    [[FirebasexCorePlugin sharedInstance] _logMessage:[NSString stringWithFormat:@"onMessageReceived: callback %@ registered, %lu message(s) pending", command.callbackId, (unsigned long)[self.notificationStack count]]];
    [self sendPendingNotifications];
    [self deliverNotificationsFromNotificationCenter];
}

/**
 * Registers a callback for notification settings open events (iOS 12+).
 * If an event was already emitted before this callback was registered,
 * fires it immediately.
 */
- (void)onOpenSettings:(CDVInvokedUrlCommand *)command {
    @try {
        self.openSettingsCallbackId = command.callbackId;
        if (openSettingsEmitted == YES) {
            [[FirebasexCorePlugin sharedInstance] sendPluginSuccessAndKeepCallback:self.openSettingsCallbackId
                                                                          command:self.commandDelegate];
            openSettingsEmitted = NO;
        }
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
    }
}

#pragma mark - Permissions

/** Checks whether standard notification permission (alert) is granted. Also registers for remote notifications if permitted. */
- (void)hasPermission:(CDVInvokedUrlCommand *)command {
    @try {
        [self _hasPermission:^(BOOL enabled) {
            CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                messageAsBool:enabled];
            [self.commandDelegate sendPluginResult:commandResult callbackId:command.callbackId];
        }];
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
    }
}

/**
 * Internal helper that checks notification permission status.
 * @param completeBlock Called with YES if alert notifications are enabled.
 */
- (void)_hasPermission:(void (^)(BOOL result))completeBlock {
    @try {
        [[UNUserNotificationCenter currentNotificationCenter]
            getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *_Nonnull settings) {
                @try {
                    BOOL enabled = NO;
                    if (settings.alertSetting == UNNotificationSettingEnabled) {
                        enabled = YES;
                        [self registerForRemoteNotifications];
                    }
                    NSLog(@"_hasPermission: %@", enabled ? @"YES" : @"NO");
                    completeBlock(enabled);
                } @catch (NSException *exception) {
                    [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
                }
            }];
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
    }
}

/**
 * Requests notification permission from the user.
 * Returns an error if permission is already granted. On success, registers
 * for remote notifications and passes the granted result to the callback.
 * Accepts an optional first argument for ProvidesAppNotificationSettings (iOS 12+).
 */
- (void)grantPermission:(CDVInvokedUrlCommand *)command {
    NSLog(@"grantPermission");
    @try {
        [self _hasPermission:^(BOOL enabled) {
            @try {
                if (enabled) {
                    NSString *message = @"Permission is already granted - call hasPermission() to check before calling grantPermission()";
                    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                                      messageAsString:message];
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                } else {
                    [UNUserNotificationCenter currentNotificationCenter].delegate =
                        (id<UNUserNotificationCenterDelegate> _Nullable)self;
                    BOOL requestWithProvidesAppNotificationSettings = [[command argumentAtIndex:0] boolValue];
                    UNAuthorizationOptions authOptions = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
                    if (@available(iOS 12.0, *)) {
                        if (requestWithProvidesAppNotificationSettings) {
                            authOptions = authOptions | UNAuthorizationOptionProvidesAppNotificationSettings;
                        }
                    }

                    [[UNUserNotificationCenter currentNotificationCenter]
                        requestAuthorizationWithOptions:authOptions
                                      completionHandler:^(BOOL granted, NSError *_Nullable error) {
                            @try {
                                NSLog(@"requestAuthorizationWithOptions: granted=%@", granted ? @"YES" : @"NO");
                                if (error == nil && granted) {
                                    [UNUserNotificationCenter currentNotificationCenter].delegate = [CDVAppDelegate instance];
                                    [self registerForRemoteNotifications];
                                }
                                [[FirebasexCorePlugin sharedInstance] handleBoolResultWithPotentialError:error
                                                                                                command:command
                                                                                                 result:granted];
                            } @catch (NSException *exception) {
                                [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
                            }
                        }];
                }
            } @catch (NSException *exception) {
                [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
            }
        }];
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
    }
}

/** Checks whether critical alert permission is granted (iOS 12+). Returns NO on earlier iOS versions. */
- (void)hasCriticalPermission:(CDVInvokedUrlCommand *)command {
    @try {
        [self _hasCriticalPermission:^(BOOL enabled) {
            CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                messageAsBool:enabled];
            [self.commandDelegate sendPluginResult:commandResult callbackId:command.callbackId];
        }];
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
    }
}

/**
 * Internal helper that checks critical alert permission status (iOS 12+).
 * @param completeBlock Called with YES if critical alerts are enabled.
 */
- (void)_hasCriticalPermission:(void (^)(BOOL result))completeBlock {
    @try {
        if (@available(iOS 12.0, *)) {
            [[UNUserNotificationCenter currentNotificationCenter]
                getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *_Nonnull settings) {
                    @try {
                        BOOL enabled = NO;
                        if (settings.criticalAlertSetting == UNNotificationSettingEnabled) {
                            enabled = YES;
                            [self registerForRemoteNotifications];
                        }
                        NSLog(@"_hasCriticalPermission: %@", enabled ? @"YES" : @"NO");
                        completeBlock(enabled);
                    } @catch (NSException *exception) {
                        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
                    }
                }];
        } else {
            completeBlock(NO);
        }
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
    }
}

/**
 * Requests critical alert permission (iOS 12+).
 * Critical alerts can bypass Do Not Disturb and the ringer switch.
 * Requires a special Apple entitlement. Returns false on earlier iOS versions.
 */
- (void)grantCriticalPermission:(CDVInvokedUrlCommand *)command {
    NSLog(@"grantCriticalPermission");
    @try {
        if (@available(iOS 12.0, *)) {
            [self _hasCriticalPermission:^(BOOL enabled) {
                @try {
                    if (enabled) {
                        NSString *message = @"Critical permission is already granted - call hasCriticalPermission() to check before calling grantCriticalPermission()";
                        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                                          messageAsString:message];
                        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                    } else {
                        [UNUserNotificationCenter currentNotificationCenter].delegate =
                            (id<UNUserNotificationCenterDelegate> _Nullable)self;
                        UNAuthorizationOptions authOptions = UNAuthorizationOptionCriticalAlert;

                        [[UNUserNotificationCenter currentNotificationCenter]
                            requestAuthorizationWithOptions:authOptions
                                          completionHandler:^(BOOL granted, NSError *_Nullable error) {
                                @try {
                                    NSLog(@"requestAuthorizationWithOptions: granted=%@", granted ? @"YES" : @"NO");
                                    [[FirebasexCorePlugin sharedInstance] handleBoolResultWithPotentialError:error
                                                                                                    command:command
                                                                                                     result:granted];
                                } @catch (NSException *exception) {
                                    [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
                                }
                            }];
                    }
                } @catch (NSException *exception) {
                    [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
                }
            }];
        } else {
            [[FirebasexCorePlugin sharedInstance] handleBoolResultWithPotentialError:nil command:command result:false];
        }
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
    }
}

/**
 * Registers for remote notifications with APNs on the main thread.
 * Only registers once per app session.
 */
- (void)registerForRemoteNotifications {
    NSLog(@"registerForRemoteNotifications");
    if (registeredForRemoteNotifications) return;

    [[FirebasexCorePlugin sharedInstance] runOnMainThread:^{
        @try {
            [[UIApplication sharedApplication] registerForRemoteNotifications];
        } @catch (NSException *exception) {
            [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
        }
        registeredForRemoteNotifications = YES;
    }];
}

#pragma mark - Subscriptions

/** Subscribes to an FCM topic. Argument: topic name string. */
- (void)subscribe:(CDVInvokedUrlCommand *)command {
    @try {
        NSString *topic = [NSString stringWithFormat:@"%@", [command.arguments objectAtIndex:0]];
        [[FIRMessaging messaging] subscribeToTopic:topic completion:^(NSError *_Nullable error) {
            [[FirebasexCorePlugin sharedInstance] handleEmptyResultWithPotentialError:error command:command];
        }];

        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
    }
}

/** Unsubscribes from an FCM topic. Argument: topic name string. */
- (void)unsubscribe:(CDVInvokedUrlCommand *)command {
    @try {
        NSString *topic = [NSString stringWithFormat:@"%@", [command.arguments objectAtIndex:0]];
        [[FIRMessaging messaging] unsubscribeFromTopic:topic completion:^(NSError *_Nullable error) {
            [[FirebasexCorePlugin sharedInstance] handleEmptyResultWithPotentialError:error command:command];
        }];

        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
    }
}

/**
 * Deletes the current FCM token. If auto-init is enabled, a new token
 * is automatically requested after deletion.
 */
- (void)unregister:(CDVInvokedUrlCommand *)command {
    @try {
        __block NSError *error = nil;
        [[FIRMessaging messaging] deleteTokenWithCompletion:^(NSError *_Nullable deleteTokenError) {
            if (error == nil && deleteTokenError != nil) error = deleteTokenError;
            if ([FIRMessaging messaging].isAutoInitEnabled) {
                [self _getToken:^(NSString *token, NSError *getError) {
                    if (error == nil && getError != nil) error = getError;
                    [[FirebasexCorePlugin sharedInstance] handleEmptyResultWithPotentialError:error command:command];
                }];
            } else {
                [[FirebasexCorePlugin sharedInstance] handleEmptyResultWithPotentialError:error command:command];
            }
        }];
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
    }
}

#pragma mark - Auto-init

/** Enables or disables FCM auto-initialization on the main thread. */
- (void)setAutoInitEnabled:(CDVInvokedUrlCommand *)command {
    @try {
        bool enabled = [[command.arguments objectAtIndex:0] boolValue];
        [[FirebasexCorePlugin sharedInstance] runOnMainThread:^{
            @try {
                [FIRMessaging messaging].autoInitEnabled = enabled;
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            } @catch (NSException *exception) {
                [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
            }
        }];
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
    }
}

/** Returns whether FCM auto-init is enabled. Runs on the main thread. */
- (void)isAutoInitEnabled:(CDVInvokedUrlCommand *)command {
    @try {
        [[FirebasexCorePlugin sharedInstance] runOnMainThread:^{
            @try {
                bool enabled = [FIRMessaging messaging].isAutoInitEnabled;
                CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                                    messageAsBool:enabled];
                [self.commandDelegate sendPluginResult:commandResult callbackId:command.callbackId];
            } @catch (NSException *exception) {
                [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
            }
        }];
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
    }
}

#pragma mark - Badge

/** Sets the app icon badge number. Runs on the main thread. */
- (void)setBadgeNumber:(CDVInvokedUrlCommand *)command {
    @try {
        int number = [[command.arguments objectAtIndex:0] intValue];
        [[FirebasexCorePlugin sharedInstance] runOnMainThread:^{
            @try {
                [[UIApplication sharedApplication] setApplicationIconBadgeNumber:number];
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            } @catch (NSException *exception) {
                [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
            }
        }];
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
    }
}

/** Returns the current app icon badge number. Runs on the main thread. */
- (void)getBadgeNumber:(CDVInvokedUrlCommand *)command {
    [[FirebasexCorePlugin sharedInstance] runOnMainThread:^{
        @try {
            long badge = [[UIApplication sharedApplication] applicationIconBadgeNumber];
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                              messageAsDouble:badge];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } @catch (NSException *exception) {
            [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
        }
    }];
}

#pragma mark - Notifications

/**
 * Clears all delivered notifications from Notification Center.
 * Uses the badge number toggle trick (set to 1 then 0) to clear them.
 */
- (void)clearAllNotifications:(CDVInvokedUrlCommand *)command {
    [[FirebasexCorePlugin sharedInstance] runOnMainThread:^{
        @try {
            [[UIApplication sharedApplication] setApplicationIconBadgeNumber:1];
            [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        } @catch (NSException *exception) {
            [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithContext:exception:command];
        }
    }];
}

#pragma mark - Channels (iOS stubs)

/** No-op stub for Android notification channel creation. Returns success immediately. */
- (void)createChannel:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

/** No-op stub for Android default channel configuration. Returns success immediately. */
- (void)setDefaultChannel:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

/** No-op stub for Android channel deletion. Returns success immediately. */
- (void)deleteChannel:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

/** No-op stub for Android channel listing. Returns empty array. */
- (void)listChannels:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                      messageAsArray:@[]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

#pragma mark - Queue persistence

/**
 * Returns a copy of a payload value that NSUserDefaults can store: NSNull entries are dropped
 * and any other non-property-list object is replaced by its description. APNs payloads are
 * JSON, so in practice only a JSON null needs this.
 */
static id FirebasexMessagingPropertyListValue(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)value count]];
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            id converted = FirebasexMessagingPropertyListValue(obj);
            if (converted != nil) {
                copy[[key isKindOfClass:[NSString class]] ? key : [key description]] = converted;
            }
        }];
        return copy;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *copy = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
        for (id obj in (NSArray *)value) {
            id converted = FirebasexMessagingPropertyListValue(obj);
            if (converted != nil) {
                [copy addObject:converted];
            }
        }
        return copy;
    }
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSDate class]] || [value isKindOfClass:[NSData class]]) {
        return value;
    }
    if (value == nil || [value isKindOfClass:[NSNull class]]) {
        return nil;
    }
    return [value description];
}

/** Writes a queue to NSUserDefaults; an empty queue removes the key. */
static void FirebasexMessagingWritePendingQueue(NSArray *stack) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (stack.count == 0) {
        [defaults removeObjectForKey:kPendingNotificationsKey];
    } else {
        [defaults setObject:FirebasexMessagingPropertyListValue(stack) forKey:kPendingNotificationsKey];
    }
}

/** Writes the queued messages to NSUserDefaults so they survive a termination while in the background. */
- (void)persistPendingNotifications {
    FirebasexMessagingWritePendingQueue([self.notificationStack copy] ?: @[]);
}

/**
 * Queues a message without a plugin instance.
 *
 * cordova-ios 8 creates the plugins from CDVViewController's viewDidLoad, which runs once a
 * scene connects, and iOS connects no scene when it launches a terminated app in the background
 * for a content-available push. The app delegate category then has no plugin to hand the
 * payload to, so it goes straight into the persisted queue that pluginInitialize restores at
 * the next (foreground) launch.
 */
+ (void)queueNotificationForNextLaunch:(NSDictionary *)userInfo {
    [self rememberDelivered:userInfo];
    NSMutableArray *stack = [[[NSUserDefaults standardUserDefaults] arrayForKey:kPendingNotificationsKey] mutableCopy] ?: [NSMutableArray array];
    [stack addObject:userInfo];
    while (stack.count > kNotificationStackSize) {
        [stack removeObjectAtIndex:0]; // drop the oldest, not the one just queued
    }
    FirebasexMessagingWritePendingQueue(stack);
    NSLog(@"%@ queueNotificationForNextLaunch: no plugin instance (app launched in the background, no scene), %lu message(s) persisted for the next launch", LOG_TAG, (unsigned long)stack.count);
}

#pragma mark - Notification Center catch-up

/**
 * Delivers to JS every remote push that is still in Notification Center and has not been handed
 * to JS yet. iOS wakes a suspended app for a content-available push only on a budget (and never
 * after a force quit, with Background App Refresh off or in Low Power Mode), so a push that showed
 * a banner may never have reached application:didReceiveRemoteNotification:. Its full payload is
 * still available from the delivered notifications, so it is picked up here when the app becomes
 * active or when onMessageReceived is registered, without the user tapping the banner.
 * Pushes without an alert never enter Notification Center and cannot be recovered this way.
 */
- (void)deliverNotificationsFromNotificationCenter {
    if (!self.isFCMEnabled || self.notificationCallbackId == nil) {
        return;
    }
    [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                NSUInteger delivered = 0;
                for (UNNotification *notification in notifications) {
                    if (![notification.request.trigger isKindOfClass:UNPushNotificationTrigger.class]) {
                        continue; // local notifications (ours or other plugins') are not pushes
                    }
                    NSDictionary *userInfo = notification.request.content.userInfo;
                    if (userInfo.count == 0 || [FirebasexMessagingPlugin wasDelivered:userInfo]) {
                        continue;
                    }
                    NSMutableDictionary *info = [userInfo mutableCopy];
                    NSDictionary *aps = [info objectForKey:@"aps"];
                    [info setValue:([aps objectForKey:@"alert"] != nil ? @"notification" : @"data") forKey:@"messageType"];
                    [info setValue:@"notification_center" forKey:@"delivery"];
                    [self sendNotification:info];
                    delivered++;
                }
                if (delivered > 0) {
                    [[FirebasexCorePlugin sharedInstance] _logMessage:[NSString stringWithFormat:@"deliverNotificationsFromNotificationCenter: %lu push(es) found in Notification Center that the app had not received", (unsigned long)delivered]];
                }
            } @catch (NSException *exception) {
                [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
            }
        });
    }];
}

/** Stable fingerprint of a payload, ignoring the keys this plugin adds on delivery. */
+ (NSString *)fingerprintForPayload:(NSDictionary *)userInfo {
    NSMutableDictionary *payload = [userInfo mutableCopy];
    for (NSString *key in @[@"messageType", @"tap", @"action", @"delivery"]) {
        [payload removeObjectForKey:key];
    }
    if ([NSJSONSerialization isValidJSONObject:payload]) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingSortedKeys error:nil];
        if (json) {
            return [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        }
    }
    return [payload description];
}

+ (BOOL)wasDelivered:(NSDictionary *)userInfo {
    NSArray *fingerprints = [[NSUserDefaults standardUserDefaults] arrayForKey:kDeliveredFingerprintsKey];
    return [fingerprints containsObject:[self fingerprintForPayload:userInfo]];
}

+ (void)rememberDelivered:(NSDictionary *)userInfo {
    NSString *fingerprint = [self fingerprintForPayload:userInfo];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *fingerprints = [[defaults arrayForKey:kDeliveredFingerprintsKey] mutableCopy] ?: [NSMutableArray array];
    [fingerprints removeObject:fingerprint];
    [fingerprints addObject:fingerprint];
    while (fingerprints.count > kDeliveredFingerprintsLimit) {
        [fingerprints removeObjectAtIndex:0];
    }
    [defaults setObject:fingerprints forKey:kDeliveredFingerprintsKey];
}

#pragma mark - Message Delivery Internal

/**
 * Delivers all queued notifications from the notification stack to the
 * JavaScript callback, then removes only the notifications being delivered
 * from the stack so notifications re-queued during delivery are preserved.
 */
- (void)sendPendingNotifications {
    if (self.notificationCallbackId == nil || self.notificationStack == nil || ![self.notificationStack count]) {
        return;
    }

    if ([[CDVAppDelegate instance].applicationInBackground isEqual:@(YES)] && !immediateMessagePayloadDelivery) {
        [[FirebasexCorePlugin sharedInstance] _logMessage:[NSString stringWithFormat:@"sendPendingNotifications: app in background, keeping %lu message(s) queued", (unsigned long)[self.notificationStack count]]];
        return;
    }

    @try {
        NSArray *pendingNotifications = [self.notificationStack copy];
        [self.notificationStack removeAllObjects];
        [self persistPendingNotifications];
        [[FirebasexCorePlugin sharedInstance] _logMessage:[NSString stringWithFormat:@"sendPendingNotifications: delivering %lu queued message(s)", (unsigned long)pendingNotifications.count]];

        for (NSDictionary *userInfo in pendingNotifications) {
            [self sendNotification:userInfo];
        }
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
    }
}

/**
 * Delivers a notification to the JavaScript callback.
 *
 * First offers the notification to any registered custom message receivers.
 * If no receiver handles it and the JS callback is registered, sends the
 * notification immediately (unless the app is backgrounded without
 * immediate delivery enabled). Otherwise queues it on the notification stack.
 * The stack is capped at {@code kNotificationStackSize} entries.
 *
 * @param userInfo The notification payload dictionary.
 */
- (void)sendNotification:(NSDictionary *)userInfo {
    @try {
        if ([FirebasePluginMessageReceiverManager sendNotification:userInfo]) {
            [[FirebasexCorePlugin sharedInstance] _logMessage:@"Message handled by custom receiver"];
            return;
        }
        [FirebasexMessagingPlugin rememberDelivered:userInfo];
        // A nil applicationInBackground (lifecycle tracking not started) counts as foreground:
        // delivering is better than queueing forever.
        BOOL inBackground = [[CDVAppDelegate instance].applicationInBackground isEqual:@(YES)];
        NSString *callbackId = self.notificationCallbackId;
        if (callbackId != nil && (!inBackground || immediateMessagePayloadDelivery)) {
            [[FirebasexCorePlugin sharedInstance] _logMessage:[NSString stringWithFormat:@"sendNotification: delivering to JS callback %@ (inBackground=%d)", callbackId, inBackground]];
            [[FirebasexCorePlugin sharedInstance] sendPluginDictionaryResultAndKeepCallback:userInfo
                                                                                   command:self.commandDelegate
                                                                                callbackId:callbackId];
        } else {
            if (!self.notificationStack) {
                self.notificationStack = [[NSMutableArray alloc] init];
            }
            [self.notificationStack addObject:userInfo];

            while ([self.notificationStack count] > kNotificationStackSize) {
                [self.notificationStack removeObjectAtIndex:0]; // drop the oldest, not the one just queued
            }
            [self persistPendingNotifications];
            [[FirebasexCorePlugin sharedInstance] _logMessage:[NSString stringWithFormat:@"sendNotification: queued (callback registered=%d, inBackground=%d, immediateDelivery=%d), %lu pending", callbackId != nil, inBackground, immediateMessagePayloadDelivery, (unsigned long)[self.notificationStack count]]];
        }
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
    }
}

/**
 * Delivers an FCM token to the JavaScript token-refresh callback.
 * @param token The FCM registration token string.
 */
- (void)sendToken:(NSString *)token {
    @try {
        if (self.tokenRefreshCallbackId != nil) {
            [[FirebasexCorePlugin sharedInstance] sendPluginStringResultAndKeepCallback:token
                                                                               command:self.commandDelegate
                                                                            callbackId:self.tokenRefreshCallbackId];
        }
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
    }
}

/**
 * Delivers an APNs token to the JavaScript APNs-token callback.
 * @param token The APNs device token as a hex string.
 */
- (void)sendApnsToken:(NSString *)token {
    @try {
        if (self.apnsTokenRefreshCallbackId != nil) {
            [[FirebasexCorePlugin sharedInstance] sendPluginStringResultAndKeepCallback:token
                                                                               command:self.commandDelegate
                                                                            callbackId:self.apnsTokenRefreshCallbackId];
        }
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
    }
}

/**
 * Notifies JavaScript that the user opened notification settings.
 * If no JS callback is registered yet, flags the event for deferred delivery.
 */
- (void)sendOpenNotificationSettings {
    @try {
        if (self.openSettingsCallbackId != nil) {
            [[FirebasexCorePlugin sharedInstance] sendPluginSuccessAndKeepCallback:self.openSettingsCallbackId
                                                                          command:self.commandDelegate];
        } else if (openSettingsEmitted != YES) {
            openSettingsEmitted = YES;
        }
    } @catch (NSException *exception) {
        [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
    }
}

@end
