package org.apache.cordova.firebasex;

import android.os.Bundle;

import com.google.firebase.messaging.RemoteMessage;

import java.util.ArrayList;
import java.util.List;

/**
 * Singleton manager that tracks all registered {@link FirebasePluginMessageReceiver} instances
 * and dispatches incoming FCM messages and notification bundles to them.
 *
 * <p>When a message or bundle arrives, each registered receiver is invoked in registration order.
 * If any receiver returns {@code true}, the manager reports the message as handled, but all
 * receivers are still invoked (i.e., handling does not short-circuit).
 *
 * @see FirebasePluginMessageReceiver
 */
public class FirebasePluginMessageReceiverManager {

    /** List of registered message receivers, in registration order. */
    private static List<FirebasePluginMessageReceiver> receivers = new ArrayList<FirebasePluginMessageReceiver>();

    /**
     * Registers a message receiver. Typically called automatically from
     * {@link FirebasePluginMessageReceiver#FirebasePluginMessageReceiver()}.
     *
     * @param receiver the receiver to register
     */
    public static void register(FirebasePluginMessageReceiver receiver) {
        receivers.add(receiver);
    }

    /**
     * Dispatches an incoming FCM message to all registered receivers.
     *
     * @param remoteMessage the incoming FCM {@link RemoteMessage}
     * @return {@code true} if at least one receiver handled the message
     */
    public static boolean onMessageReceived(RemoteMessage remoteMessage) {
        boolean handled = false;
        for (FirebasePluginMessageReceiver receiver : receivers) {
            boolean wasHandled = receiver.onMessageReceived(remoteMessage);
            if (wasHandled) {
                handled = true;
            }
        }
        return handled;
    }

    /**
     * Dispatches a notification bundle to all registered receivers.
     *
     * @param bundle the notification data bundle
     * @return {@code true} if at least one receiver handled the bundle
     */
    public static boolean sendMessage(Bundle bundle) {
        boolean handled = false;
        for (FirebasePluginMessageReceiver receiver : receivers) {
            boolean wasHandled = receiver.sendMessage(bundle);
            if (wasHandled) {
                handled = true;
            }
        }
        return handled;
    }
}
