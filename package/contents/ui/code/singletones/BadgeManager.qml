/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma Singleton
import QtQuick
import org.kde.plasma.workspace.dbus as DBus
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.notificationmanager as NotificationManager

/**
 * BadgeManager: Unified aggregator for taskbar badges.
 * Intercepts Unity-style signals via a Python helper script.
 */
Item {
    id: root

    // Reactive store for unread counts and progress
    property var unityCounts: ({})
    property var unityProgress: ({})
    property var unityUrgent: ({})
    // True while any app has set the LauncherEntry "urgent" flag
    property bool anyUrgent: false
    property int countVersion: 0
    // Unread notification counts per desktop entry (e.g. "org.kde.dolphin"), like the
    // stock task manager's badges for apps that don't use the LauncherEntry API
    property var notificationCounts: ({})

    Component.onCompleted: bridgeStarter.start()

    // Background process to sniff D-Bus signals that QML might miss
    Plasma5Support.DataSource {
        id: bridgeStarter
        engine: "executable"
        connectedSources: []
        
        function start() {
            let scriptPath = decodeURIComponent(Qt.resolvedUrl("../unity_bridge.py").toString().replace(/^file:\/\//, ""));
            connectSource("python3 '" + scriptPath.replace(/'/g, "'\\''") + "'");
        }
        
        onNewData: (sourceName, data) => {
            // Being stopped together with Plasma also gives a non-zero exit code, but no stderr
            if (data["exit code"] && String(data.stderr || "").trim())
                console.warn("Taskline: badge bridge failed:", data.stderr);
            disconnectSource(sourceName);
        }
    }

    NotificationManager.Settings {
        id: notificationSettings
        live: true
    }

    NotificationManager.Notifications {
        id: notificationsModel
        showNotifications: true
        showJobs: false
        showExpired: true
        showDismissed: true
        groupMode: NotificationManager.Notifications.GroupDisabled

        onCountChanged: notificationCountTimer.restart()
        onDataChanged: notificationCountTimer.restart()
        onModelReset: notificationCountTimer.restart()
    }

    Connections {
        target: notificationSettings
        function onBadgesInTaskManagerChanged() {
            notificationCountTimer.restart();
        }
        function onBadgeBlacklistedApplicationsChanged() {
            notificationCountTimer.restart();
        }
    }

    // Coalesce bursts of model changes into one recount
    Timer {
        id: notificationCountTimer
        interval: 100
        onTriggered: root.recountNotifications()
    }

    function recountNotifications() {
        const counts = {};
        if (notificationSettings.badgesInTaskManager) {
            const blocked = notificationSettings.badgeBlacklistedApplications || [];
            for (let row = 0; row < notificationsModel.count; ++row) {
                const idx = notificationsModel.index(row, 0);
                if (notificationsModel.data(idx, NotificationManager.Notifications.ReadRole))
                    continue;
                const entry = String(notificationsModel.data(idx, NotificationManager.Notifications.DesktopEntryRole) || "");
                if (!entry || blocked.indexOf(entry) !== -1)
                    continue;
                counts[entry] = (counts[entry] || 0) + 1;
            }
        }
        if (JSON.stringify(counts) === JSON.stringify(root.notificationCounts))
            return;
        root.notificationCounts = counts;
        root.countVersion++;
    }

    // Listener for internal bridge signals
    DBus.SignalWatcher {
        id: bridgeWatcher
        service: "io.github.divinae.taskline.Bridge"
        path: "/Bridge"
        iface: "io.github.divinae.taskline.BadgeUpdate"
        
        function dbusUpdateSignal(appId, count, progress, urgent) {
            root.updateData(String(appId), count, progress, !!urgent);
        }
    }

    // appId without an "application://" prefix or ".desktop" suffix, and (unless
    // keepApplicationsPrefix) without an "applications:" prefix
    function _cleanId(appId, keepApplicationsPrefix) {
        let cleanId = String(appId);
        if (cleanId.startsWith("application://")) cleanId = cleanId.slice(14);
        if (cleanId.endsWith(".desktop")) cleanId = cleanId.slice(0, -8);
        if (!keepApplicationsPrefix && cleanId.startsWith("applications:")) cleanId = cleanId.slice(13);
        return cleanId;
    }

    // The keys an app's entries may be stored under: as given, cleaned, cleaned + ".desktop"
    function _lookupIds(appId) {
        const cleanId = _cleanId(appId, false);
        return [String(appId), cleanId, cleanId + ".desktop"];
    }

    // First value stored for appId under any of its keys, else fallback
    function _lookup(map, appId, fallback) {
        for (const id of _lookupIds(appId)) {
            if (map[id] !== undefined)
                return map[id];
        }
        return fallback;
    }

    // First truthy value stored for appId under any of its keys, else undefined
    function _lookupTruthy(map, appId) {
        const ids = _lookupIds(appId);
        return map[ids[0]] || map[ids[1]] || map[ids[2]];
    }

    /**
     * Returns the unread count for a given AppId.
     * Tries multiple name variations for maximum compatibility.
     */
    function getUnreadCount(appId) {
        if (!appId) return 0;
        // LauncherEntry counts win over notification counts, like the stock task manager
        return _lookupTruthy(unityCounts, appId) || notificationCounts[_cleanId(appId, false)] || 0;
    }

    /**
     * Returns the progress (-1.0 if not visible) for a given AppId.
     */
    function getProgress(appId) {
        if (!appId) return -1.0;
        return _lookup(unityProgress, appId, -1.0);
    }

    /**
     * Returns whether the app has set the LauncherEntry "urgent" flag.
     */
    function getUrgent(appId) {
        if (!appId) return false;
        return !!_lookupTruthy(unityUrgent, appId);
    }

    // Copy of map with value stored under keys, or null when map already holds exactly that.
    // A new object is needed for QML to notify the property change.
    function _withValue(map, keys, value) {
        if (keys.every(key => map[key] === value))
            return null;
        const result = Object.assign({}, map);
        for (const key of keys)
            result[key] = value;
        return result;
    }

    /**
     * Updates the count, progress and urgent flag for an application and triggers UI refresh.
     */
    function updateData(appId, count, progress, urgent) {
        const strId = String(appId);
        // The ids the lookups try (_lookupIds), plus the form with an "applications:" prefix
        const cleanId = _cleanId(strId, false);
        const prefixedId = _cleanId(strId, true);

        const keys = [strId, cleanId, cleanId + ".desktop"];
        if (prefixedId !== cleanId)
            keys.push(prefixedId);
        // Handle dot-notation names (e.g. io.github.name)
        if (cleanId.includes(".")) {
            const dots = cleanId.split(".");
            const baseName = dots[dots.length - 1];
            keys.push(baseName, baseName + ".desktop");
        }

        const newCounts = _withValue(unityCounts, keys, count);
        const newProgress = _withValue(unityProgress, keys, progress);
        const newUrgent = _withValue(unityUrgent, keys, urgent);
        if (!newCounts && !newProgress && !newUrgent)
            return;

        if (newCounts)
            root.unityCounts = newCounts;
        if (newProgress)
            root.unityProgress = newProgress;
        if (newUrgent) {
            root.unityUrgent = newUrgent;
            root.anyUrgent = Object.keys(newUrgent).some(key => newUrgent[key]);
        }
        root.countVersion++;
    }
}
