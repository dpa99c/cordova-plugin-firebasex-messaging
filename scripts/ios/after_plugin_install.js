/**
 * @file after_plugin_install.js
 * @brief Hook script that runs after the messaging plugin is installed on iOS.
 *
 * Updates the FirebaseMessaging pod version in the Podfile based on the
 * IOS_FIREBASE_SDK_VERSION plugin variable, allowing users to override the
 * default Firebase SDK version.
 *
 * Plugin variables are resolved using a 4-layer override strategy:
 * 1. Defaults from plugin.xml preferences (via hook context).
 * 2. Overrides from `config.xml` `<plugin><variable>` elements (wrapper and own plugin ID).
 * 3. Overrides from `package.json` `cordova.plugins` entries (wrapper and own plugin ID).
 * 4. CLI variables passed at install time (highest priority).
 */
var fs = require("fs");
var path = require("path");

/** @constant {string} The plugin identifier. */
var PLUGIN_ID = "cordova-plugin-firebasex-messaging";
/** @constant {string} The wrapper meta-plugin identifier used as a fallback source for plugin variables. */
var WRAPPER_PLUGIN_ID = "cordova-plugin-firebasex";

function isSwiftPackageManagerEnabled(projectRoot) {
    var iosPlatformPath = path.join(projectRoot, "platforms", "ios");
    var appSubDirPath = path.join(iosPlatformPath, "App");
    return fs.existsSync(appSubDirPath) && fs.statSync(appSubDirPath).isDirectory();
}

function updatePackageSwiftVersion(projectRoot, newVersion) {
    var packagePaths = [];
    var seen = {};
    var versionRegex = /(let\s+firebaseSDKVersion(?::\s*Version)?\s*=\s*")([^"]+)(")/;

    function addPackagePath(packagePath) {
        if (!packagePath || seen[packagePath] || !fs.existsSync(packagePath)) return;
        seen[packagePath] = true;
        packagePaths.push(packagePath);
    }

    function collectPackagePaths(rootDir, depth) {
        if (depth < 0 || !fs.existsSync(rootDir) || !fs.statSync(rootDir).isDirectory()) return;
        fs.readdirSync(rootDir).forEach(function(entry) {
            var entryPath = path.join(rootDir, entry);
            var stat = fs.statSync(entryPath);
            if (stat.isDirectory()) {
                collectPackagePaths(entryPath, depth - 1);
                return;
            }
            if (entry === "Package.swift") {
                var contents = fs.readFileSync(entryPath, "utf-8");
                if (contents.indexOf('name: "' + PLUGIN_ID + '"') !== -1) {
                    addPackagePath(entryPath);
                }
            }
        });
    }

    addPackagePath(path.join(projectRoot, "plugins", PLUGIN_ID, "Package.swift"));
    collectPackagePaths(path.join(projectRoot, "platforms", "ios"), 4);

    packagePaths.forEach(function(packagePath) {
        var contents = fs.readFileSync(packagePath, "utf-8");
        var match = contents.match(versionRegex);
        if (!match || match[2] === newVersion) return;
        fs.writeFileSync(packagePath, contents.replace(versionRegex, '$1' + newVersion + '$3'));
        console.log("[FirebasexMessaging] Firebase SDK version set to v" + newVersion + " in " + packagePath);
    });
}

/**
 * Resolves plugin variables using the 4-layer override strategy.
 *
 * @param {object} context - The Cordova hook context.
 * @returns {Object} Resolved plugin variable key/value pairs.
 */
function resolvePluginVariables(context) {
    var pluginVariables = {};

    // 1. Defaults from plugin.xml preferences
    var plugin = context.opts.plugin;
    if (plugin && plugin.pluginInfo && plugin.pluginInfo._et && plugin.pluginInfo._et._root && plugin.pluginInfo._et._root._children) {
        plugin.pluginInfo._et._root._children.forEach(function(child) {
            if (child.tag === "preference") {
                pluginVariables[child.attrib.name] = child.attrib.default;
            }
        });
    }

    // 2. Overrides from config.xml
    try {
        var configXmlPath = path.join(context.opts.projectRoot, "config.xml");
        if (fs.existsSync(configXmlPath)) {
            var configXml = fs.readFileSync(configXmlPath, "utf-8");
            [WRAPPER_PLUGIN_ID, PLUGIN_ID].forEach(function(pluginId) {
                var pluginRegex = new RegExp('<plugin[^>]+name="' + pluginId + '"[^>]*>(.*?)</plugin>', "s");
                var pluginMatch = configXml.match(pluginRegex);
                if (pluginMatch) {
                    var varRegex = /<variable\s+name="([^"]+)"\s+value="([^"]+)"\s*\/>/g;
                    var varMatch;
                    while ((varMatch = varRegex.exec(pluginMatch[1])) !== null) {
                        pluginVariables[varMatch[1]] = varMatch[2];
                    }
                }
            });
        } else {
            console.warn("[FirebasexMessaging] config.xml not found at " + configXmlPath + ". Cannot read plugin variables from config.xml.");
        }
    } catch (e) {
        console.warn("[FirebasexMessaging] Could not read config.xml for plugin variables: " + e.message);
    }

    // 3. Overrides from package.json
    try {
        var packageJsonPath = path.join(context.opts.projectRoot, "package.json");
        if (fs.existsSync(packageJsonPath)) {
            var packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf-8"));
            if (packageJson.cordova && packageJson.cordova.plugins) {
                [WRAPPER_PLUGIN_ID, PLUGIN_ID].forEach(function(pluginId) {
                    if (packageJson.cordova.plugins[pluginId]) {
                        var pluginVars = packageJson.cordova.plugins[pluginId];
                        for (var key in pluginVars) {
                            pluginVariables[key] = pluginVars[key];
                        }
                    }
                });
            }
        } else {
            console.warn("[FirebasexMessaging] package.json not found at " + packageJsonPath + ". Cannot read plugin variables from package.json.");
        }
    } catch (e) {
        console.warn("[FirebasexMessaging] Could not read package.json for plugin variables: " + e.message);
    }

    // 4. CLI variable overrides (highest priority)
    if (context.opts && context.opts.cli_variables) {
        Object.keys(context.opts.cli_variables).forEach(function(key) {
            pluginVariables[key] = context.opts.cli_variables[key];
        });
    }

    return pluginVariables;
}

/**
 * Cordova hook entry point.
 * Updates the FirebaseMessaging pod version in the Podfile.
 *
 * @param {object} context - The Cordova hook context.
 */
module.exports = function(context) {
    var pluginVariables = resolvePluginVariables(context);
    if (!pluginVariables["IOS_FIREBASE_SDK_VERSION"]){
        console.warn("[FirebasexMessaging] IOS_FIREBASE_SDK_VERSION variable not set. Skipping iOS dependency version update.");
        return;
    }

    if (isSwiftPackageManagerEnabled(context.opts.projectRoot)) {
        updatePackageSwiftVersion(context.opts.projectRoot, pluginVariables["IOS_FIREBASE_SDK_VERSION"]);
        return;
    }

    var iosPlatformPath = path.join(context.opts.projectRoot, "platforms", "ios");
    var podFilePath = path.join(iosPlatformPath, "Podfile");
    if (!fs.existsSync(podFilePath)) {
        return;
    }

    try {
        var podFileContents = fs.readFileSync(podFilePath, "utf-8");
        var sdkVersion = pluginVariables["IOS_FIREBASE_SDK_VERSION"];
        var versionRegex = /\d+\.\d+\.\d+[^'"]*/;
        var podRegEx = /pod 'FirebaseMessaging', '(\d+\.\d+\.\d+[^'"]*)'/g;
        var matches = podFileContents.match(podRegEx);
        if (matches) {
            var modified = false;
            matches.forEach(function(match) {
                var currentVersion = match.match(versionRegex)[0];
                if (currentVersion !== sdkVersion) {
                    podFileContents = podFileContents.replace(match, match.replace(currentVersion, sdkVersion));
                    modified = true;
                }
            });
            if (modified) {
                fs.writeFileSync(podFilePath, podFileContents);
                console.log("[FirebasexMessaging] Firebase SDK version set to v" + sdkVersion + " in Podfile");
            }
        }
    } catch(e) {
        console.warn("[FirebasexMessaging] Error updating Firebase Messaging pod version: " + e.message);
    }
};
