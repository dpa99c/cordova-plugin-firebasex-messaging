/**
 * @file FirebasePluginMessageReceiver.m
 * @brief Implementation of the base message receiver class for iOS.
 *
 * Auto-registers with @c FirebasePluginMessageReceiverManager on @c init.
 * Subclasses override @c sendNotification: to handle incoming notifications.
 */

#import "FirebasePluginMessageReceiver.h"
#import "FirebasePluginMessageReceiverManager.h"

@implementation FirebasePluginMessageReceiver

/**
 * Initialises the receiver and auto-registers it with the
 * @c FirebasePluginMessageReceiverManager.
 */
- (instancetype)init {
    self = [super init];
    if (self) {
        [FirebasePluginMessageReceiverManager registerMessageReceiver:self];
    }
    return self;
}

/**
 * No-op default implementation. Override in subclass to handle notifications.
 *
 * @param notification The notification payload dictionary.
 */
- (void)sendNotification:(NSDictionary *)notification {
    // Override in subclass
}

@end
