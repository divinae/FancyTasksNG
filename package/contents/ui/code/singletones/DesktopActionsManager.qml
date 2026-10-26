/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma Singleton
import QtQuick
import org.kde.plasma.workspace.dbus as DBus
import org.kde.plasma.plasma5support as Plasma5Support

/**
 * DesktopActionsManager — provides desktop file jump list actions
 * and recent documents via a Python helper over DBus.
 */
Item {
    id: root

    property var cache: ({})
    // key -> Date.now() of the last fetch; entries younger than cacheFreshMs are not refetched
    property var cacheStamps: ({})
    readonly property int cacheFreshMs: 15000
    readonly property int cacheMaxEntries: 64

    // Last error line printed by the Python helper if it failed to start
    // (typically a missing python3-dbus / PyGObject module); empty while it works.
    property string helperError: ""

    // Bus name of the helper; also the name of its main interface
    readonly property string _service: "io.github.daydve.fancytasksng.DesktopActions"

    function _shellQuote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'";
    }

    Plasma5Support.DataSource {
        id: dbusDaemonStarter
        engine: "executable"
        connectedSources: []
        Component.onCompleted: {
            // Start the DBus daemon ONCE; a second instance exits cleanly if one already runs
            let scriptPath = Qt.resolvedUrl("../desktop_actions.py").toString().replace(/^file:\/\//, "");
            connectSource("python3 " + root._shellQuote(decodeURIComponent(scriptPath)));
        }
        // Only delivered when the helper exits; a running helper never reports here
        onNewData: (sourceName, data) => {
            const exitCode = data["exit code"];
            // Being stopped together with Plasma also gives a non-zero exit code, but no stderr
            if (exitCode && String(data.stderr || "").trim()) {
                const lines = String(data.stderr || "").trim().split("\n");
                root.helperError = lines[lines.length - 1] || ("exit code " + exitCode);
                console.warn("FancyTasksNG: desktop actions helper failed:", data.stderr);
            }
            disconnectSource(sourceName);
        }
    }

    // Calls a helper method and passes its reply (or the D-Bus error text) to callback as a string.
    function _call(iface, member, args, signature, callback) {
        const pendingReply = DBus.SessionBus.asyncCall({
            "service": root._service,
            "path": "/DesktopActions",
            "iface": iface,
            "member": member,
            "arguments": args,
            "signature": signature
        });
        pendingReply.finished.connect(() => {
            const value = pendingReply.value;
            if (callback) callback(value !== undefined && value !== null ? String(value) : "");
            pendingReply.destroy();
        });
    }

    // True if a reply string came from the helper rather than from D-Bus failing to reach it
    function isHelperReply(reply) {
        return reply.startsWith("{") || reply === "OK" || reply.startsWith("OK:") || reply.startsWith("ERROR:");
    }

    // Single source of truth for the cache key: query/prefetch/_doQuery must
    // agree on it, or a prefetched entry silently misses when re-queried.
    function _buildKey(launcherUrl, appPid, showHistory, limit) {
        appPid = parseInt(appPid || 0);
        showHistory = !!showHistory;
        limit = parseInt(limit || 10);
        return String(launcherUrl) + "|" + appPid + "|" + showHistory + "|" + limit;
    }

    // Shared gate for "should browser history be requested": history only
    // makes sense for an app with a valid running-process id.
    function shouldShowHistory(appPid, enabled) {
        return !!enabled && parseInt(appPid || 0) > 0;
    }

    function query(launcherUrl, appPid, showHistory, limit, callback) {
        const key = _buildKey(launcherUrl, appPid, showHistory, limit);

        // Return cached data immediately for instant UI, and refresh it in the
        // background only when it is older than cacheFreshMs
        if (key in cache && callback) {
            callback(cache[key]);
            if (Date.now() - (cacheStamps[key] || 0) > cacheFreshMs)
                _doQuery(String(launcherUrl), appPid, showHistory, limit, null);
            return;
        }

        _doQuery(String(launcherUrl), appPid, showHistory, limit, callback);
    }

    function prefetch(launcherUrl, appPid, showHistory, limit) {
        if (!launcherUrl) return;
        const key = _buildKey(launcherUrl, appPid, showHistory, limit);
        // Only prefetch if NOT in cache to avoid spam
        if (!(key in cache)) {
            _doQuery(String(launcherUrl), appPid, showHistory, limit, null);
        }
    }

    function _doQuery(launcherUrl, appPid, showHistory, limit, callback) {
        const key = _buildKey(launcherUrl, appPid, showHistory, limit);
        _call(root._service, "Query",
              [String(launcherUrl || ""), !!showHistory, parseInt(limit || 10), parseInt(appPid || 0)], "(sbii)",
              reply => {
            const stdout = reply.trim();
            // Native DBus might return empty array (coerced to "") or empty string on errors (e.g. service starting up)
            if (!stdout) {
                if (callback) callback({jumpList: [], recentDocs: []});
            } else if (!stdout.startsWith("{")) {
                // Ignore expected startup race condition
                if (stdout.indexOf("was not provided by any .service files") === -1) {
                    console.warn("DesktopActionsManager D-Bus error:", stdout);
                }
                if (callback) callback({jumpList: [], recentDocs: []});
            } else {
                let result = null;
                try {
                    result = JSON.parse(stdout);
                    root._store(key, result);
                } catch (e) {
                    console.warn("DesktopActionsManager JSON parse error:", e, stdout);
                    result = {jumpList: [], recentDocs: []};
                }

                // Call callback outside the try-catch so UI errors aren't swallowed!
                if (callback) callback(result);
            }
        });
    }

    function _store(key, result) {
        // Keys include the app PID, so drop the oldest entries as apps come and go
        const keys = Object.keys(cache);
        if (!(key in cache) && keys.length >= cacheMaxEntries) {
            const oldest = keys.reduce((a, b) => (cacheStamps[a] || 0) <= (cacheStamps[b] || 0) ? a : b);
            delete cache[oldest];
            delete cacheStamps[oldest];
        }
        cache[key] = result;
        cacheStamps[key] = Date.now();
    }

    function invalidate(launcherUrl) {
        if (launcherUrl) {
            const pattern = String(launcherUrl) + "|";
            // Important: we need to clean BOTH the exact key and any variations 
            // (with symbols like |true/false|limit)
            for (let k in cache) {
                if (k === String(launcherUrl) || k.startsWith(pattern)) {
                    delete cache[k];
                    delete cacheStamps[k];
                }
            }
        } else {
            cache = {};
            cacheStamps = {};
        }
    }

    function clearRecentDocuments(launcherUrl) {
        _call(root._service, "ClearRecent", [String(launcherUrl || "")], "(s)", () => invalidate(launcherUrl));
    }

    function executeCommand(execCmd) {
        _call(root._service, "Execute", [String(execCmd || "")], "(s)", null);
    }

    function exportConfig(path, content, callback) {
        _call("io.github.daydve.fancytasksng.Config", "ExportConfig", [String(path || ""), String(content || "")], "(ss)", callback);
    }

    function importConfig(path, callback) {
        _call("io.github.daydve.fancytasksng.Config", "ImportConfig", [String(path || "")], "(s)", callback);
    }

    function openUrl(url, launcherUrl) {
        _call(root._service, "OpenUrl", [String(url || ""), String(launcherUrl || "")], "(ss)", null);
    }
}
