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
@import cordova_plugin_firebasex_core;
@import FirebaseMessaging;
@import UserNotifications;

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

/** Called when the app becomes active; flushes any queued notifications. */
- (void)onAppDidBecomeActive {
    [self sendPendingNotifications];
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
    [self sendPendingNotifications];
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

#pragma mark - Message Delivery Internal

/**
 * Delivers all queued notifications from the notification stack to the
 * JavaScript callback, then clears the stack.
 */
- (void)sendPendingNotifications {
    if (self.notificationCallbackId != nil && self.notificationStack != nil && [self.notificationStack count]) {
        @try {
            for (NSDictionary *userInfo in self.notificationStack) {
                [self sendNotification:userInfo];
            }
            [self.notificationStack removeAllObjects];
        } @catch (NSException *exception) {
            [[FirebasexCorePlugin sharedInstance] handlePluginExceptionWithoutContext:exception];
        }
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
        if (self.notificationCallbackId != nil &&
            ([[CDVAppDelegate instance].applicationInBackground isEqual:@(NO)] || immediateMessagePayloadDelivery)) {
            [[FirebasexCorePlugin sharedInstance] sendPluginDictionaryResultAndKeepCallback:userInfo
                                                                                   command:self.commandDelegate
                                                                                callbackId:self.notificationCallbackId];
        } else {
            if (!self.notificationStack) {
                self.notificationStack = [[NSMutableArray alloc] init];
            }
            [self.notificationStack addObject:userInfo];

            if ([self.notificationStack count] >= kNotificationStackSize) {
                [self.notificationStack removeLastObject];
            }
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
