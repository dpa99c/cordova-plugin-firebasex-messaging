package org.apache.cordova.firebasex;

import android.os.Bundle;

import com.google.firebase.messaging.RemoteMessage;

/**
 * Abstract base class for intercepting Firebase Cloud Messaging (FCM) messages.
 *
 * <p>Subclasses can register themselves to intercept and process incoming
 * FCM messages or notification bundles before they are handled by the
 * default messaging plugin logic. This enables custom receiver plugins
 * (e.g., {@code cordova-plugin-customfcmreceiver}) to implement
 * application-specific message handling.
 *
 * <p>Registration is automatic: the constructor calls
 * {@link FirebasePluginMessageReceiverManager#register(FirebasePluginMessageReceiver)}
 * so subclass instances are immediately available to receive messages.
 *
 * @see FirebasePluginMessageReceiverManager
 */
public abstract class FirebasePluginMessageReceiver {

    /**
     * Creates a new receiver and auto-registers it with the
     * {@link FirebasePluginMessageReceiverManager}.
     */
    public FirebasePluginMessageReceiver() {
        FirebasePluginMessageReceiverManager.register(this);
    }

    /**
     * Called when a new FCM {@link RemoteMessage} is received.
     *
     * @param remoteMessage the incoming FCM message
     * @return {@code true} if this receiver handled the message and default processing
     *         should continue checking other receivers; {@code false} otherwise
     */
    public abstract boolean onMessageReceived(RemoteMessage remoteMessage);

    /**
     * Called when a notification bundle is being dispatched (e.g., from a tap action).
     *
     * @param bundle the notification data bundle
     * @return {@code true} if this receiver handled the bundle and default processing
     *         should continue checking other receivers; {@code false} otherwise
     */
    public abstract boolean sendMessage(Bundle bundle);
}
