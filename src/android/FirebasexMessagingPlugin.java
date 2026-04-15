package org.apache.cordova.firebasex;

import android.app.Activity;
import android.app.NotificationManager;
import android.app.NotificationChannel;
import android.content.BroadcastReceiver;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;

import androidx.core.app.NotificationCompat;
import androidx.localbroadcastmanager.content.LocalBroadcastManager;

import com.google.firebase.messaging.FirebaseMessaging;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/**
 * FirebasexMessagingPlugin
 *
 * Cordova plugin for Firebase Cloud Messaging.
 * Handles FCM token management, notification permissions, subscriptions,
 * notification channels, and message delivery.
 */
public class FirebasexMessagingPlugin extends CordovaPlugin {

    /** Singleton instance of this plugin. */
    protected static FirebasexMessagingPlugin instance = null;
    /** Log tag for this plugin. */
    protected static final String TAG = "FirebasexMessaging";
    /** JavaScript global namespace prefix used for native-to-JS callbacks. */
    protected static final String JS_GLOBAL_NAMESPACE = "FirebasexMessaging.";

    /** Android permission name for POST_NOTIFICATIONS (Android 13+). */
    protected static final String POST_NOTIFICATIONS = "POST_NOTIFICATIONS";
    /** Request code used for the POST_NOTIFICATIONS runtime permission dialog. */
    protected static final int POST_NOTIFICATIONS_PERMISSION_REQUEST_ID = 1;

    /** Whether incoming message payloads should be delivered immediately even when in background. */
    private static boolean immediateMessagePayloadDelivery = false;
    /** Queue of notification bundles received while the JS callback was not yet registered. */
    private static ArrayList<Bundle> notificationStack = null;
    /** Persistent callback context for delivering incoming messages to JavaScript. */
    private static CallbackContext notificationCallbackContext;
    /** Persistent callback context for delivering FCM token refreshes to JavaScript. */
    private static CallbackContext tokenRefreshCallbackContext;
    /** Callback context for the pending POST_NOTIFICATIONS permission request. */
    private static CallbackContext postNotificationPermissionRequestCallbackContext;

    /** The default Android notification channel used for FCM notifications. */
    private static NotificationChannel defaultNotificationChannel = null;
    /** Channel ID of the default notification channel. */
    public static String defaultChannelId = null;
    /** Display name of the default notification channel. */
    public static String defaultChannelName = null;

    /** Receiver for app lifecycle events (e.g. app becoming active) from FirebasexCore. */
    private BroadcastReceiver lifecycleReceiver;

    /**
     * Returns the singleton instance.
     */
    public static FirebasexMessagingPlugin getInstance() {
        return instance;
    }

    /**
     * Initializes the plugin: registers the singleton instance, checks launch
     * extras for notifications that opened the app, creates the default notification
     * channel, and registers a lifecycle receiver to flush pending notifications
     * when the app becomes active.
     */
    @Override
    protected void pluginInitialize() {
        instance = this;
        try {
            Log.d(TAG, "Starting Firebase Messaging plugin");

            Context applicationContext = cordova.getActivity().getApplicationContext();
            Activity cordovaActivity = cordova.getActivity();

            immediateMessagePayloadDelivery = "true".equals(FirebasexCorePlugin.getInstance()
                    .getPluginVariableFromConfigXml("FIREBASE_MESSAGING_IMMEDIATE_PAYLOAD_DELIVERY"));

            // Check for notification from app launch.
            // Detect both system-handled notifications (google.message_id in extras)
            // and notifications routed through OnNotificationReceiverActivity (messageType in extras).
            Bundle extras = cordovaActivity.getIntent().getExtras();
            if (extras != null && extras.size() > 1) {
                if (notificationStack == null) {
                    notificationStack = new ArrayList<Bundle>();
                }
                if (extras.containsKey("google.message_id")) {
                    extras.putString("messageType", "notification");
                    extras.putString("tap", "background");
                    notificationStack.add(extras);
                    Log.d(TAG, "Notification message found on init (google.message_id): " + extras.toString());
                } else if (extras.containsKey("messageType") && extras.containsKey("tap")) {
                    // Already processed by OnNotificationReceiverActivity — avoid duplicate
                    // Only add if not already in the stack (sendMessage may have queued it)
                    boolean alreadyQueued = false;
                    if (notificationStack != null) {
                        for (Bundle b : notificationStack) {
                            if (b == extras || (extras.getString("id") != null && extras.getString("id").equals(b.getString("id")))) {
                                alreadyQueued = true;
                                break;
                            }
                        }
                    }
                    if (!alreadyQueued) {
                        notificationStack.add(extras);
                        Log.d(TAG, "Notification message found on init (messageType+tap): " + extras.toString());
                    }
                }
            }

            // Initialize default notification channel
            defaultChannelId = FirebasexCorePlugin.getInstance().getStringResource("default_notification_channel_id");
            defaultChannelName = FirebasexCorePlugin.getInstance().getStringResource("default_notification_channel_name");
            createDefaultChannel();

            // Register for lifecycle events from core
            lifecycleReceiver = new BroadcastReceiver() {
                @Override
                public void onReceive(Context context, Intent intent) {
                    String action = intent.getAction();
                    if ("FirebasexAppDidBecomeActive".equals(action)) {
                        sendPendingNotifications();
                    }
                }
            };
            FirebasexEventBus.register(applicationContext, "FirebasexAppDidBecomeActive", lifecycleReceiver);

        } catch (Exception e) {
            FirebasexCorePlugin.getInstance().handleExceptionWithoutContext(e);
        }
    }

    /**
     * Routes Cordova action calls to the appropriate handler method.
     * Handles 20+ actions; iOS-only actions (setBadgeNumber, getBadgeNumber,
     * hasCriticalPermission, grantCriticalPermission, getAPNSToken,
     * onApnsTokenReceived, onOpenSettings) are implemented as no-ops on Android.
     */
    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        try {
            switch (action) {
                case "getToken":
                    getToken(callbackContext);
                    return true;
                case "onMessageReceived":
                    onMessageReceived(callbackContext);
                    return true;
                case "onTokenRefresh":
                    onTokenRefresh(callbackContext);
                    return true;
                case "subscribe":
                    subscribe(callbackContext, args.getString(0));
                    return true;
                case "unsubscribe":
                    unsubscribe(callbackContext, args.getString(0));
                    return true;
                case "unregister":
                    unregister(callbackContext);
                    return true;
                case "hasPermission":
                    hasPermission(callbackContext);
                    return true;
                case "grantPermission":
                    grantPermission(callbackContext);
                    return true;
                case "isAutoInitEnabled":
                    isAutoInitEnabled(callbackContext);
                    return true;
                case "setAutoInitEnabled":
                    setAutoInitEnabled(callbackContext, args.getBoolean(0));
                    return true;
                case "createChannel":
                    createChannel(callbackContext, args.getJSONObject(0));
                    return true;
                case "setDefaultChannel":
                    setDefaultChannel(callbackContext, args.getJSONObject(0));
                    return true;
                case "deleteChannel":
                    deleteChannel(callbackContext, args.getString(0));
                    return true;
                case "listChannels":
                    listChannels(callbackContext);
                    return true;
                case "clearAllNotifications":
                    clearAllNotifications(callbackContext);
                    return true;
                case "setBadgeNumber":
                    // No-op on Android
                    callbackContext.success();
                    return true;
                case "getBadgeNumber":
                    // No-op on Android
                    callbackContext.success(0);
                    return true;
                case "hasCriticalPermission":
                    // No-op on Android
                    callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.OK, false));
                    return true;
                case "grantCriticalPermission":
                    // No-op on Android
                    callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.OK, false));
                    return true;
                case "getAPNSToken":
                    // No-op on Android
                    callbackContext.success("");
                    return true;
                case "onApnsTokenReceived":
                    // No-op on Android
                    callbackContext.success();
                    return true;
                case "onOpenSettings":
                    // No-op on Android
                    callbackContext.success();
                    return true;
                default:
                    return false;
            }
        } catch (Exception e) {
            FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
            return false;
        }
    }

    /**
     * Handles new intents delivered when the activity is already running.
     * Checks for notification data in the intent extras and delivers it.
     */
    @Override
    public void onNewIntent(Intent intent) {
        try {
            super.onNewIntent(intent);
            final Bundle data = intent.getExtras();
            if (data != null && data.containsKey("google.message_id")) {
                data.putString("messageType", "notification");
                data.putString("tap", "background");
                Log.d(TAG, "Notification message on new intent: " + data.toString());
                sendMessage(data, FirebasexCorePlugin.getApplicationContext());
            }
        } catch (Exception e) {
            FirebasexCorePlugin.handleExceptionWithoutContext(e);
        }
    }

    /** Unregisters the lifecycle receiver on plugin destruction. */
    @Override
    public void onDestroy() {
        if (lifecycleReceiver != null) {
            FirebasexEventBus.unregister(cordova.getActivity().getApplicationContext(), lifecycleReceiver);
        }
        super.onDestroy();
    }

    // ---- Token Management ----

    /**
     * Retrieves the current FCM registration token asynchronously.
     * @param callbackContext Receives the token string on success.
     */
    private void getToken(final CallbackContext callbackContext) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    FirebaseMessaging.getInstance().getToken()
                            .addOnCompleteListener(new com.google.android.gms.tasks.OnCompleteListener<String>() {
                                @Override
                                public void onComplete(com.google.android.gms.tasks.Task<String> task) {
                                    try {
                                        if (task.isSuccessful()) {
                                            callbackContext.success(task.getResult());
                                        } else {
                                            callbackContext.error(task.getException().getMessage());
                                        }
                                    } catch (Exception e) {
                                        FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                                    }
                                }
                            });
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    /**
     * Registers a persistent callback for FCM token refresh events.
     * Immediately attempts to fetch and return the current token.
     * @param callbackContext Kept alive and called each time the token changes.
     */
    private void onTokenRefresh(final CallbackContext callbackContext) {
        tokenRefreshCallbackContext = callbackContext;

        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    FirebaseMessaging.getInstance().getToken().addOnCompleteListener(new com.google.android.gms.tasks.OnCompleteListener<String>() {
                        @Override
                        public void onComplete(com.google.android.gms.tasks.Task<String> task) {
                            try {
                                if (task.isSuccessful() || task.getException() == null) {
                                    String currentToken = task.getResult();
                                    if (currentToken != null) {
                                        sendToken(currentToken);
                                    }
                                } else if (task.getException() != null) {
                                    callbackContext.error(task.getException().getMessage());
                                } else {
                                    callbackContext.error("Task failed for unknown reason");
                                }
                            } catch (Exception e) {
                                FirebasexCorePlugin.handleExceptionWithContext(e, callbackContext);
                            }
                        }
                    });
                } catch (Exception e) {
                    FirebasexCorePlugin.handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    /**
     * Registers a persistent callback for incoming push messages.
     * Immediately flushes any notifications queued before the callback was set.
     * @param callbackContext Kept alive and called for each incoming message.
     */
    private void onMessageReceived(final CallbackContext callbackContext) {
        notificationCallbackContext = callbackContext;
        sendPendingNotifications();
    }

    // ---- Subscriptions ----

    /**
     * Subscribes to an FCM topic.
     * @param callbackContext Called on completion.
     * @param topic           The topic name.
     */
    private void subscribe(final CallbackContext callbackContext, final String topic) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    FirebaseMessaging.getInstance().subscribeToTopic(topic);
                    callbackContext.success();
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    /**
     * Unsubscribes from an FCM topic.
     * @param callbackContext Called on completion.
     * @param topic           The topic name.
     */
    private void unsubscribe(final CallbackContext callbackContext, final String topic) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    FirebaseMessaging.getInstance().unsubscribeFromTopic(topic);
                    callbackContext.success();
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    /**
     * Deletes the current FCM token and optionally re-registers if auto-init is enabled.
     * @param callbackContext Called on completion.
     */
    private void unregister(final CallbackContext callbackContext) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    FirebaseMessaging.getInstance().deleteToken();
                    boolean isAutoInitEnabled = FirebaseMessaging.getInstance().isAutoInitEnabled();
                    if (isAutoInitEnabled) {
                        FirebaseMessaging.getInstance().getToken();
                    }
                    callbackContext.success();
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    // ---- Permissions ----

    /**
     * Checks whether the app has notification permission.
     * On Android 13+ checks POST_NOTIFICATIONS; on earlier versions checks
     * whether notifications are enabled via NotificationManagerCompat.
     * @param callbackContext Called with a boolean result.
     */
    private void hasPermission(final CallbackContext callbackContext) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    boolean hasPermission;
                    Context ctx = cordova.getActivity().getApplicationContext();
                    if (Build.VERSION.SDK_INT >= 33) {
                        hasPermission = ctx.checkSelfPermission("android.permission.POST_NOTIFICATIONS")
                                == android.content.pm.PackageManager.PERMISSION_GRANTED;
                    } else {
                        hasPermission = androidx.core.app.NotificationManagerCompat.from(ctx).areNotificationsEnabled();
                    }
                    callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.OK, hasPermission));
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    /**
     * Requests the POST_NOTIFICATIONS runtime permission (Android 13+).
     * On earlier versions, returns true immediately.
     * @param callbackContext Called with a boolean indicating whether permission was granted.
     */
    private void grantPermission(final CallbackContext callbackContext) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    if (Build.VERSION.SDK_INT >= 33) {
                        postNotificationPermissionRequestCallbackContext = callbackContext;
                        cordova.requestPermission(FirebasexMessagingPlugin.this, POST_NOTIFICATIONS_PERMISSION_REQUEST_ID,
                                "android.permission.POST_NOTIFICATIONS");
                    } else {
                        callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.OK, true));
                    }
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    /**
     * Callback for the system permission dialog result.
     * Delivers the grant/deny result to the stored callback context.
     */
    @Override
    public void onRequestPermissionResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode == POST_NOTIFICATIONS_PERMISSION_REQUEST_ID && postNotificationPermissionRequestCallbackContext != null) {
            boolean granted = grantResults.length > 0 && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED;
            postNotificationPermissionRequestCallbackContext.sendPluginResult(
                    new PluginResult(PluginResult.Status.OK, granted));
            postNotificationPermissionRequestCallbackContext = null;
        }
    }

    // ---- Auto-init ----

    /**
     * Checks whether FCM auto-init is enabled.
     * @param callbackContext Called with a boolean result.
     */
    private void isAutoInitEnabled(final CallbackContext callbackContext) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    boolean enabled = FirebaseMessaging.getInstance().isAutoInitEnabled();
                    callbackContext.sendPluginResult(new PluginResult(PluginResult.Status.OK, enabled));
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    /**
     * Enables or disables FCM auto-initialization.
     * @param callbackContext Called on completion.
     * @param enabled         {@code true} to enable, {@code false} to disable.
     */
    private void setAutoInitEnabled(final CallbackContext callbackContext, final boolean enabled) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    FirebaseMessaging.getInstance().setAutoInitEnabled(enabled);
                    callbackContext.success();
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    // ---- Notification Channels ----

    /**
     * Creates a notification channel (Cordova action handler).
     * @param callbackContext Called on completion.
     * @param options         JSON object with channel configuration.
     */
    public void createChannel(final CallbackContext callbackContext, final JSONObject options) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    createChannel(options);
                    callbackContext.success();
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    /**
     * Creates or recreates a notification channel (Android O+).
     * If a channel with the same ID already exists, it is deleted first.
     * Handles all channel properties: name, importance, description, light,
     * lightColor, visibility, badge, usage, streamType, sound ("default",
     * "ringtone", custom resource, or "false" for silent), and vibration
     * (boolean or long[] pattern).
     *
     * @param options JSON object with channel configuration properties.
     * @return The created {@link NotificationChannel}, or null if below API 26.
     * @throws JSONException if required properties are missing.
     */
    protected static NotificationChannel createChannel(final JSONObject options) throws JSONException {
        NotificationChannel channel = null;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            String id = options.getString("id");
            Log.i(TAG, "Creating channel id=" + id);

            if (channelExists(id)) {
                deleteChannel(id);
            }

            Context applicationContext = FirebasexCorePlugin.getInstance().getApplicationContext();
            NotificationManager nm = (NotificationManager) applicationContext.getSystemService(Context.NOTIFICATION_SERVICE);
            String packageName = FirebasexCorePlugin.getInstance().getCordovaActivity().getPackageName();

            String name = options.optString("name", "");
            Log.d(TAG, "Channel " + id + " - name=" + name);

            int importance = options.optInt("importance", NotificationManager.IMPORTANCE_HIGH);
            Log.d(TAG, "Channel " + id + " - importance=" + importance);

            channel = new NotificationChannel(id, name, importance);

            String description = options.optString("description", "");
            Log.d(TAG, "Channel " + id + " - description=" + description);
            channel.setDescription(description);

            boolean light = options.optBoolean("light", true);
            Log.d(TAG, "Channel " + id + " - light=" + light);
            channel.enableLights(light);

            int lightColor = options.optInt("lightColor", -1);
            if (lightColor != -1) {
                Log.d(TAG, "Channel " + id + " - lightColor=" + lightColor);
                channel.setLightColor(lightColor);
            }

            int visibility = options.optInt("visibility", NotificationCompat.VISIBILITY_PUBLIC);
            Log.d(TAG, "Channel " + id + " - visibility=" + visibility);
            channel.setLockscreenVisibility(visibility);

            boolean badge = options.optBoolean("badge", true);
            Log.d(TAG, "Channel " + id + " - badge=" + badge);
            channel.setShowBadge(badge);

            int usage = options.optInt("usage", AudioAttributes.USAGE_NOTIFICATION_RINGTONE);
            Log.d(TAG, "Channel " + id + " - usage=" + usage);

            int streamType = options.optInt("streamType", -1);
            Log.d(TAG, "Channel " + id + " - streamType=" + streamType);

            String sound = options.optString("sound", "default");
            AudioAttributes.Builder audioAttributesBuilder = new AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(usage);

            if (streamType != -1) {
                audioAttributesBuilder.setLegacyStreamType(streamType);
            }

            AudioAttributes audioAttributes = audioAttributesBuilder.build();
            if ("ringtone".equals(sound)) {
                channel.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE), audioAttributes);
                Log.d(TAG, "Channel " + id + " - sound=ringtone");
            } else if (!sound.contentEquals("false")) {
                if (!sound.contentEquals("default")) {
                    Uri soundUri = Uri.parse(ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + packageName + "/raw/" + sound);
                    channel.setSound(soundUri, audioAttributes);
                    Log.d(TAG, "Channel " + id + " - sound=" + sound);
                } else {
                    channel.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION), audioAttributes);
                    Log.d(TAG, "Channel " + id + " - sound=default");
                }
            } else {
                channel.setSound(null, null);
                Log.d(TAG, "Channel " + id + " - sound=none");
            }

            JSONArray pattern = options.optJSONArray("vibration");
            if (pattern != null) {
                int patternLength = pattern.length();
                long[] patternArray = new long[patternLength];
                for (int i = 0; i < patternLength; i++) {
                    patternArray[i] = pattern.optLong(i);
                }
                channel.enableVibration(true);
                channel.setVibrationPattern(patternArray);
                Log.d(TAG, "Channel " + id + " - vibrate=" + pattern);
            } else {
                boolean vibrate = options.optBoolean("vibration", true);
                channel.enableVibration(vibrate);
                Log.d(TAG, "Channel " + id + " - vibrate=" + vibrate);
            }

            nm.createNotificationChannel(channel);
        }
        return channel;
    }

    /**
     * Creates the default notification channel using the configured default ID and name.
     * @throws JSONException if channel creation fails.
     */
    protected static void createDefaultChannel() throws JSONException {
        JSONObject options = new JSONObject();
        options.put("id", defaultChannelId);
        options.put("name", defaultChannelName);
        createDefaultChannel(options);
    }

    /**
     * Creates the default notification channel with custom options.
     * @param options JSON object with channel configuration.
     * @throws JSONException if channel creation fails.
     */
    protected static void createDefaultChannel(final JSONObject options) throws JSONException {
        defaultNotificationChannel = createChannel(options);
    }

    /**
     * Sets the default notification channel, replacing any existing default.
     * @param callbackContext Called on completion.
     * @param options         JSON object with new channel configuration.
     */
    public void setDefaultChannel(final CallbackContext callbackContext, final JSONObject options) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    deleteChannel(defaultChannelId);

                    String id = options.optString("id", null);
                    if (id != null) {
                        defaultChannelId = id;
                    }

                    String name = options.optString("name", null);
                    if (name != null) {
                        defaultChannelName = name;
                    }
                    createDefaultChannel(options);
                    callbackContext.success();
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    /**
     * Deletes a notification channel (Cordova action handler).
     * @param callbackContext Called on completion.
     * @param channelID       The channel ID to delete.
     */
    public void deleteChannel(final CallbackContext callbackContext, final String channelID) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    deleteChannel(channelID);
                    callbackContext.success();
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    /**
     * Deletes a notification channel by its ID (Android O+).
     * @param channelID The channel ID to delete.
     */
    protected static void deleteChannel(final String channelID) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Context applicationContext = FirebasexCorePlugin.getInstance().getApplicationContext();
            NotificationManager nm = (NotificationManager) applicationContext.getSystemService(Context.NOTIFICATION_SERVICE);
            nm.deleteNotificationChannel(channelID);
        }
    }

    /**
     * Lists all notification channels (Cordova action handler).
     * Returns a JSON array of objects with "id" and "name" properties.
     * @param callbackContext Called with the channels array.
     */
    public void listChannels(final CallbackContext callbackContext) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    List<NotificationChannel> notificationChannels = listChannels();
                    JSONArray channels = new JSONArray();
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        for (NotificationChannel notificationChannel : notificationChannels) {
                            JSONObject channel = new JSONObject();
                            channel.put("id", notificationChannel.getId());
                            channel.put("name", notificationChannel.getName());
                            channels.put(channel);
                        }
                    }
                    callbackContext.success(channels);
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    /**
     * Returns all registered notification channels (Android O+).
     * @return List of notification channels, or null if below API 26.
     */
    public static List<NotificationChannel> listChannels() {
        List<NotificationChannel> notificationChannels = null;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Context applicationContext = FirebasexCorePlugin.getInstance().getApplicationContext();
            NotificationManager nm = (NotificationManager) applicationContext.getSystemService(Context.NOTIFICATION_SERVICE);
            notificationChannels = nm.getNotificationChannels();
        }
        return notificationChannels;
    }

    /**
     * Checks whether a notification channel with the given ID exists.
     * @param channelId The channel ID to check.
     * @return {@code true} if the channel exists.
     */
    public static boolean channelExists(String channelId) {
        boolean exists = false;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            List<NotificationChannel> notificationChannels = listChannels();
            if (notificationChannels != null) {
                for (NotificationChannel notificationChannel : notificationChannels) {
                    if (notificationChannel.getId().equals(channelId)) {
                        exists = true;
                    }
                }
            }
        }
        return exists;
    }

    // ---- Notifications ----

    /**
     * Cancels all displayed notifications from the notification shade.
     * @param callbackContext Called on completion.
     */
    public void clearAllNotifications(final CallbackContext callbackContext) {
        cordova.getThreadPool().execute(new Runnable() {
            public void run() {
                try {
                    Context applicationContext = FirebasexCorePlugin.getInstance().getApplicationContext();
                    NotificationManager nm = (NotificationManager) applicationContext.getSystemService(Context.NOTIFICATION_SERVICE);
                    nm.cancelAll();
                    callbackContext.success();
                } catch (Exception e) {
                    FirebasexCorePlugin.getInstance().handleExceptionWithContext(e, callbackContext);
                }
            }
        });
    }

    // ---- Static message delivery (called from FirebasexMessagingService) ----

    /**
     * Returns whether the application is currently in the background.
     * @return {@code true} if the app is backgrounded.
     */
    public static boolean inBackground() {
        return FirebasexCorePlugin.isApplicationInBackground();
    }

    /**
     * Returns whether a JS callback is registered for incoming notifications.
     * @return {@code true} if the notification callback context is set.
     */
    public static boolean hasNotificationsCallback() {
        return notificationCallbackContext != null;
    }

    /**
     * Returns whether immediate message payload delivery is enabled.
     * When enabled, messages are delivered to the JS layer even when the app is in the background.
     * @return {@code true} if immediate delivery is enabled.
     */
    public static boolean isImmediateMessagePayloadDelivery() {
        return immediateMessagePayloadDelivery;
    }

    /**
     * Called from the messaging service or notification receivers to deliver a message
     * to the JS callback.
     */
    public static void sendMessage(Bundle bundle, Context context) {
        if (!hasNotificationsCallback() || (inBackground() && !immediateMessagePayloadDelivery)) {
            if (notificationStack == null) {
                notificationStack = new ArrayList<Bundle>();
            }
            notificationStack.add(bundle);

            return;
        }

        final CallbackContext callbackContext = notificationCallbackContext;
        if (bundle != null) {
            // Pass the message bundle to the receiver manager so any registered receivers can decide to handle it
            boolean wasHandled = FirebasePluginMessageReceiverManager.sendMessage(bundle);
            if (wasHandled) {
                Log.d(TAG, "Message bundle was handled by a registered receiver");
            } else if (callbackContext != null) {
                JSONObject json = new JSONObject();
                java.util.Set<String> keys = bundle.keySet();
                for (String key : keys) {
                    try {
                        json.put(key, bundle.get(key));
                    } catch (JSONException e) {
                        FirebasexCorePlugin.handleExceptionWithContext(e, callbackContext);
                        return;
                    }
                }
                PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, json);
                pluginResult.setKeepCallback(true);
                callbackContext.sendPluginResult(pluginResult);
            }
        }
    }

    /**
     * Called from the messaging service when a new FCM token is received.
     */
    public static void sendToken(String token) {
        try {
            if (tokenRefreshCallbackContext != null) {
                PluginResult pluginResult = new PluginResult(PluginResult.Status.OK, token);
                pluginResult.setKeepCallback(true);
                tokenRefreshCallbackContext.sendPluginResult(pluginResult);
            }
        } catch (Exception e) {
            FirebasexCorePlugin.getInstance().handleExceptionWithoutContext(e);
        }
    }

    /**
     * Sends any queued notifications to the JS layer.
     * Takes a snapshot of the pending stack and clears it before iterating,
     * so that sendMessage() can safely re-queue items without causing
     * ConcurrentModificationException or data corruption from parallel tasks.
     */
    private synchronized void sendPendingNotifications() {
        if (notificationStack != null && !notificationStack.isEmpty()) {
            final ArrayList<Bundle> pending = new ArrayList<>(notificationStack);
            notificationStack.clear();
            this.cordova.getThreadPool().execute(new Runnable() {
                public void run() {
                    try {
                        for (Bundle bundle : pending) {
                            sendMessage(bundle, FirebasexCorePlugin.getApplicationContext());
                        }
                    } catch (Exception e) {
                        FirebasexCorePlugin.handleExceptionWithoutContext(e);
                    }
                }
            });
        }
    }
}
