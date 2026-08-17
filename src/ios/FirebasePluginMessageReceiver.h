/**
 * @file FirebasePluginMessageReceiver.h
 * @brief Base class for intercepting Firebase Cloud Messaging notifications on iOS.
 *
 * Subclass this to implement custom notification handling logic.
 * Instances auto-register with @c FirebasePluginMessageReceiverManager on @c init.
 * Override @c sendNotification: to process incoming notification dictionaries.
 */

#import <Foundation/Foundation.h>

/**
 * Base class for custom FCM message receivers.
 *
 * Subclasses override @c sendNotification: to inspect or transform incoming
 * notification payloads before (or instead of) the default handling.
 * Registration with @c FirebasePluginMessageReceiverManager is automatic.
 */
@interface FirebasePluginMessageReceiver : NSObject

/**
 * Called by the manager when a notification is received.
 *
 * The default implementation is a no-op. Override in a subclass to handle
 * notifications.
 *
 * @param notification The notification payload dictionary.
 */
- (void)sendNotification:(NSDictionary *)notification;

@end
