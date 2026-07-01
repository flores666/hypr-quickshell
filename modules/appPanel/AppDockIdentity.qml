import Quickshell
import Quickshell.Widgets
import QtQuick
import "../../services" as Services

QtObject {
    id: root

    function normalizeToken(value) {
        var text = String(value || "").trim().toLowerCase();
        if (text.length >= 8 && text.lastIndexOf(".desktop") === text.length - 8)
            text = text.substring(0, text.length - 8);
        if (text.indexOf("org.") === 0)
            text = text.substring(4);
        return text.replace(/[^a-z0-9]+/g, "");
    }

    function addUniqueToken(list, value) {
        var key = normalizeToken(value);
        var ignored = {
            "app": true,
            "apps": true,
            "application": true,
            "desktop": true,
            "electron": true,
            "gtk": true,
            "io": true,
            "net": true,
            "org": true,
            "com": true,
            "dev": true,
            "qt": true,
            "wayland": true,
            "x11": true
        };
        if (ignored[key])
            return;
        if (key.length > 0 && list.indexOf(key) < 0)
            list.push(key);
    }

    function addIdentityVariants(list, value) {
        var raw = String(value || "").trim();
        if (!raw)
            return;

        addUniqueToken(list, raw);
        addUniqueToken(list, appSubstitution(raw));
        addUniqueToken(list, reverseDomainNameAppName(raw));
        addUniqueToken(list, kebabNormalizedAppName(raw));

        var stem = raw.length >= 8 && raw.lastIndexOf(".desktop") === raw.length - 8 ? raw.substring(0, raw.length - 8) : raw;
        var parts = stem.split(/[.\-_]+/);
        for (var i = 0; i < parts.length; i++)
            addUniqueToken(list, parts[i]);
    }

    function canonicalAppToken(value) {
        var key = normalizeToken(appSubstitution(value));
        var aliases = {
            "navigator": "firefox",
            "firefox": "firefox",
            "mozillafirefox": "firefox",
            "orgmozillafirefox": "firefox",
            "firefoxdeveloperedition": "firefoxdeveloperedition",
            "obsidian": "obsidian",
            "mdobsidian": "obsidian",
            "telegramdesktop": "telegramdesktop",
            "orgtelegramdesktop": "telegramdesktop",
            "zed": "zed",
            "devzedzed": "zed",
            "code": "visualstudiocode",
            "vscode": "visualstudiocode",
            "visualstudiocode": "visualstudiocode",
            "comvisualstudiocode": "visualstudiocode",
            "codium": "vscodium",
            "vscodium": "vscodium",
            "zen": "zen",
            "zenbrowser": "zen",
            "zenalpha": "zen",
            "zenbeta": "zen",
            "orggnomenautilus": "nautilus",
            "gnomenautilus": "nautilus",
            "nautilus": "nautilus",
            "orgkdedolphin": "dolphin",
            "kdedolphin": "dolphin",
            "dolphin": "dolphin",
            "thunar": "thunar",
            "kitty": "kitty",
            "orgwezfurlongwezterm": "wezterm",
            "wezfurlongwezterm": "wezterm",
            "wezterm": "wezterm"
        };
        return aliases[key] || key;
    }

    function addCanonicalAppToken(list, value) {
        var raw = String(value || "").trim();
        if (!raw)
            return;

        var candidates = [
            raw,
            appSubstitution(raw),
            reverseDomainNameAppName(raw),
            kebabNormalizedAppName(raw)
        ];
        for (var i = 0; i < candidates.length; i++) {
            var token = canonicalAppToken(candidates[i]);
            var ignored = {
                "app": true,
                "apps": true,
                "application": true,
                "com": true,
                "desktop": true,
                "dev": true,
                "electron": true,
                "flatpak": true,
                "gtk": true,
                "io": true,
                "kde": true,
                "net": true,
                "org": true,
                "qt": true,
                "wayland": true,
                "x11": true
            };
            if (ignored[token])
                continue;
            if (token.length > 0 && list.indexOf(token) < 0)
                list.push(token);
        }
    }

    function appCanonicalKeys(app, extraValue) {
        var keys = [];
        if (app) {
            addCanonicalAppToken(keys, app.desktopId || "");
            addCanonicalAppToken(keys, app.sourceDesktopId || "");
            addCanonicalAppToken(keys, app.iconName || "");
            addCanonicalAppToken(keys, app.icon || "");
            addCanonicalAppToken(keys, app.executable || "");
            addCanonicalAppToken(keys, app.startupWmClass || "");
            var matchKeys = app.matchKeys || [];
            for (var i = 0; i < matchKeys.length; i++)
                addCanonicalAppToken(keys, matchKeys[i]);
        }
        addCanonicalAppToken(keys, extraValue || "");
        return keys;
    }

    function appIdentityKeys(app, extraValue) {
        var keys = [];
        if (app) {
            addIdentityVariants(keys, app.desktopId || "");
            addIdentityVariants(keys, app.name || "");
            addIdentityVariants(keys, app.displayName || "");
            addIdentityVariants(keys, app.iconName || "");
            addIdentityVariants(keys, app.icon || "");
            addIdentityVariants(keys, app.executable || "");
            addIdentityVariants(keys, app.startupWmClass || "");

            var matchKeys = app.matchKeys || [];
            for (var i = 0; i < matchKeys.length; i++)
                addUniqueToken(keys, matchKeys[i]);
        }
        addIdentityVariants(keys, extraValue || "");
        return keys;
    }

    function listsShareIdentity(a, b) {
        for (var i = 0; i < a.length; i++) {
            if (b.indexOf(a[i]) >= 0)
                return true;
        }
        return false;
    }

    function appsCompatible(appA, appB, extraA, extraB) {
        if (!appA || !appB)
            return false;
        var idA = String(appA.desktopId || "");
        var idB = String(appB.desktopId || "");
        if (idA && idB && idA === idB)
            return true;
        return listsShareIdentity(appCanonicalKeys(appA, extraA), appCanonicalKeys(appB, extraB));
    }

    function appMatchesKeys(app, keys) {
        if (!app)
            return false;
        return listsShareIdentity(appIdentityKeys(app, ""), keys || []);
    }

    function addRuntimeIdentity(list, value) {
        var raw = String(value || "").trim();
        if (!raw)
            return;

        addCanonicalAppToken(list, raw);
        addCanonicalAppToken(list, appSubstitution(raw));
        addCanonicalAppToken(list, reverseDomainNameAppName(raw));
        addCanonicalAppToken(list, kebabNormalizedAppName(raw));

        var stem = raw.length >= 8 && raw.lastIndexOf(".desktop") === raw.length - 8 ? raw.substring(0, raw.length - 8) : raw;
        var parts = stem.split(/[.\-_]+/);
        for (var i = 0; i < parts.length; i++)
            addCanonicalAppToken(list, parts[i]);
    }

    function runtimeAppKeysForWindow(window) {
        var result = [];
        var fields = [window && window.appId, window && window.rawClass, window && window.initialClass];
        for (var i = 0; i < fields.length; i++)
            addRuntimeIdentity(result, fields[i]);
        return result;
    }

    function runtimeAppKeyForWindow(window) {
        var keys = runtimeAppKeysForWindow(window);
        for (var i = 0; i < keys.length; i++) {
            if (pinnedAppForRuntimeKey(keys[i]))
                return keys[i];
        }
        var apps = Services.AppPanelService.apps || [];
        for (var k = 0; k < keys.length; k++) {
            for (var a = 0; a < apps.length; a++) {
                if (appMatchesRuntimeKey(apps[a], keys[k]))
                    return keys[k];
            }
        }
        return keys.length > 0 ? keys[0] : "";
    }

    function appMatchesRuntimeKey(app, appKey) {
        var key = String(appKey || "");
        if (!app || !key)
            return false;
        return appCanonicalKeys(app, "").indexOf(key) >= 0;
    }

    function pinnedAppForRuntimeKey(appKey) {
        var key = String(appKey || "");
        if (!key)
            return null;

        var pins = Services.AppPanelService.pinnedIds || [];
        for (var i = 0; i < pins.length; i++) {
            var pinId = String(pins[i] || "");
            var pinApp = Services.AppPanelService.appById(pinId);
            if (pinApp && appMatchesRuntimeKey(pinApp, key))
                return pinApp;
        }
        return null;
    }

    function appPinnedBonus(app) {
        if (!app)
            return 0;
        var desktopId = String(app.desktopId || "");
        if (Services.AppPanelService.isPinned(desktopId))
            return 24;

        var pins = Services.AppPanelService.pinnedIds || [];
        var keys = appCanonicalKeys(app, "");
        for (var i = 0; i < pins.length; i++) {
            var pinId = String(pins[i] || "");
            if (!pinId)
                continue;
            if (keys.indexOf(canonicalAppToken(pinId)) >= 0)
                return 18;
            var pinApp = Services.AppPanelService.appById(pinId);
            if (pinApp && appsCompatible(app, pinApp))
                return 18;
        }
        return 0;
    }

    function appOrderBonus(app) {
        if (!app)
            return 0;
        var desktopId = String(app.desktopId || "");
        if ((Services.AppPanelService.orderIds || []).indexOf(desktopId) >= 0)
            return 6;
        return 0;
    }

    function appLaunchBonus(app) {
        if (!app)
            return 0;
        var desktopId = String(app.desktopId || "");
        return Services.AppPanelService.launchingIds[desktopId] ? 18 : 0;
    }

    function appPreferenceBonus(app) {
        if (!app)
            return 0;
        return appPinnedBonus(app)
                + appOrderBonus(app)
                + appLaunchBonus(app)
                - (app.noDisplay ? 6 : 0);
    }

    function appFirstLetter(item) {
        var text = String(item && (item.displayName || item.name || item.appId || item.desktopId) || "A").trim();
        return text.length > 0 ? text.charAt(0).toUpperCase() : "A";
    }

    function isBrowserItem(item) {
        if (!item)
            return false;
        var text = [item.desktopId, item.name, item.displayName, item.command].join(" ");
        var key = normalizeToken(text);
        var browsers = ["firefox", "zenbrowser", "chromium", "googlechrome", "chrome", "brave", "vivaldi", "opera", "microsoftedge", "browser"];
        for (var i = 0; i < browsers.length; i++) {
            if (key.indexOf(browsers[i]) >= 0)
                return true;
        }
        return false;
    }

    function iconExists(iconName) {
        var name = String(iconName || "").trim();
        return name.length > 0
                && Quickshell.iconPath(name, true).length > 0
                && name.indexOf("image-missing") < 0;
    }

    function appSubstitution(value) {
        var key = String(value || "").trim();
        var lower = key.toLowerCase();
        var substitutions = {
            "code-url-handler": "visual-studio-code",
            "code": "visual-studio-code",
            "vscode": "visual-studio-code",
            "codium": "vscodium",
            "firefox": "firefox",
            "navigator": "firefox",
            "obsidian": "obsidian",
            "md.obsidian": "obsidian",
            "org.telegram.desktop": "telegramdesktop",
            "telegram-desktop": "telegramdesktop",
            "org.gnome.nautilus": "nautilus",
            "org.kde.dolphin": "dolphin",
            "footclient": "foot",
            "pavucontrol-qt": "pavucontrol",
            "zen-beta": "zen",
            "zen-alpha": "zen",
            "zen-browser": "zen"
        };
        return substitutions[key] || substitutions[lower] || key;
    }

    function reverseDomainNameAppName(value) {
        var parts = String(value || "").split(".");
        return parts.length > 0 ? parts[parts.length - 1] : "";
    }

    function kebabNormalizedAppName(value) {
        return String(value || "").toLowerCase().replace(/\s+/g, "-").replace(/_/g, "-");
    }

    function desktopEntryByIdLike(value) {
        var raw = String(value || "").trim();
        if (!raw)
            return null;

        var substituted = appSubstitution(raw);
        var lower = substituted.toLowerCase();
        var reverse = reverseDomainNameAppName(substituted);
        var candidates = [
            raw,
            substituted,
            lower,
            reverse,
            reverse.toLowerCase(),
            kebabNormalizedAppName(substituted)
        ];

        for (var i = 0; i < candidates.length; i++) {
            var candidate = String(candidates[i] || "").trim();
            if (!candidate)
                continue;

            var ids = candidate.length >= 8 && candidate.lastIndexOf(".desktop") === candidate.length - 8
                    ? [candidate]
                    : [candidate, candidate + ".desktop"];
            for (var j = 0; j < ids.length; j++) {
                var entry = DesktopEntries.byId(ids[j]);
                if (entry)
                    return entry;
            }
        }

        var heuristic = DesktopEntries.heuristicLookup(substituted);
        if (heuristic)
            return heuristic;
        return DesktopEntries.heuristicLookup(raw);
    }

    function guessIconName(value) {
        var raw = String(value || "").trim();
        if (!raw)
            return "";

        var entry = desktopEntryByIdLike(raw);
        if (entry && entry.icon)
            return entry.icon;

        var substituted = appSubstitution(raw);
        if (iconExists(substituted))
            return substituted;

        var lower = substituted.toLowerCase();
        if (iconExists(lower))
            return lower;

        var reverse = reverseDomainNameAppName(substituted);
        if (iconExists(reverse))
            return reverse;
        if (iconExists(reverse.toLowerCase()))
            return reverse.toLowerCase();

        var kebab = kebabNormalizedAppName(substituted);
        if (iconExists(kebab))
            return kebab;

        return "";
    }

    function guessIconForWindow(window) {
        var fields = [window && window.appId, window && window.rawClass, window && window.initialClass];
        for (var i = 0; i < fields.length; i++) {
            var icon = guessIconName(fields[i]);
            if (icon)
                return icon;
        }
        return window && window.icon ? window.icon : "application-x-executable";
    }

    function desktopEntryForWindow(window) {
        var fields = [window && window.appId, window && window.rawClass, window && window.initialClass];
        for (var i = 0; i < fields.length; i++) {
            var entry = desktopEntryByIdLike(fields[i]);
            if (entry)
                return entry;
        }
        return null;
    }

    function appByDesktopEntry(entry) {
        if (!entry)
            return null;
        var entryKeys = [];
        addCanonicalAppToken(entryKeys, entry.id || "");
        addCanonicalAppToken(entryKeys, entry.icon || "");

        var bestApp = null;
        var bestRank = 0;
        var apps = Services.AppPanelService.apps || [];
        for (var i = 0; i < apps.length; i++) {
            var app = apps[i];
            var appId = String(app.desktopId || "");
            var rank = 0;
            if (appId && appId === String(entry.id || ""))
                rank = 120;
            else if (listsShareIdentity(appCanonicalKeys(app, ""), entryKeys))
                rank = 100;
            else
                continue;

            rank += appPreferenceBonus(app);
            if (rank > bestRank) {
                bestRank = rank;
                bestApp = app;
            }
        }
        return bestApp;
    }

    function fallbackAppFromDesktopEntry(entry, window) {
        if (!entry)
            return null;
        var id = String(entry.id || "").trim();
        if (!id)
            id = String(window && (window.appId || window.rawClass || window.initialClass) || "").trim();
        if (!id)
            return null;

        return {
            desktopId: id,
            name: entry.name || id,
            genericName: "",
            icon: entry.icon || guessIconForWindow(window),
            iconName: entry.icon || "",
            iconPath: "",
            command: "",
            executable: "",
            startupWmClass: "",
            noDisplay: false,
            terminal: false,
            matchKeys: windowTokens(window)
        };
    }

    function stringContainsAppKey(text, key) {
        if (!text || !key || key.length < 3)
            return false;
        return normalizeToken(text).indexOf(key) >= 0;
    }

    function windowTokens(window) {
        if (!window)
            return [];

        // Only stable window identity fields are used for app matching. Window
        // titles and initial titles are deliberately excluded: browser tabs or
        // document titles can contain words like "emacs" and must not turn the
        // browser into another application in AppDock.
        var fields = [window.appId, window.rawClass, window.initialClass];
        var result = [];
        for (var i = 0; i < fields.length; i++) {
            addWindowToken(result, fields[i]);
        }
        return result;
    }

    function addWindowToken(result, value) {
        var key = normalizeToken(value);
        if (key.length <= 0)
            return;

        var aliases = {
            "firefox": ["firefox", "mozillafirefox", "orgmozillafirefox", "mozilla"],
            "mozillafirefox": ["firefox", "mozillafirefox", "orgmozillafirefox"],
            "orgmozillafirefox": ["firefox", "mozillafirefox", "orgmozillafirefox"],
            "firefoxdeveloperedition": ["firefoxdeveloperedition", "firefoxdeveloper", "firefox"],
            "obsidian": ["obsidian", "mdobsidian"],
            "mdobsidian": ["obsidian", "mdobsidian"],
            "code": ["code", "vscode", "visualstudiocode"],
            "visualstudiocode": ["code", "vscode", "visualstudiocode"],
            "codium": ["codium", "vscodium"],
            "vscodium": ["codium", "vscodium"],
            "telegramdesktop": ["telegramdesktop", "orgtelegramdesktop"],
            "orgtelegramdesktop": ["telegramdesktop", "orgtelegramdesktop"],
            "nautilus": ["nautilus", "orggnomenautilus", "gnomenautilus"],
            "orggnomenautilus": ["nautilus", "orggnomenautilus", "gnomenautilus"],
            "dolphin": ["dolphin", "orgkdedolphin", "kdedolphin"],
            "orgkdedolphin": ["dolphin", "orgkdedolphin", "kdedolphin"],
            "chromium": ["chromium", "chromiumbrowser"],
            "googlechrome": ["googlechrome", "chrome"],
            "bravebrowser": ["brave", "bravebrowser"],
            "zen": ["zen", "zenbrowser", "zenalpha", "zenbeta"],
            "zenbrowser": ["zen", "zenbrowser", "zenalpha", "zenbeta"],
            "zenalpha": ["zen", "zenbrowser", "zenalpha"],
            "zenbeta": ["zen", "zenbrowser", "zenbeta"]
        };

        var candidates = [key].concat(aliases[key] || []);
        for (var i = 0; i < candidates.length; i++) {
            var token = normalizeToken(candidates[i]);
            if (token.length > 0 && result.indexOf(token) < 0)
                result.push(token);
        }
    }

    function canonicalRuntimeFields(window) {
        var fields = [window && window.appId, window && window.rawClass, window && window.initialClass];
        var result = [];
        for (var i = 0; i < fields.length; i++)
            addCanonicalAppToken(result, fields[i]);
        return result;
    }

    function appExactFieldScore(window, app) {
        if (!window || !app)
            return 0;

        var runtime = canonicalRuntimeFields(window);
        if (runtime.length <= 0)
            return 0;

        var best = 0;
        var exactFields = [
            { value: app.desktopId || "", score: 190 },
            { value: app.sourceDesktopId || "", score: 190 },
            { value: app.startupWmClass || "", score: 180 },
            { value: app.executable || "", score: 150 },
            { value: app.iconName || "", score: 118 }
        ];

        for (var i = 0; i < exactFields.length; i++) {
            var keys = [];
            addCanonicalAppToken(keys, exactFields[i].value);
            for (var k = 0; k < keys.length; k++) {
                if (runtime.indexOf(keys[k]) >= 0)
                    best = Math.max(best, exactFields[i].score);
            }
        }

        return best;
    }

    function appEntryScore(app, entry) {
        if (!app || !entry)
            return 0;

        var entryId = String(entry.id || "");
        var appId = String(app.desktopId || "");
        if (entryId && appId && entryId === appId)
            return 170;

        var entryKeys = [];
        addCanonicalAppToken(entryKeys, entry.id || "");
        addCanonicalAppToken(entryKeys, entry.icon || "");
        if (listsShareIdentity(appCanonicalKeys(app, ""), entryKeys))
            return 115;

        return 0;
    }

    function appTokenScore(window, app, tokens) {
        if (!window || !app)
            return 0;

        var keys = app.matchKeys || [];
        var best = 0;

        for (var i = 0; i < tokens.length; i++) {
            for (var j = 0; j < keys.length; j++) {
                var key = String(keys[j] || "");
                if (!key)
                    continue;
                if (tokens[i] === key) {
                    best = Math.max(best, 100);
                } else if (key.length >= 5 && tokens[i].length >= 5 && (tokens[i].indexOf(key) >= 0 || key.indexOf(tokens[i]) >= 0)) {
                    // Permit useful long-form matches such as org.mozilla.firefox
                    // -> firefox, but reject short ambiguous keys such as obs ->
                    // obsidian. Short substrings caused Obsidian to be shown as OBS.
                    best = Math.max(best, 72);
                }
            }
        }

        var executable = normalizeToken(app.executable || "");
        if (executable) {
            for (var t = 0; t < tokens.length; t++) {
                if (tokens[t] === executable) {
                    best = Math.max(best, 92);
                } else if (executable.length >= 5 && tokens[t].length >= 5 && (tokens[t].indexOf(executable) >= 0 || executable.indexOf(tokens[t]) >= 0)) {
                    best = Math.max(best, 70);
                }
            }
        }

        return best;
    }

    function appMatchScore(window, app, tokens, entry) {
        return Math.max(
            appExactFieldScore(window, app),
            appEntryScore(app, entry),
            appTokenScore(window, app, tokens)
        );
    }

    function appTieBreakScore(app) {
        if (!app)
            return 0;

        // Preferences are deliberately only a tie-breaker. The app identity must
        // come from stable runtime fields first; otherwise unpinning an open app
        // can switch its title/icon to a neighbouring .desktop entry.
        return appPreferenceBonus(app) - (app.noDisplay ? 24 : 0);
    }

    function betterAppCandidate(score, tie, bestScore, bestTie) {
        if (score > bestScore)
            return true;
        if (score < bestScore)
            return false;
        return tie > bestTie;
    }

    function findAppForWindow(window) {
        var bestApp = null;
        var bestScore = 0;
        var bestTie = -999999;
        var apps = Services.AppPanelService.apps || [];
        var tokens = windowTokens(window);
        var entry = desktopEntryForWindow(window);
        var runtimeKey = runtimeAppKeyForWindow(window);
        var pinnedApp = pinnedAppForRuntimeKey(runtimeKey);
        if (pinnedApp)
            return pinnedApp;

        for (var i = 0; i < apps.length; i++) {
            var app = apps[i];
            var score = appMatchScore(window, app, tokens, entry);
            if (score < 70)
                continue;

            var tie = appTieBreakScore(app);
            if (betterAppCandidate(score, tie, bestScore, bestTie)) {
                bestScore = score;
                bestTie = tie;
                bestApp = app;
            }
        }

        if (bestApp)
            return bestApp;

        var entryApp = appByDesktopEntry(entry);
        return entryApp || fallbackAppFromDesktopEntry(entry, window);
    }

    function windowAddressKey(window) {
        var address = String(window && window.address || "").replace(/^0x/, "");
        return address.length > 0 ? address : normalizeToken(window && (window.appId || window.rawClass || window.title) || "window");
    }

}
