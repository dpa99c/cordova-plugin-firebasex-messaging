# cordova-plugin-firebasex-messaging [![Latest Stable Version](https://img.shields.io/npm/v/cordova-plugin-firebasex-messaging.svg)](https://www.npmjs.com/package/cordova-plugin-firebasex-messaging) [![Total Downloads](https://img.shields.io/npm/dt/cordova-plugin-firebasex-messaging.svg)](https://npm-stat.com/charts.html?package=cordova-plugin-firebasex-messaging)

Firebase Cloud Messaging (FCM) plugin for the modular FirebaseX Cordova plugin suite. Provides push notification support including token management, topic subscriptions, notification permissions, notification channels (Android), and data messages.

This is part of the [modular FirebaseX Cordova plugin suite](https://github.com/dpa99c/cordova-plugin-firebasex#modular-plugins).
Install only the modules you need for smaller app size and better build performance.

Supported platforms: Android and iOS

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Installation](#installation)
  - [Plugin variables](#plugin-variables)
- [Cloud messaging](#cloud-messaging)
  - [Background notifications](#background-notifications)
  - [Foreground notifications](#foreground-notifications)
  - [Android notifications](#android-notifications)
    - [Android background notifications](#android-background-notifications)
    - [Android foreground notifications](#android-foreground-notifications)
    - [Android Notification Channels](#android-notification-channels)
    - [Android Notification Icons](#android-notification-icons)
    - [Android Notification Color](#android-notification-color)
    - [Android Notification Sound](#android-notification-sound)
    - [Android cloud message types](#android-cloud-message-types)
  - [iOS notifications](#ios-notifications)
    - [iOS background notifications](#ios-background-notifications)
    - [iOS notification sound](#ios-notification-sound)
    - [iOS critical notifications](#ios-critical-notifications)
    - [iOS badge number](#ios-badge-number)
    - [iOS actionable notifications](#ios-actionable-notifications)
    - [iOS notification settings button](#ios-notification-settings-button)
  - [Data messages](#data-messages)
    - [Data message notifications](#data-message-notifications)
  - [Custom FCM message handling](#custom-fcm-message-handling)
- [API](#api)
  - [Notifications and data messages](#notifications-and-data-messages)
    - [getToken](#gettoken)
    - [getId](#getid)
    - [onTokenRefresh](#ontokenrefresh)
    - [getAPNSToken](#getapnstoken)
    - [onApnsTokenReceived](#onapnstokenreceived)
    - [onOpenSettings](#onopensettings)
    - [onMessageReceived](#onmessagereceived)
    - [grantPermission](#grantpermission)
    - [grantCriticalPermission](#grantcriticalpermission)
    - [hasPermission](#haspermission)
    - [hasCriticalPermission](#hascriticalpermission)
    - [unregister](#unregister)
    - [isAutoInitEnabled](#isautoinitenabled)
    - [setAutoInitEnabled](#setautoinitenabled)
    - [setBadgeNumber](#setbadgenumber)
    - [getBadgeNumber](#getbadgenumber)
    - [clearAllNotifications](#clearallnotifications)
    - [subscribe](#subscribe)
    - [unsubscribe](#unsubscribe)
    - [createChannel](#createchannel)
    - [setDefaultChannel](#setdefaultchannel)
    - [Default Android Channel Properties](#default-android-channel-properties)
    - [deleteChannel](#deletechannel)
    - [listChannels](#listchannels)
- [Reporting issues](#reporting-issues)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Installation

    cordova plugin add cordova-plugin-firebasex-messaging

**Dependency:** Requires `cordova-plugin-firebasex-core` to be installed.

## Plugin variables

The following plugin variables can be set at installation time using the `--variable` flag:

| Variable | Default | Description |
|---|---|---|
| `FIREBASE_FCM_AUTOINIT_ENABLED` | `true` | Whether to auto-initialize FCM on app startup. Set to `false` to enable user opt-in for push notifications. |
| `FIREBASE_MESSAGING_IMMEDIATE_PAYLOAD_DELIVERY` | `false` | Whether to attempt immediate delivery of message payloads when the app is in background/inactive. See [Android background notifications](#android-background-notifications) and [iOS background notifications](#ios-background-notifications). |
| `IOS_FCM_ENABLED` | `true` | Whether to enable FCM on iOS. |
| `IOS_ENABLE_CRITICAL_ALERTS_ENABLED` | `false` | Whether to enable critical alert notification capability on iOS. See [iOS critical notifications](#ios-critical-notifications). |
| `IOS_FIREBASE_SDK_VERSION` | `12.9.0` | Version of the Firebase iOS SDK to use. |

For example, to disable FCM auto-initialization and enable critical alerts:

    cordova plugin add cordova-plugin-firebasex-messaging --variable FIREBASE_FCM_AUTOINIT_ENABLED=false --variable IOS_ENABLE_CRITICAL_ALERTS_ENABLED=true

# Cloud messaging

<p align="center">
  <a href="https://youtu.be/qLPhan9YUhQ"><img src="https://media.giphy.com/media/U70vu02o9yCFEffidf/200w_d.gif" /></a>
  <span>&nbsp;</span>
  <a href="https://youtu.be/35feCmGYSR4"><img src="https://media.giphy.com/media/Y4oFG0Awhd3TpnggHz/200w_d.gif" /></a>
</p>

There are 2 distinct types of messages that can be sent by Firebase Cloud Messaging (FCM):

-   [Notification messages](https://firebase.google.com/docs/cloud-messaging/concept-options#notifications)
    -   automatically displayed to the user by the operating system on behalf of the client app **while your app is not running or is in the background**
        -   **if your app is in the foreground when the notification message arrives**, it is passed to the client app and it is the responsibility of the client app to display it.
    -   have a predefined set of user-visible keys and an optional data payload of custom key-value pairs.
-   [Data messages](https://firebase.google.com/docs/cloud-messaging/concept-options#data_messages)
    -   Client app is responsible for processing data messages.
    -   Data messages have only custom key-value pairs.

Note: only notification messages can be sent via the Firebase Console - data messages must be sent via the [FCM APIs](https://firebase.google.com/docs/cloud-messaging/server).

## Background notifications

If the notification message arrives while the app is in the background/not running, it will be displayed as a system notification.

If the user taps the system notification, this launches/resumes the app and the notification title, body and optional data payload is passed to the [onMessageReceived](#onMessageReceived) callback.
When the `onMessageReceived` is called in response to a user tapping a system notification while the app is in the background/not running, it will be passed the property `tap: "background"`.

By default, no callback is made to the plugin when the message arrives while the app is not in the foreground, since the display of the notification is entirely handled by the operating system.
However, there are platform-specific circumstances where a callback can be made, when a message arrives while the app is in the background or is inactive, that doesn't require user interaction to receive the message payload - see [Android background notifications](#android-background-notifications) and [iOS background notifications](#ios-background-notifications) for details.


## Foreground notifications

If the notification message arrives while the app is in running in the foreground, by default **it will NOT be displayed as a system notification**.
Instead the notification message payload will be passed to the [onMessageReceived](#onMessageReceived) callback for the plugin to handle (`tap` will not be set).

If you include the `notification_foreground` key in the `data` payload, the plugin will also display a system notification upon receiving the notification messages while the app is running in the foreground.
For example:

```json
{
    "name": "my_notification",
    "notification": {
        "body": "Notification body",
        "title": "Notification title"
    },
    "data": {
        "notification_foreground": "true"
    }
}
```

When the `onMessageReceived` is called in response to a user tapping a system notification while the app is in the foreground, it will be passed the property `tap: "foreground"`.

You can set additional properties of the foreground notification using the same key names as for [Data Message Notifications](#data-message-notification-keys).

## Android notifications

Notifications on Android can be customised to specify the sound, icon, LED colour, etc. that's displayed when the notification arrives.

### Android background notifications

If the notification message arrives while the app is in the background/not running, it will be displayed as a system notification.

If the user then taps the system notification, the app will be brought to the foreground and `onMessageReceived` will be invoked **again**, this time with `tap: "background"` indicating that the user tapped the system notification while the app was in the background.

If a notification message arrives while the app is in the background or inactive, it will be queued until the next time the app is resumed into the foreground. This is to ensure the Cordova application running in the Webview is in a state where it can receive the notification message.
Upon resuming, each queued notification will be sent to the `onMessageReceived` callback without the `tap` property, indicating the message was received without user interaction.

If you wish to attempt to immediately deliver the message payload to the `onMessageReceived` callback when the app is in the background or inactive (the default behaviour of this plugin prior to v18), you can set the `FIREBASE_MESSAGING_IMMEDIATE_PAYLOAD_DELIVERY` plugin variable to `true` at plugin install time:

    cordova plugin add cordova-plugin-firebasex-messaging --variable FIREBASE_MESSAGING_IMMEDIATE_PAYLOAD_DELIVERY=true

However there is no guarantee that the message will be delivered successfully, since the Cordova application running in the Webview may not be in a state where it can receive the notification message.


In addition to the title and body of the notification message, Android system notifications support specification of the following notification settings:

-   [Icon](#android-notification-icons)
-   [Sound](#android-notification-sound)
-   [Color accent](#android-notification-color)
-   [Channel ID](#android-notification-channels) (Android 8.0 (O) and above)
    -   This channel configuration enables you to specify:
        -   Sound
        -   Vibration
        -   LED light
        -   Badge
        -   Importance
        -   Visibility
    -   See [createChannel](#createchannel) for details.

Note: on tapping a background notification, if your app is not running, only the `data` section of the notification message payload will be delivered to [onMessageReceived](#onMessageReceived).
i.e. the notification title, body, etc. will not. Therefore if you need the properties of the notification message itself (e.g. title & body) to be delivered to [onMessageReceived](#onMessageReceived), you must duplicate these in the `data` section, e.g.:

```json
{
    "name": "my_notification",
    "notification": {
        "body": "Notification body",
        "title": "Notification title"
    },
    "data": {
        "notification_body": "Notification body",
        "notification_title": "Notification title"
    }
}
```

### Android foreground notifications

If the notification message arrives while the app is in the foreground, by default a system notification won't be displayed and the data will be passed to [onMessageReceived](#onMessageReceived).

However, if you set the `notification_foreground` key in the `data` section of the notification message payload, this will cause the plugin to display system notification when the message is received while your app is in the foreground. You can customise the notification using the same keys as for [Android data message notifications](#android-data-message-notifications).

### Android Notification Channels

-   Android 8 (O) introduced [notification channels](https://developer.android.com/training/notify-user/channels).
-   Notification channels are configured by the app and used to determine the **sound/lights/vibration** settings of system notifications.
-   By default, this plugin creates a default channel with [default properties](#default-android-channel-properties)
    -   These can be overridden via the [setDefaultChannel](#setdefaultchannel) function.
-   The plugin enables the creation of additional custom channels via the [createChannel](#createchannel) function.

First you need to create a custom channel with the desired settings, for example:

```javascript
var channel = {
    id: "my_channel_id",
    sound: "mysound",
    vibration: true,
    light: true,
    lightColor: parseInt("FF0000FF", 16).toString(),
    importance: 4,
    badge: true,
    visibility: 1,
};

FirebasexMessaging.createChannel(
    channel,
    function () {
        console.log("Channel created: " + channel.id);
    },
    function (error) {
        console.log("Create channel error: " + error);
    }
);
```

Then reference it from your message payload:

```json
{
    "name": "my_notification",
    "notification": {
        "body": "Notification body",
        "title": "Notification title"
    },
    "android": {
        "notification": {
            "channel_id": "my_channel_id"
        }
    }
}
```

#### Android 7 and below

-   the channel referenced in the message payload will be ignored
-   the sound setting of system notifications is specified in the notification message itself - see [Android Notification Sound](#android-notification-sound).

### Android Notification Icons

By default the plugin will use the default app icon for notification messages.

#### Android Default Notification Icon

To define a custom default notification icon, you need to create the images and deploy them to the `<projectroot>/platforms/android/app/src/main/res/<drawable-DPI>` folders.
The easiest way to create the images is using the [Image Asset Studio in Android Studio](https://developer.android.com/studio/write/image-asset-studio#create-notification) or using the [Android Asset Studio webapp](https://romannurik.github.io/AndroidAssetStudio/icons-notification.html#source.type=clipart&source.clipart=ac_unit&source.space.trim=1&source.space.pad=0&name=notification_icon).

The icons should be monochrome transparent PNGs with the following sizes:

-   mdpi: 24x24
-   hdpi: 36x36
-   xhdpi: 48x48
-   xxhdpi: 72x72
-   xxxhdpi: 96x96

Once you've created the images, you need to deploy them from your Cordova project to the native Android project.
To do this, copy the `drawable-DPI` image directories into your Cordova project and add `<resource-file>` entries to the `<platform name="android">` section of your `config.xml`, where `src` specifies the relative path to the images files within your Cordova project directory.

For example, copy the`drawable-DPI` image directories to `<projectroot>/res/android/` and add the following to your `config.xml`:

```xml
<platform name="android">
    <resource-file src="res/android/drawable-mdpi/notification_icon.png" target="app/src/main/res/drawable-mdpi/notification_icon.png" />
    <resource-file src="res/android/drawable-hdpi/notification_icon.png" target="app/src/main/res/drawable-hdpi/notification_icon.png" />
    <resource-file src="res/android/drawable-xhdpi/notification_icon.png" target="app/src/main/res/drawable-xhdpi/notification_icon.png" />
    <resource-file src="res/android/drawable-xxhdpi/notification_icon.png" target="app/src/main/res/drawable-xxhdpi/notification_icon.png" />
    <resource-file src="res/android/drawable-xxxhdpi/notification_icon.png" target="app/src/main/res/drawable-xxxhdpi/notification_icon.png" />
</platform>
```

The default notification icon images **must** be named `notification_icon.png`.

You then need to add a `<config-file>` block to the `config.xml` which will instruct Firebase to use your icon as the default for notifications:

```xml
<platform name="android">
    <config-file target="AndroidManifest.xml" parent="/manifest/application">
        <meta-data android:name="com.google.firebase.messaging.default_notification_icon" android:resource="@drawable/notification_icon" />
    </config-file>
</platform>
```

#### Android Large Notification Icon

The default notification icons above are monochrome, however you can additionally define a larger multi-coloured icon.

**NOTE:** FCM currently does not support large icons in system notifications displayed for notification messages received in the while the app is in the background (or not running).
So the large icon will currently only be used if specified in [data messages](#android-data-messages) or [foreground notifications](#foreground-notifications).

The large icon image should be a PNG-24 that's 256x256 pixels and must be named `notification_icon_large.png` and should be placed in the `drawable-xxxhdpi` resource directory.
As with the small icons, you'll need to add a `<resource-file>` entry to the `<platform name="android">` section of your `config.xml`:

```xml
<platform name="android">
    <resource-file src="res/android/drawable-xxxhdpi/notification_icon_large.png" target="app/src/main/res/drawable-xxxhdpi/notification_icon_large.png" />
</platform>
```

#### Android Custom Notification Icons

You can define additional sets of notification icons in the same manner as above.
These can be specified in notification or data messages.

For example:

```xml
        <resource-file src="res/android/drawable-mdpi/my_icon.png" target="app/src/main/res/drawable-mdpi/my_icon.png" />
        <resource-file src="res/android/drawable-hdpi/my_icon.png" target="app/src/main/res/drawable-hdpi/my_icon.png" />
        <resource-file src="res/android/drawable-xhdpi/my_icon.png" target="app/src/main/res/drawable-xhdpi/my_icon.png" />
        <resource-file src="res/android/drawable-xxhdpi/my_icon.png" target="app/src/main/res/drawable-xxhdpi/my_icon.png" />
        <resource-file src="res/android/drawable-xxxhdpi/my_icon.png" target="app/src/main/res/drawable-xxxhdpi/my_icon.png" />
        <resource-file src="res/android/drawable-xxxhdpi/my_icon_large.png" target="app/src/main/res/drawable-xxxhdpi/my_icon_large.png" />
```

When sending an FCM notification message, you will then specify the icon name in the `android.notification` section, for example:

```json
{
    "name": "my_notification",
    "notification": {
        "body": "Notification body",
        "title": "Notification title"
    },
    "android": {
        "notification": {
            "icon": "my_icon"
        }
    },
    "data": {
        "notification_foreground": "true"
    }
}
```

You can also reference these icons in [data messages](#android-data-messages), for example:

```json
{
    "name": "my_data",
    "data": {
        "notification_foreground": "true",
        "notification_body": "Notification body",
        "notification_title": "Notification title",
        "notification_android_icon": "my_icon"
    }
}
```

### Android Notification Color

On Android Lollipop (5.0/API 21) and above you can set the default accent color for the notification by adding a color setting.
This is defined as an [ARGB colour](<https://en.wikipedia.org/wiki/RGBA_color_space#ARGB_(word-order)>) which the plugin sets by default to `#FF00FFFF` (cyan).
Note: On Android 7 and above, the accent color can only be set for the notification displayed in the system tray area - the icon in the statusbar is always white.

You can override this default by specifying a value using the `ANDROID_ICON_ACCENT` plugin variable during plugin installation of `cordova-plugin-firebasex-core`, for example:

    cordova plugin add cordova-plugin-firebasex-core --variable ANDROID_ICON_ACCENT=#FF123456

You can override the default color accent by specifying the `colour` key as an RGB value in a notification message, e.g.:

```json
{
    "name": "my_notification",
    "notification": {
        "body": "Notification body",
        "title": "Notification title"
    },
    "android": {
        "notification": {
            "color": "#00ff00"
        }
    }
}
```

And in a data message:

```json
{
    "name": "my_data",
    "data": {
        "notification_foreground": "true",
        "notification_body": "Notification body",
        "notification_title": "Notification title",
        "notification_android_color": "#00ff00"
    }
}
```

### Android Notification Sound

You can specify custom sounds for notifications or play the device default notification sound.

Custom sound files must be in `.mp3` format and deployed to the `/res/raw` directory in the Android project.
To do this, you can add `<resource-file>` tags to your `config.xml` to deploy the files, for example:

```xml
<platform name="android">
    <resource-file src="res/android/raw/my_sound.mp3" target="app/src/main/res/raw/my_sound.mp3" />
</platform>
```

To ensure your custom sounds works on all versions of Android, be sure to include both the channel name and sound name in your message payload (see below for details), for example:

```json
{
    "name": "my_notification",
    "notification": {
        "body": "Notification body",
        "title": "Notification title"
    },
    "android": {
        "notification": {
            "channel_id": "my_channel_id",
            "sound": "my_sound"
        }
    }
}
```

#### Android 8.0 and above

On Android 8.0 and above, the notification sound is specified by which [Android notification channel](#android-notification-channels) is referenced in the notification message payload.
First create a channel that references your sound, for example:

```javascript
var channel = {
    id: "my_channel_id",
    sound: "my_sound",
};

FirebasexMessaging.createChannel(
    channel,
    function () {
        console.log("Channel created: " + channel.id);
    },
    function (error) {
        console.log("Create channel error: " + error);
    }
);
```

Then reference that channel in your message payload:

```json
{
    "name": "my_notification",
    "notification": {
        "body": "Notification body",
        "title": "Notification title"
    },
    "android": {
        "notification": {
            "channel_id": "my_channel_id"
        }
    }
}
```

#### On Android 7 and below

On Android 7 and below, you need to specify the sound file name in the `android.notification` section of the message payload.
For example:

```json
{
    "name": "my_notification",
    "notification": {
        "body": "Notification body",
        "title": "Notification title"
    },
    "android": {
        "notification": {
            "sound": "my_sound"
        }
    }
}
```

And in a data message by specifying it in the `data` section:

```json
{
    "name": "my_data",
    "data": {
        "notification_foreground": "true",
        "notification_body": "Notification body",
        "notification_title": "Notification title",
        "notification_android_sound": "my_sound"
    }
}
```

-   To play the default notification sound, set `"sound": "default"`.
-   To display a silent notification (no sound), omit the `sound` key from the message.

### Android cloud message types

The type of payload data in an FCM message influences how the message will be delivered to the app dependent on its run state, as outlined in [this Firebase documentation](https://firebase.google.com/docs/cloud-messaging/android/receive).

| App run state | Notification payload                               | Data payload                                              | Notification+Data payload                                                                                                                                                           |
| ------------- | -------------------------------------------------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Foreground    | `onMessageReceived`                                | `onMessageReceived`                                       | `onMessageReceived`                                                                                                                                                                 |
| Background    | System tray<sup>[[1]](#messagetypefootnote1)</sup> | `onMessageReceived`                                       | Notification payload: System tray<sup>[[1]](#messagetypefootnote1)</sup> <br/> Data payload: `onMessageReceived` via extras of New Intent<sup>[[2]](#messagetypefootnote2)</sup>    |
| Not running   | System tray<sup>[[1]](#messagetypefootnote1)</sup> | **Never received**<sup>[[3]](#messagetypefootnote3)</sup> | Notification payload: System tray<sup>[[1]](#messagetypefootnote1)</sup> <br/> Data payload: `onMessageReceived` via extras of Launch Intent<sup>[[2]](#messagetypefootnote2)</sup> |

<a name="messagetypefootnote1">1</a>: If user taps the system notification, its payload is delivered to `onMessageReceived`

<a name="messagetypefootnote2">2</a>: The data payload is only delivered as an extras Bundle Intent if the user taps the system notification.
Otherwise it will not be delivered as outlined in [this Firebase documentation](https://firebase.google.com/docs/cloud-messaging/concept-options#notification-messages-with-optional-data-payload).

<a name="messagetypefootnote3">3</a>: If the app is not running/has been task-killed when the data message arrives, it will never be received by the app.

## iOS notifications

Notifications on iOS can be customised to specify the sound and badge number that's displayed when the notification arrives.

Notification settings are specified in the `apns.payload.aps` key of the notification message payload.
For example:

```json
{
    "name": "my_notification",
    "notification": {
        "body": "Notification body",
        "title": "Notification title"
    },
    "apns": {
        "payload": {
            "aps": {
                "sound": "default",
                "badge": 1,
                "content-available": 1
            }
        }
    }
}
```

### iOS background notifications

If the notification message arrives while the app is in the background/not running, it will be displayed as a system notification.

If the user then taps the system notification, the app will be brought to the foreground and `onMessageReceived` will be invoked **again**, this time with `tap: "background"` indicating that the user tapped the system notification while the app was in the background.

If the app is in the background or inactive when the notification message arrives, the message can be queued so that the next time the app is resumed from the background, the `onMessageReceived` callback is invoked with the notification payload without requiring user interaction (i.e. tapping the system notification).
To do this you must specify `"content-available": 1` in the `apns.payload.aps` section of the message payload - see the [Apple documentation](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CreatingtheNotificationPayload.html#//apple_ref/doc/uid/TP40008194-CH10-SW8) for more information.
When app is next launched/resumed from the background, any queued notification payloads will be sent to the `onMessageReceived` callback without the `tap` property, indicating the message was received without user interaction.

If you wish to attempt to immediately deliver the message payload to the `onMessageReceived` callback when the app is in the background or inactive (the default behaviour of this plugin prior to v18), you can set the `FIREBASE_MESSAGING_IMMEDIATE_PAYLOAD_DELIVERY` plugin variable to `true` at plugin install time:

    cordova plugin add cordova-plugin-firebasex-messaging --variable FIREBASE_MESSAGING_IMMEDIATE_PAYLOAD_DELIVERY=true

However there is no guarantee that the message will be delivered successfully, since the Cordova application running in the Webview may not be in a state where it can receive the notification message.

### iOS notification sound

You can specify custom sounds for notifications or play the device default notification sound.

Custom sound files must be in a supported audio format (see [this Apple documentation](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SupportingNotificationsinYourApp.html#//apple_ref/doc/uid/TP40008194-CH4-SW10) for supported formats).
For example to convert an `.mp3` file to the supported `.caf` format run:

    afconvert my_sound.mp3 my_sound.caf -d ima4 -f caff -v

Sound files must be deployed with the iOS application bundle.
To do this, you can add `<resource-file>` tags to your `config.xml` to deploy the files, for example:

```xml
<platform name="ios">
    <resource-file src="res/ios/sound/my_sound.caf" />
</platform>
```

In a notification message, specify the `sound` key in the `apns.payload.aps` section, for example:

```json
{
    "name": "my_notification",
    "notification": {
        "body": "Notification body",
        "title": "Notification title"
    },
    "apns": {
        "payload": {
            "aps": {
                "sound": "my_sound.caf"
            }
        }
    }
}
```

-   To play the default notification sound, set `"sound": "default"`.
-   To display a silent notification (no sound), omit the `sound` key from the message.

In a data message, specify the `notification_ios_sound` key in the `data` section:

```json
{
    "name": "my_data",
    "data": {
        "notification_foreground": "true",
        "notification_body": "Notification body",
        "notification_title": "Notification title",
        "notification_ios_sound": "my_sound.caf"
    }
}
```

### iOS critical notifications

iOS offers the option to send critical push notifications. These kind of notifications appear even when your iPhone or iPad is in Do Not Disturb mode or silenced. Sending critical notifications requires a special entitlement that needs to be issued by Apple.
Use the plugin variable `IOS_ENABLE_CRITICAL_ALERTS_ENABLED=true` to enable the critical push notifications capability.
A user also needs to explicitly [grant permission](#grantcriticalpermission) to receive critical alerts.

### iOS badge number

In a notification message, specify the `badge` key in the `apns.payload.aps` section, for example:

```json
{
    "name": "my_notification",
    "notification": {
        "body": "Notification body",
        "title": "Notification title"
    },
    "apns": {
        "payload": {
            "aps": {
                "badge": 1
            }
        }
    }
}
```

In a data message, specify the `notification_ios_badge` key in the `data` section:

```json
{
    "name": "my_data",
    "data": {
        "notification_foreground": "true",
        "notification_body": "Notification body",
        "notification_title": "Notification title",
        "notification_ios_badge": 1
    }
}
```

### iOS actionable notifications

[Actionable notifications](https://developer.apple.com/documentation/usernotifications/declaring_your_actionable_notification_types) are supported on iOS:

<img width="300" src="https://user-images.githubusercontent.com/2345062/90025071-88c0a180-dcad-11ea-86f7-033f84601a56.png"/>
<img width="300" src="https://user-images.githubusercontent.com/2345062/90028234-531db780-dcb1-11ea-9df3-6bfcf8f2e9d8.png"/>

To use them in your app you must do the following:

1. Add a `pn-actions.json` file to your Cordova project which defines categories and actions, for example:

```json
{
    "PushNotificationActions": [
        {
            "category": "news",
            "actions": [
                {
                    "id": "read",
                    "title": "Read",
                    "foreground": true
                },
                {
                    "id": "skip",
                    "title": "Skip"
                },
                {
                    "id": "delete",
                    "title": "Delete",
                    "destructive": true
                }
            ]
        }
    ]
}
```

Note the `foreground` and `destructive` options correspond to the equivalent [UNNotificationActionOptions](https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions?language=objc).

2. Reference it as a resource file in your `config.xml`:

```xml
    <platform name="ios">
        ...
        <resource-file src="relative/path/to/pn-actions.json" />
    </platform>
```

3. Add a category entry to your FCM message payload which references one of your categories:

```json
{
    "notification": {
        "title": "iOS Actionable Notification",
        "body": "With custom buttons"
    },
    "apns": {
        "payload": {
            "aps": {
                "category": "news"
            }
        }
    }
}
```

When the notification arrives, if the user presses an action button the [`onMessageReceived()`](#onmessagereceived) function is invoked with the notification message payload, including the corresponding action ID.
For example:

```json
{
    "action": "read",
    "google.c.a.e": "1",
    "notification_foreground": "true",
    "aps": {
        "alert": {
            "title": "iOS Actionable Notification",
            "body": "With custom buttons"
        },
        "category": "news"
    },
    "gcm.message_id": "1597240847657854",
    "tap": "background",
    "messageType": "notification"
}
```

So you can obtain the category with `message.aps.category` and the action with `message.action` and handle this appropriately in your app code.

Notes:

-   Actionable notifications are currently only available for iOS - not Android
-   To reveal the notification action buttons, the user must drag downwards on the notification dialog
-   Actionable notifications work with both foreground and background (system) notifications
-   If your app is in the background/not running when the notification message arrives and a system notification is displayed, if the user chooses an action (instead of tapping the notification dialog body), your app will not be launched/foregrounded but [`onMessageReceived()`](#onmessagereceived) will be invoked, enabling your app code to handle the user's action selection silently in the background.

### iOS notification settings button

<img width="300" src="https://i.stack.imgur.com/84LDU.jpg">

Adding such a Button is possible with this Plugin.
To enable this Feature, you need to pass `true` for **requestWithProvidesAppNotificationSettings** when you [request the Permission](#grantpermission).

You then need to subscribe to `onOpenSettings` and open your apps notification settings page.

## Data messages

FCM data messages are sent as an arbitrary k/v structure and by default are passed to the app for it to handle them.

**NOTE:** FCM data messages **cannot** be sent from the Firebase Console - they can only be sent via the FCM APIs.

### Data message notifications

This plugin enables a data message to be displayed as a system notification.
To have the app display a notification when the data message arrives, you need to set the `notification_foreground` key in the `data` section.
You can then set a `notification_title` and `notification_body`, for example:

```json
{
    "name": "my_data",
    "data": {
        "notification_foreground": "true",
        "notification_body": "Notification body",
        "notification_title": "Notification title",
        "foo": "bar"
    }
}
```

Additional platform-specific notification options can be set using the additional keys below (which are only relevant if the `notification_foreground` key is set).

Note: [foreground notification messages](#foreground-notifications) can also make use of these keys.

#### Android data message notifications

On Android:

-   Data messages that arrive while your app is running in the foreground or running in the background will be immediately passed to the `onMessageReceived()` Javascript handler in the Webview.
-   Data messages (not containing notification keys) that arrive while your app is **not running** will be passed to the `onMessageReceived()` Javascript handler when the app is next launched.
-   Data messages containing notification keys that arrive while your app is running or **not running** will be displayed as a system notification.

The following Android-specific keys are supported and should be placed inside the `data` section:

-   `notification_android_id` - Identifier used to replace existing notifications in the notification drawer
    -   If not specified, each request creates a new notification.
    -   If specified and a notification with the same tag is already being shown, the new notification replaces the existing one in the notification drawer.
-   `notification_android_body_html` - If is passed, the body of a notification is processed as if it were html, you can use `<b>, <i> or <s>`
    -   If not specified, the body of the notification will be processed as plain text.
-   `notification_android_icon` - name of a [custom notification icon](#android-custom-notification-icons) in the drawable resources
    -   if not specified, the plugin will use the default `notification_icon` if it exists; otherwise the default app icon will be displayed
    -   if a [large icon](#android-large-notification-icon) has been defined, it will also be displayed in the system notification.
-   `notification_android_color` - the [color accent](#android-notification-color) to use for the small notification icon
    -   if not specified, the default color accent will be used
-   `notification_android_image` - Specifies the image notification
    -   if not specified, the notification will not show any image
-   `notification_android_image_type` - Specifies the image notification type
    -   Possible values:
        -   `square` - The image is displayed in the default format.
        -   `circle` - This notification displays the image in circular format.
        -   `big_picture` - Displays the image like `square` type, but the notification can be expanded and show the image in a big picture, example: https://developer.android.com/training/notify-user/expanded#image-style
    -   Defaults to `square` if not specified.
-   `notification_android_channel_id` - ID of the [notification channel](#android-notification-channels) to use to display the notification
    -   Only applies to Android 8.0 and above
    -   If not specified, the [default notification channel](#default-android-channel-properties) will be used.
        -   You can override the default configuration for the default notification channel using [setDefaultChannel](#setdefaultchannel).
    -   You can create additional channels using [createChannel](#createchannel).
-   `notification_android_priority` - Specifies the notification priority
    -   Possible values:
        -   `2` - Highest notification priority for your application's most important items that require the user's prompt attention or input.
        -   `1` - Higher notification priority for more important notifications or alerts.
        -   `0` - Default notification priority.
        -   `-1` - Lower notification priority for items that are less important.
        -   `-2` - Lowest notification priority. These items might not be shown to the user except under special circumstances, such as detailed notification logs.
    -   Defaults to `2` if not specified.
-   `notification_android_visibility` - Specifies the notification visibility
    -   Possible values:
        -   `1` - Show this notification in its entirety on all lockscreens.
        -   `0` - Show this notification on all lockscreens, but conceal sensitive or private information on secure lockscreens.
        -   `-1` - Do not reveal any part of this notification on a secure lockscreen.
    -   Defaults to `1` if not specified.

The following keys only apply to Android 7 and below.
On Android 8 and above they will be ignored - the `notification_android_channel_id` property should be used to specify a [notification channel](#android-notification-channels) with equivalent settings.

-   `notification_android_sound` - name of a sound resource to play as the [notification sound](#android-notification-sound)
    -   if not specified, no sound is played
    -   `default` plays the default device notification sound
    -   otherwise should be the name of an `.mp3` file in the `/res/raw` directory, e.g. `my_sound.mp3` => `"sounds": "my_sound"`
-   `notification_android_lights` - color and pattern to use to blink the LED light
    -   if not defined, LED will not blink
    -   in the format `ARGB, time_on_ms, time_off_ms` where
        -   `ARGB` is an ARGB color definition e.g. `#ffff0000`
        -   `time_on_ms` is the time in milliseconds to turn the LED on for
        -   `time_off_ms` is the time in milliseconds to turn the LED off for
    -   e.g. `"lights": "#ffff0000, 250, 250"`
-   `notification_android_vibrate` - pattern of vibrations to use when the message arrives
    -   if not specified, device will not vibrate
    -   an array of numbers specifying the time in milliseconds to vibrate
    -   e.g. `"vibrate": "500, 200, 500"`

Example data message with Android notification keys:

```json
{
    "name": "my_data_message",
    "data": {
        "notification_foreground": "true",
        "notification_body": "Notification body",
        "notification_title": "Notification title",
        "notification_android_channel_id": "my_channel",
        "notification_android_priority": "2",
        "notification_android_visibility": "1",
        "notification_android_color": "#ff0000",
        "notification_android_icon": "coffee",
        "notification_android_image": "https://example.com/avatar.jpg",
        "notification_android_image_type": "circle",
        "notification_android_sound": "my_sound",
        "notification_android_vibrate": "500, 200, 500",
        "notification_android_lights": "#ffff0000, 250, 250"
    }
}
```

#### iOS data message notifications

On iOS:

-   Data messages that arrive while your app is running in the foreground or running in the background will be immediately passed to the `onMessageReceived()` Javascript handler in the Webview.
-   Data messages that arrive while your app is **not running** will **NOT be received by your app!**

The following iOS-specific keys are supported and should be placed inside the `data` section:

-   `notification_ios_sound` - Sound to play when the notification is displayed
    -   To play a custom sound, set the name of the sound file bundled with your app, e.g. `"sound": "my_sound.caf"` - see [iOS notification sound](#ios-notification-sound) for more info.
    -   To play the default notification sound, set `"sound": "default"`.
    -   To display a silent notification (no sound), omit the `sound` key from the message.
-   `notification_ios_badge` - Badge number to display on app icon on home screen.
-   `notification_ios_image_jpg` - Specifies the `jpg` image notification, to use this you need to have configured the `NotificationService` - [Tutorial to set it up](docs/IOS_NOTIFICATION_SERVICE.md)
-   `notification_ios_image_png` - Specifies the `png` image notification, to use this you need to have configured the `NotificationService` - [Tutorial to set it up](docs/IOS_NOTIFICATION_SERVICE.md)
-   `notification_ios_image_gif` - Specifies the `gif` image notification, to use this you need to have configured the `NotificationService` - [Tutorial to set it up](docs/IOS_NOTIFICATION_SERVICE.md)

For example:

```json
{
    "name": "my_data",
    "data": {
        "notification_foreground": "true",
        "notification_body": "Notification body",
        "notification_title": "Notification title",
        "notification_ios_sound": "my_sound.caf",
        "notification_ios_badge": 1,
        "notification_ios_image_png": "https://example.com/avatar.png"
    }
}
```

## Custom FCM message handling

In some cases you may want to handle certain incoming FCM messages differently rather than with the default behaviour of this plugin.
Therefore this plugin provides a mechanism by which you can implement your own custom FCM message handling for specific FCM messages which bypasses handling of those messages by this plugin.
To do this requires you to write native handlers for Android & iOS which hook into the native code of this plugin.

### Android

You'll need to add a native class which extends the [`FirebasePluginMessageReceiver` abstract class](src/android/FirebasePluginMessageReceiver.java) and implements the `onMessageReceived()` and `sendMessage()` abstract methods.

### iOS

You'll need to add a native class which extends the [`FirebasePluginMessageReceiver` abstract class](src/ios/FirebasePluginMessageReceiver.h) and implements the `sendNotification()` abstract method.

# API

The list of available methods for this plugin is described below.

## Notifications and data messages

The plugin is capable of receiving push notifications and FCM data messages.

See [Cloud messaging](#cloud-messaging) section for more.

### getToken

Get the current FCM token.
Null if the token has not been allocated yet by the Firebase SDK.

**Parameters**:

-   {function} success - callback function which will be passed the {string} token as an argument
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.getToken(
    function (fcmToken) {
        console.log(fcmToken);
    },
    function (error) {
        console.error(error);
    }
);
```

Note that token will be null if it has not been established yet.

### getId

Get the app instance ID (a constant ID which persists as long as the app is not uninstalled/reinstalled).
Null if the ID has not been allocated yet by the Firebase SDK.

**Parameters**:

-   {function} success - callback function which will be passed the {string} ID as an argument
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.getId(
    function (appInstanceId) {
        console.log(appInstanceId);
    },
    function (error) {
        console.error(error);
    }
);
```

Note that ID will be null if it has not been established yet.

### onTokenRefresh

Registers a handler to call when the FCM token changes.
This is the best way to get the token as soon as it has been allocated.
This will be called on the first run after app install when a token is first allocated.
It may also be called again under other circumstances, e.g. if `unregister()` is called or Firebase allocates a new token for other reasons.
You can use this callback to return the token to your server to keep the FCM token associated with a given user up-to-date.

**Parameters**:

-   {function} success - callback function which will be passed the {string} token as an argument
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.onTokenRefresh(
    function (fcmToken) {
        console.log(fcmToken);
    },
    function (error) {
        console.error(error);
    }
);
```

### getAPNSToken

iOS only.
Get the APNS token allocated for this app install.
Note that token will be null if it has not been allocated yet.

**Parameters**:

-   {function} success - callback function which will be passed the {string} APNS token as an argument
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.getAPNSToken(
    function (apnsToken) {
        console.log(apnsToken);
    },
    function (error) {
        console.error(error);
    }
);
```

### onApnsTokenReceived

iOS only.
Registers a handler to call when the APNS token is allocated.
This will be called once when remote notifications permission has been granted by the user at runtime.

**Parameters**:

-   {function} success - callback function which will be passed the {string} token as an argument
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.onApnsTokenReceived(
    function (apnsToken) {
        console.log(apnsToken);
    },
    function (error) {
        console.error(error);
    }
);
```

### onOpenSettings

iOS only.
Registers a callback function to invoke when the AppNotificationSettingsButton is tapped by the user.

**Parameters**:

-   {function} success - callback function which will be invoked without any argument
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.onOpenSettings(
    function () {
        console.log("Redirect to App Notification Settings Page here");
    },
    function (error) {
        console.error(error);
    }
);
```

### onMessageReceived

Registers a callback function to invoke when:

-   a notification or data message is received by the app
-   a system notification is tapped by the user

**Parameters**:

-   {function} success - callback function which will be passed the {object} message as an argument
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.onMessageReceived(
    function (message) {
        console.log("Message type: " + message.messageType);
        if (message.messageType === "notification") {
            console.log("Notification message received");
            if (message.tap) {
                console.log("Tapped in " + message.tap);
            }
        }
        console.dir(message);
    },
    function (error) {
        console.error(error);
    }
);
```

The `message` object passed to the callback function will contain the platform-specific FCM message payload along with the following keys:

-   `messageType=notification|data` - indicates if received message is a notification or data message
-   `tap=foreground|background` - set if the call to `onMessageReceived()` was initiated by user tapping on a system notification.
    -   indicates if the system notification was tapped while the app was in the foreground or background.
    -   not set if no system notification was tapped (i.e. message was received directly from FCM rather than via a user tap on a system notification).

Notification message flow:

1. App is in foreground:
   a. By default, when a notification message arrives the app receives the notification message payload in the `onMessageReceived` JavaScript callback without any system notification on the device itself.
   b. If the `data` section contains the `notification_foreground` key, the plugin will display a system notification while in the foreground.
2. App is in background:
   a. User receives the notification message as a system notification in the device notification bar
   b. User taps the system notification which launches the app
   b. User receives the notification message payload in the `onMessageReceived` JavaScript callback

Data message flow:

1. App is in foreground:
   a. By default, when a data message arrives the app receives the data message payload in the `onMessageReceived` JavaScript callback without any system notification on the device itself.
   b. If the `data` section contains the `notification_foreground` key, the plugin will display a system notification while in the foreground.
2. App is in background:
   a. The app receives the data message in the `onMessageReceived` JavaScript callback while in the background
   b. If the data message contains the [data message notification keys](#data-message-notifications), the plugin will display a system notification for the data message while in the background.

### grantPermission

Grant run-time permission to receive push notifications (will trigger user permission prompt).
iOS & Android 13+ (Android <= 12 will always return true).

On Android, the `POST_NOTIFICATIONS` permission must be added to the `AndroidManifest.xml` file by inserting the following into your `config.xml` file:

```xml
<config-file target="AndroidManifest.xml" parent="/*">
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
</config-file>
```

Note, in addition to removing and re-adding the android platform, you may need to add the following attribute to `<widget>` in your `config.xml` file to avoid a parse error when building: `xmlns:android="http://schemas.android.com/apk/res/android"`

**Parameters**:

-   {function} success - callback function which will be passed the {boolean} permission result as an argument
-   {function} error - callback function which will be passed a {string} error message as an argument
-   {boolean} requestWithProvidesAppNotificationSettings - (**iOS12+ only**) indicates if app provides AppNotificationSettingsButton

```javascript
FirebasexMessaging.grantPermission(function (hasPermission) {
    console.log(
        "Notifications permission was " + (hasPermission ? "granted" : "denied")
    );
});
```

### grantCriticalPermission

Grant critical permission to receive critical push notifications (will trigger additional prompt).
iOS 12.0+ only (Android will always return true).

**Parameters**:

-   {function} success - callback function which will be passed the {boolean} permission result as an argument
-   {function} error - callback function which will be passed a {string} error message as an argument

**Critical push notifications require a special entitlement that needs to be issued by Apple.**

```javascript
FirebasexMessaging.grantCriticalPermission(function (hasPermission) {
    console.log(
        "Critical notifications permission was " +
            (hasPermission ? "granted" : "denied")
    );
});
```

### hasPermission

Check permission to receive push notifications and return the result to a callback function as boolean.
On iOS, returns true if runtime permission for remote notifications is granted and enabled in Settings.
On Android, returns true if global remote notifications are enabled in the device settings and (on Android 13+) runtime permission for remote notifications is granted.

**Parameters**:

-   {function} success - callback function which will be passed the {boolean} permission result as an argument
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.hasPermission(function (hasPermission) {
    console.log("Permission is " + (hasPermission ? "granted" : "denied"));
});
```

### hasCriticalPermission

Check permission to receive critical push notifications and return the result to a callback function as boolean.
iOS 12.0+ only (Android will always return true).

**Critical push notifications require a special entitlement that needs to be issued by Apple.**

**Parameters**:

-   {function} success - callback function which will be passed the {boolean} permission result as an argument
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.hasCriticalPermission(function (hasPermission) {
    console.log(
        "Permission to send critical push notifications is " +
            (hasPermission ? "granted" : "denied")
    );
});
```

### unregister

Unregisters from Firebase Cloud Messaging by deleting the current FCM device token.
Use this to stop receiving push notifications associated with the current token.
e.g. call this when you logout user from your app.
By default, a new token will be generated as soon as the old one is removed.
To prevent a new token being generated, be sure to disable autoinit using [`setAutoInitEnabled()`](#setautoinitenabled) before calling [`unregister()`](#unregister).

You can disable autoinit on first run and therefore prevent an FCM token being allocated by default (allowing user opt-in) by setting the `FIREBASE_FCM_AUTOINIT_ENABLED` plugin variable at plugin installation time:

    cordova plugin add cordova-plugin-firebasex-messaging --variable FIREBASE_FCM_AUTOINIT_ENABLED=false

**Parameters**: None

```javascript
FirebasexMessaging.unregister();
```

### isAutoInitEnabled

Indicates whether autoinit is currently enabled.
If so, new FCM tokens will be automatically generated.

**Parameters**:

-   {function} success - callback function which will be passed the {boolean} result as an argument
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.isAutoInitEnabled(function (enabled) {
    console.log("Auto init is " + (enabled ? "enabled" : "disabled"));
});
```

### setAutoInitEnabled

Sets whether to autoinit new FCM tokens.
By default, a new token will be generated as soon as the old one is removed.
To prevent a new token being generated, be sure to disable autoinit using [`setAutoInitEnabled()`](#setautoinitenabled) before calling [`unregister()`](#unregister).

**Parameters**:

-   {boolean} enabled - set true to enable, false to disable
-   {function} success - callback function to call on successful execution of operation.
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.setAutoInitEnabled(false, function () {
    console.log("Auto init has been disabled ");
    FirebasexMessaging.unregister();
});
```

### setBadgeNumber

iOS only.
Set a number on the icon badge:

**Parameters**:

-   {integer} badgeNumber - number to set for the app badge

```javascript
FirebasexMessaging.setBadgeNumber(3);
```

Set 0 to clear the badge

```javascript
FirebasexMessaging.setBadgeNumber(0);
```

Note: this function is no longer available on Android (see [#124](https://github.com/dpa99c/cordova-plugin-firebasex/issues/124))

### getBadgeNumber

iOS only.
Get icon badge number:

**Parameters**:

-   {function} success - callback function which will be passed the {integer} current badge number as an argument

```javascript
FirebasexMessaging.getBadgeNumber(function (n) {
    console.log(n);
});
```

Note: this function is no longer available on Android (see [#124](https://github.com/dpa99c/cordova-plugin-firebasex/issues/124))

### clearAllNotifications

Clear all pending notifications from the drawer:

**Parameters**: None

```javascript
FirebasexMessaging.clearAllNotifications();
```

### subscribe

Subscribe to a topic.

Topic messaging allows you to send a message to multiple devices that have opted in to a particular topic.

**Parameters**:

-   {string} topicName - name of topic to subscribe to
-   {function} success - callback function which will be called on successful subscription
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.subscribe(
    "latest_news",
    function () {
        console.log("Subscribed to topic");
    },
    function (error) {
        console.error("Error subscribing to topic: " + error);
    }
);
```

### unsubscribe

Unsubscribe from a topic.

This will stop you receiving messages for that topic.

**Parameters**:

-   {string} topicName - name of topic to unsubscribe from
-   {function} success - callback function which will be called on successful unsubscription
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.unsubscribe(
    "latest_news",
    function () {
        console.log("Unsubscribed from topic");
    },
    function (error) {
        console.error("Error unsubscribing from topic: " + error);
    }
);
```

### createChannel

Android 8+ only.
Creates a custom channel to be used by notification messages which have the channel property set in the message payload to the `id` of the created channel:

-   For background (system) notifications: `android.notification.channel_id`
-   For foreground/data notifications: `data.notification_android_channel_id`

For each channel you may set the sound to be played, the color of the phone LED (if supported by the device), whether to vibrate and set vibration pattern (if supported by the device), importance and visibility.
Channels should be created as soon as possible (on program start) so notifications can work as expected.
A default channel is created by the plugin at app startup; the properties of this can be overridden see [setDefaultChannel](#setdefaultchannel)

Calling on Android 7 or below or another platform will have no effect.

Note: Each time you want to play a different sound, you need to create a new channel with a new unique ID - do not re-use the same channel ID even if you have called `deleteChannel()` ([see this comment](https://github.com/dpa99c/cordova-plugin-firebasex/issues/560#issuecomment-798407467)).

**Parameters**:

-   {object} - channel configuration object (see below for object keys/values)
-   {function} success - callback function which will be called on successful channel creation
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
// Define custom  channel - all keys are except 'id' are optional.
var channel = {
    // channel ID - must be unique per app package
    id: "my_channel_id",

    // Channel description. Default: empty string
    description: "Channel description",

    // Channel name. Default: empty string
    name: "Channel name",

    //The sound to play once a push comes. Default value: 'default'
    //Values allowed:
    //'default' - plays the default notification sound
    //'ringtone' - plays the currently set ringtone
    //'false' - silent; don't play any sound
    //filename - the filename of the sound file located in '/res/raw' without file extension (mysound.mp3 -> mysound)
    sound: "mysound",

    //Vibrate on new notification. Default value: true
    //Possible values:
    //Boolean - vibrate or not
    //Array - vibration pattern - e.g. [500, 200, 500] - milliseconds vibrate, milliseconds pause, vibrate, pause, etc.
    vibration: true,

    // Whether to blink the LED
    light: true,

    //LED color in ARGB format - this example BLUE color. If set to -1, light color will be default. Default value: -1.
    lightColor: parseInt("FF0000FF", 16).toString(),

    //Importance - integer from 0 to 4. Default value: 4
    //0 - none - no sound, does not show in the shade
    //1 - min - no sound, only shows in the shade, below the fold
    //2 - low - no sound, shows in the shade, and potentially in the status bar
    //3 - default - shows everywhere, makes noise, but does not visually intrude
    //4 - high - shows everywhere, makes noise and peeks
    importance: 4,

    //Show badge over app icon when non handled pushes are present. Default value: true
    badge: true,

    //Show message on locked screen. Default value: 1
    //Possible values (default 1):
    //-1 - secret - Do not reveal any part of the notification on a secure lockscreen.
    //0 - private - Show the notification on all lockscreens, but conceal sensitive or private information on secure lockscreens.
    //1 - public - Show the notification in its entirety on all lockscreens.
    visibility: 1,

    // Optionally specify the usage type of the notification. Defaults to USAGE_NOTIFICATION_RINGTONE ( =6)
    // For a list of all possible usages, see https://developer.android.com/reference/android/media/AudioAttributes.Builder#setUsage(int)

    usage: 6,
    // Optionally specify the stream type of the notification channel.
    // For a list of all possible values, see https://developer.android.com/reference/android/media/AudioAttributes.Builder#setLegacyStreamType(int)
    streamType: 5,
};

// Create the channel
FirebasexMessaging.createChannel(
    channel,
    function () {
        console.log("Channel created: " + channel.id);
    },
    function (error) {
        console.log("Create channel error: " + error);
    }
);
```

Example FCM v1 API notification message payload for invoking the above example channel:

```json
{
    "notification": {
        "title": "Notification title",
        "body": "Notification body"
    },
    "android": {
        "notification": {
            "channel_id": "my_channel_id"
        }
    }
}
```

If your Android app plays multiple sounds or effects, it's a good idea to create a channel for each likely combination. This is because once a channel is created you cannot override sounds/effects.
IE, expanding on the createChannel example:

```javascript
let soundList = ["train", "woop", "clock", "radar", "sonar"];
for (let key of soundList) {
    let name = "yourchannelprefix_" + key;
    channel.id = name;
    channel.sound = key;
    channel.name = "Your description " + key;

    // Create the channel
    FirebasexMessaging.createChannel(
        channel,
        function () {
            console.log(
                "Notification Channel created: " +
                    channel.id +
                    " " +
                    JSON.stringify(channel)
            );
        },
        function (error) {
            console.log("Create notification channel error: " + error);
        }
    );
}
```

Note, if you just have one sound / effect combination that the user can customise, just use setDefaultChannel when any changes are made.

### setDefaultChannel

Android 8+ only.
Overrides the properties for the default channel.
The default channel is used if no other channel exists or is specified in the notification.
Any options not specified will not be overridden.
Should be called as soon as possible (on app start) so default notifications will work as expected.
Calling on Android 7 or below or another platform will have no effect.

**Parameters**:

-   {object} - channel configuration object
-   {function} success - callback function which will be called on successfully setting default channel
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
var channel = {
    id: "my_default_channel",
    name: "My Default Name",
    description: "My Default Description",
    sound: "ringtone",
    vibration: [500, 200, 500],
    light: true,
    lightColor: parseInt("FF0000FF", 16).toString(),
    importance: 4,
    badge: false,
    visibility: -1,
};

FirebasexMessaging.setDefaultChannel(
    channel,
    function () {
        console.log("Default channel set");
    },
    function (error) {
        console.log("Set default channel error: " + error);
    }
);
```

### Default Android Channel Properties

The default channel is initialised at app startup with the following default settings:

```json
{
    "id": "fcm_default_channel",
    "name": "Default",
    "description": "",
    "sound": "default",
    "vibration": true,
    "light": true,
    "lightColor": -1,
    "importance": 4,
    "badge": true,
    "visibility": 1
}
```

### deleteChannel

Android 8+ only.
Removes a previously defined channel.
Calling on Android 7 or below or another platform will have no effect.

**Parameters**:

-   {string} - id of channel to delete
-   {function} success - callback function which will be called on successfully deleting channel
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.deleteChannel(
    "my_channel_id",
    function () {
        console.log("Channel deleted");
    },
    function (error) {
        console.log("Delete channel error: " + error);
    }
);
```

### listChannels

Android 8+ only.
Gets a list of all channels.
Calling on Android 7 or below or another platform will have no effect.

**Parameters**:

-   {function} success - callback function which will be passed the {array} of channel objects as an argument
-   {function} error - callback function which will be passed a {string} error message as an argument

```javascript
FirebasexMessaging.listChannels(
    function (channels) {
        if (typeof channels == "undefined") return;

        for (var i = 0; i < channels.length; i++) {
            console.log(
                "ID: " + channels[i].id + ", Name: " + channels[i].name
            );
        }
    },
    function (error) {
        alert("List channels error: " + error);
    }
);
```

# Reporting issues

Before reporting an issue with this plugin, please do the following:
- Check the existing [issues](https://github.com/dpa99c/cordova-plugin-firebasex-messaging/issues) and [pull requests](https://github.com/dpa99c/cordova-plugin-firebasex-messaging/pulls) for duplicates
- Ensure you are using the latest version of the plugin and its dependencies
- Include full details of the error including relevant logs and device/platform information
