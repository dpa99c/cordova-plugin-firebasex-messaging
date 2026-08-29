# Version 2.0.3
- fix: pin core plugin dependency to v2
- (ios) Resolve pending notification issues
	- Resolves [issue #4](https://github.com/dpa99c/cordova-plugin-firebasex-core/issues/4)
- Move `FirebasePluginMessageReceiver` from core plugin to messaging plugin.
	- Resolves [issue #1](https://github.com/dpa99c/cordova-plugin-firebasex-core/issues/1)
- fix(android): prevent loss of FCM notifications on cold start
	- Merged from [PR #2](https://github.com/dpa99c/cordova-plugin-firebasex-messaging/pull/2)
	- Resolves [issue #3](https://github.com/dpa99c/cordova-plugin-firebasex-messaging/issues/3)
- fix: add types field to package.json so TypeScript resolves type definitions
	- Merged from [PR #9](https://github.com/dpa99c/cordova-plugin-firebasex-messaging/pull/9)

# Version 2.0.2
- Move `FirebasePluginMessageReceiver` from core plugin to messaging plugin.
	- Resolves [issue #1](https://github.com/dpa99c/cordova-plugin-firebasex-core/issues/1

# Version 2.0.1
- (ios) bugfix: pin `cordova-plugin-firebasex-core@^2.0.0` to ensure SPM version is available for `cordova-ios@8+`.

# Version 2.0.0
- (ios) feat - BREAKING: Use Swift Package Manager (SPM) for Firebase SDK and other dependencies with `cordova-ios@8+`; continue to use Cocoapods for `cordova-ios@7`.
- (android) Update pinned Firebase SDK versions to BoM v34.14.0 (May 28, 2026)
	- https://firebase.google.com/support/release-notes/android#2026-05-28
- (ios) Update pinned Firebase SDK version to v12.14.0 (May 26, 2026)
	- https://firebase.google.com/support/release-notes/ios#version_12140_-_may_26_2026	
    
# Version 1.0.3
- fix: add missing WAKE_LOCK permission and Android IMMEDIATE_PAYLOAD_DELIVERY config.
- (android) Manage icon accent color for notifications.

# Version 1.0.2
- (ios) Fix hook script compatibility with cordova-ios@8.

# Version 1.0.1
- Fix plugin metadata

# Version 1.0.0
- Initial release of the modular plugin.
    - See [CHANGELOG](https://github.com/dpa99c/cordova-plugin-firebasex/blob/master/CHANGELOG.md) for the full changelog of the main plugin which includes this module as a dependency.