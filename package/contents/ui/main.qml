/*
    SPDX-FileCopyrightText: 2025-2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-FileCopyrightText: 2025 SushiTrash <namanrajhans@gmail.com>
    SPDX-FileCopyrightText: 2025 SushiTrash <strash137@gmail.com>
    SPDX-FileCopyrightText: 2023-2024 Fushan Wen <qydwhotmail@gmail.com>
    SPDX-FileCopyrightText: 2023-2024 Marco Martin <notmart@gmail.com>
    SPDX-FileCopyrightText: 2023-2024 Nate Graham <nate@kde.org>
    SPDX-FileCopyrightText: 2023-2024 Niccolò Venerandi <niccolo@venerandi.com>
    SPDX-FileCopyrightText: 2024 David Edmundson <kde@davidedmundson.co.uk>
    SPDX-FileCopyrightText: 2024 David Redondo <kde@david-redondo.de>
    SPDX-FileCopyrightText: 2024 Ismael Asensio <isma.af@gmail.com>
    SPDX-FileCopyrightText: 2024 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2022-2023 Alexandra <alexankitty@gmail.com>
    SPDX-FileCopyrightText: 2023 Bharadwaj Raju <bharadwaj.raju777@protonmail.com>
    SPDX-FileCopyrightText: 2023 Nicolas Fella <nicolas.fella@gmx.de>
    SPDX-FileCopyrightText: 2023 Noah Davis <noahadvs@gmail.com>
    SPDX-FileCopyrightText: 2023 Taro Tanaka <mkrmdk@gmail.com>
    SPDX-FileCopyrightText: 2012-2013 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.ksvg as KSvg
import org.kde.plasma.private.mpris as Mpris
import org.kde.kirigami as Kirigami

import org.kde.plasma.workspace.trianglemousefilter

import org.kde.taskmanager as TaskManager
import QtCore as QtCore
// import org.kde.plasma.private.taskmanager as TaskManagerApplet
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kitemmodels as KItemModels

import "code/layoutmetrics.js" as LayoutMetrics
import "code/tools.js" as TaskTools
import "code/FloatingLogic.js" as FloatingLogic
import "code/singletones"

PlasmoidItem {
    id: tasks

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground

    readonly property var config: Plasmoid.configuration
    readonly property int location: Plasmoid.location
    readonly property var containment: Plasmoid.containment

    rotation: tasks.config.reverseMode && tasks.vertical ? 180 : 0

    // Prevent shrinking to zero during startup before the tasks model is fully initialized.
    // Otherwise, in Wayland with "Fit Content" panel, the panel shrinks to zero size
    // and becomes invisible until edit mode is entered.
    readonly property bool shouldShrinkToZero: !tasks._initialStartup && !!tasks.effectiveTasksModel && tasks.effectiveTasksModel.count === 0
    readonly property int effectiveLocation: FloatingLogic.getEffectiveLocation(tasks.location, tasks.config, PlasmaCore.Types)

    readonly property bool vertical: {
        if (effectiveLocation === PlasmaCore.Types.LeftEdge || effectiveLocation === PlasmaCore.Types.RightEdge) {
            return true;
        }
        if (effectiveLocation === PlasmaCore.Types.TopEdge || effectiveLocation === PlasmaCore.Types.BottomEdge) {
            return false;
        }
        return Plasmoid.formFactor === PlasmaCore.Types.Vertical;
    }
    readonly property bool iconsOnly: tasks.config.iconOnly
    property bool showBadges: tasks.config.showBadges

    property alias globalVolumeOverlay: globalVolumeOverlayLoader
    property Item dropIndicator: dropIndicatorRect
    property int dropIndex: -1
    property Item dragSource: null
    property bool dragEndedOutsidePanel: false

    property bool _isApplyingConfig: false
    property bool _initialStartup: true
    property bool _isDestroying: false

    Timer {
        id: startupTimer
        interval: 1500
        repeat: false
        onTriggered: {
            tasks.applyModelConfiguration();
            // Only the manual modes keep a user-arranged order ("Do not sort" runs on
            // SortManual too in this fork)
            if (tasks.config.sortingStrategy <= 1)
                tasks.restoreTaskOrder();
            // Deferred: restoreTaskOrder()'s move() calls pass through several
            // chained proxy models, so their rowsMoved signals aren't
            // guaranteed to arrive in this same tick. Qt.callLater() only
            // runs once those are drained, so the Connections guard below
            // stays active until they have.
            Qt.callLater(() => { tasks._initialStartup = false; });
        }
    }

    // Snapshot of the visible task order, restored after a plasmashell
    // restart. TasksModel's own manual-sort logic has no memory of the
    // previous live arrangement (e.g. a dragged-away pinned button) - it
    // only rebuilds sort order from scratch. Saved on every real order
    // change, applied once the model has settled at startup. One category
    // per applet: the settings file is shared by the whole plasmashell, and
    // several instances (e.g. one per panel) would overwrite each other.
    QtCore.Settings {
        id: taskOrderSettings
        category: "TaskOrder-" + Plasmoid.id
        property string savedOrder: "[]"
    }

    Timer {
        id: taskOrderSaveTimer
        interval: 500
        repeat: false
        onTriggered: tasks.snapshotTaskOrder()
    }

    Connections {
        target: tasks.tasksModel
        // Ignored during the startup settling window: row churn while the
        // model is still populating isn't a real change, and saving it would
        // overwrite the snapshot restoreTaskOrder() is about to read.
        function onRowsInserted() { if (!tasks._initialStartup) taskOrderSaveTimer.restart(); }
        function onRowsRemoved() { if (!tasks._initialStartup) taskOrderSaveTimer.restart(); }
        function onRowsMoved() { if (!tasks._initialStartup) taskOrderSaveTimer.restart(); }
    }

    // Stable across a plasmashell restart, unlike WinIdList (only meaningful
    // within the same process on Wayland). Can't disambiguate multiple
    // windows of the same app - restoreTaskOrder() matches those in order as
    // a best-effort fallback.
    function taskOrderIdentifierAt(index) {
        const idx = tasks.tasksModel.index(index, 0);
        const isLauncher = tasks.tasksModel.data(idx, TaskManager.AbstractTasksModel.IsLauncher);
        const winIds = tasks.tasksModel.data(idx, TaskManager.AbstractTasksModel.WinIdList);
        if (isLauncher && (!winIds || winIds.length === 0)) {
            return "L:" + tasks.tasksModel.data(idx, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon);
        }
        return "A:" + tasks.tasksModel.data(idx, TaskManager.AbstractTasksModel.AppId);
    }

    function snapshotTaskOrder() {
        if (!tasks.tasksModel || tasks._isDestroying)
            return;
        const order = [];
        for (let i = 0; i < tasks.tasksModel.count; i++) {
            order.push(tasks.taskOrderIdentifierAt(i));
        }
        taskOrderSettings.savedOrder = JSON.stringify(order);
    }

    function restoreTaskOrder() {
        if (!tasks.tasksModel)
            return;

        let savedOrder;
        try {
            savedOrder = JSON.parse(taskOrderSettings.savedOrder);
        } catch (e) {
            return;
        }
        if (!Array.isArray(savedOrder) || savedOrder.length === 0)
            return;

        // Mirrors the model's order locally, updated after each move() so
        // later lookups search post-move positions.
        const current = [];
        for (let i = 0; i < tasks.tasksModel.count; i++) {
            current.push(tasks.taskOrderIdentifierAt(i));
        }

        for (let target = 0; target < savedOrder.length && target < current.length; target++) {
            const from = current.indexOf(savedOrder[target], target);
            if (from === -1 || from === target)
                continue;
            tasks.tasksModel.move(from, target);
            current.splice(target, 0, current.splice(from, 1)[0]);
        }
    }

    Connections {
        target: tasks.config
        function onShowBadgesChanged() {
            tasks.showBadges = tasks.config.showBadges;
        }

        function onShowOnlyCurrentDesktopChanged() {
            modelUpdateTimer.restart();
            tasks.filteredTasksModel.invalidateFilter();
        }
        function onShowOnlyCurrentScreenChanged() {
            modelUpdateTimer.restart();
            tasks.filteredTasksModel.invalidateFilter();
        }
        function onShowOnlyCurrentActivityChanged() {
            modelUpdateTimer.restart();
            tasks.filteredTasksModel.invalidateFilter();
        }
        function onReverseFiltersChanged() {
            modelUpdateTimer.restart();
            tasks.filteredTasksModel.invalidateFilter();
        }

        function onSortingStrategyChanged() {
            modelUpdateTimer.restart();
        }
        function onGroupingStrategyChanged() {
            modelUpdateTimer.restart();
        }

        function onMinimizedFilterChanged() {
            tasks.filteredTasksModel.invalidateFilter();
        }

        function onGroupPopupsChanged() {
            modelUpdateTimer.restart();
        }
        // hideActivatedLaunchers and the grouping threshold depend on icons-only mode
        function onIconOnlyChanged() {
            modelUpdateTimer.restart();
        }
        // Edited from the settings page; the context menu writes these through the model
        function onGroupingAppIdBlacklistChanged() {
            if (tasks.tasksModel && JSON.stringify(tasks.tasksModel.groupingAppIdBlacklist) !== JSON.stringify(tasks.config.groupingAppIdBlacklist))
                tasks.tasksModel.groupingAppIdBlacklist = tasks.config.groupingAppIdBlacklist;
        }
        function onGroupingLauncherUrlBlacklistChanged() {
            if (tasks.tasksModel && JSON.stringify(tasks.tasksModel.groupingLauncherUrlBlacklist) !== JSON.stringify(tasks.config.groupingLauncherUrlBlacklist))
                tasks.tasksModel.groupingLauncherUrlBlacklist = tasks.config.groupingLauncherUrlBlacklist;
        }

        function onLaunchersChanged(): void {
            if (tasks.tasksModel && !tasks._isInternalLauncherUpdate) {
                tasks.tasksModel.launcherList = tasks.config.launchers;
                tasks.tasksModel.syncLaunchers();
            }
        }
    }

    property Task toolTipOpenedByClick
    property Task toolTipAreaItem

    property Task currentHoveredTask: null
    property Task instantHoveredTask: null
    property int instantHoveredIndex: instantHoveredTask ? instantHoveredTask.index : -1
    property real instantHoveredFraction: 0.5
    property bool isTooltipHovered: false

    // Keeps the tooltip anchored while it closes
    property Item lastTooltipParent: null

    function hideTooltipImmediately() {
        tasks.currentHoveredTask = null;
        tasks.toolTipOpenedByClick = null;
    }

    // Key: WinId, Value: { result: ItemGrabResult, stamp: ms }
    // Capped at THUMBNAIL_CACHE_MAX entries; entries older than THUMBNAIL_CACHE_TTL_MS are treated as stale.
    property var thumbnailCache: ({})
    readonly property int thumbnailCacheMax: 48
    readonly property int thumbnailCacheTtlMs: 120000

    function cacheThumbnail(winId, result) {
        const now = Date.now();
        // Build a fresh object rather than mutating in place: reassigning the
        // property (not just its contents) is what makes the change propagate
        // through the tasks.thumbnailCache -> toolTipDelegate.thumbnailCache
        // binding chain, since QML skips a changed signal when the rebound
        // value is reference-equal to the previous one.
        const next = {};
        let count = 0;
        let oldestKey = null, oldestStamp = Infinity;
        for (const k of Object.keys(thumbnailCache)) {
            const entry = thumbnailCache[k];
            if (now - entry.stamp > thumbnailCacheTtlMs) continue; // evict stale
            next[k] = entry;
            count++;
            if (entry.stamp < oldestStamp) {
                oldestStamp = entry.stamp;
                oldestKey = k;
            }
        }
        if (count >= thumbnailCacheMax && oldestKey !== null) {
            delete next[oldestKey]; // enforce cap by dropping the oldest survivor
        }
        next[winId] = { result: result, stamp: now };
        thumbnailCache = next;
    }

    onCurrentHoveredTaskChanged: {
        if (currentHoveredTask) {
            lastTooltipParent = currentHoveredTask.tooltipAnchor;
        }
    }

    Timer {
        id: tooltipCloseTimer
        interval: 500
        running: !tasks.isTooltipHovered && tasks.currentHoveredTask !== null && !tasks.currentHoveredTask.containsMouse && tasks.currentHoveredTask !== mouseHandler.hoveredItem
        onTriggered: {
            if (!tasks.isTooltipHovered && (tasks.currentHoveredTask && !tasks.currentHoveredTask.containsMouse && tasks.currentHoveredTask !== mouseHandler.hoveredItem)) {
                tasks.currentHoveredTask = null;
            }
        }
    }

    readonly property Component contextMenuComponent: Qt.createComponent("ContextMenu.qml")
    readonly property Component audioStreamManagerComponent: Qt.createComponent("AudioStreamManager.qml")


    property alias taskList: taskListView
    property alias effectWatcher: windowViewEffectWatcher
    property alias audioStreamManager: audioStreamManagerLoader
    property alias mpris2Source: mpris2SourceModel
    property alias dragHelper: dragHelper
    property alias taskFrame: taskFrame
    property alias filteredTasksModel: internalFilteredTasksModel
    property alias busyIndicator: busyIndicator
    property alias virtualDesktopInfo: virtualDesktopInfo
    property alias mouseHandler: mouseHandler
    FancyTasksExplosion {
        id: explosionManager
    }

    preferredRepresentation: fullRepresentation
    Plasmoid.constraintHints: Plasmoid.CanFillArea

    Layout.fillWidth: vertical ? true : tasks.config.fill
    Layout.fillHeight: !vertical ? true : tasks.config.fill
    Layout.minimumWidth: {
        if (shouldShrinkToZero)
            return Kirigami.Units.gridUnit;
        return vertical ? 0 : LayoutMetrics.preferredMinWidth();
    }
    Layout.minimumHeight: {
        if (shouldShrinkToZero)
            return Kirigami.Units.gridUnit;
        return !vertical ? 0 : LayoutMetrics.preferredMinHeight();
    }
    Layout.preferredWidth: {
        if (shouldShrinkToZero)
            return 0.01;
        if (tasks.location === PlasmaCore.Types.Floating)
            return -1; // Let Plasma manage and persist manual resizes
        if (vertical)
            return Kirigami.Units.gridUnit * (iconsOnly ? 2.5 : 10);
        return taskListView.Layout.maximumWidth;
    }
    Layout.preferredHeight: {
        if (shouldShrinkToZero)
            return 0.01;
        if (tasks.location === PlasmaCore.Types.Floating)
            return -1; // Let Plasma manage and persist manual resizes
        if (vertical)
            return taskListView.Layout.maximumHeight;
        return Kirigami.Units.gridUnit * 2;
    }

    signal requestLayout
    signal windowsHovered(var winIds, bool hovered)
    function activateWindowView(winIds) {
        if (!windowViewEffectWatcher.registered)
            return;
        cancelHighlightWindows();
        return DBus.SessionBus.asyncCall({
            service: "org.kde.KWin.Effect.WindowView1",
            path: "/org/kde/KWin/Effect/WindowView1",
            iface: "org.kde.KWin.Effect.WindowView1",
            member: "activate",
            arguments: [winIds.map(s => String(s))],
            signature: "(as)"
        });
    }

    onWindowsHovered: (winIds, hovered) => {
        if (!tasks.config.highlightWindows || !tasks.config.enableToolTips)
            return;
        DBus.SessionBus.asyncCall({
            service: "org.kde.KWin.HighlightWindow",
            path: "/org/kde/KWin/HighlightWindow",
            iface: "org.kde.KWin.HighlightWindow",
            member: "highlightWindows",
            arguments: [hovered ? winIds : []],
            signature: "(as)"
        });
    }

    function cancelHighlightWindows(): DBus.DBusPendingReply {
        return DBus.SessionBus.asyncCall({
            service: "org.kde.KWin.HighlightWindow",
            path: "/org/kde/KWin/HighlightWindow",
            iface: "org.kde.KWin.HighlightWindow",
            member: "highlightWindows",
            arguments: [[]],
            signature: "(as)"
        });
    }

    onDragSourceChanged: {
        if (tasks.dragSource === null && tasks.tasksModel)
            tasks.tasksModel.syncLaunchers();
    }

    property bool _isInternalLauncherUpdate: false
    property bool _isPublishingGeometries: false

    function publishIconGeometries(taskItems: var): void {
        if (_isPublishingGeometries || tasks._isDestroying)
            return;
        if (TaskTools.taskManagerInstanceCount >= 2)
            return;

        _isPublishingGeometries = true;
        try {
            for (let i = 0; i < taskItems.length; ++i) {
                const task = taskItems[i];
                if (task.getGlobalRect && task.model && !task.model.IsLauncher && !task.model.IsStartup && tasks.tasksModel) {
                    const idx = task.modelIndex();
                    if (idx && idx.valid) {
                        tasks.tasksModel.requestPublishDelegateGeometry(idx, task.getGlobalRect(), task);
                    }
                }
            }
        } finally {
            _isPublishingGeometries = false;
        }
    }

    readonly property TaskManager.TasksModel tasksModel: internalTasksModel
    TaskManager.TasksModel {
        id: internalTasksModel

        virtualDesktop: virtualDesktopInfo.currentDesktop
        screenGeometry: tasks.containment ? tasks.containment.screenGeometry : Qt.rect(0, 0, 0, 0)
        activity: activityInfo.currentActivity

        onLauncherListChanged: {
            if (!tasks._isApplyingConfig) {
                tasks._isInternalLauncherUpdate = true;
                tasks.config.launchers = launcherList;
                // Defer reset to ensure the config change signal has finished propagating
                Qt.callLater(() => {
                    if (tasks)
                        tasks._isInternalLauncherUpdate = false;
                });
            }
        }
        onGroupingAppIdBlacklistChanged: {
            if (!tasks._isApplyingConfig) {
                tasks.config.groupingAppIdBlacklist = groupingAppIdBlacklist;
            }
        }
        onGroupingLauncherUrlBlacklistChanged: {
            if (!tasks._isApplyingConfig) {
                tasks.config.groupingLauncherUrlBlacklist = groupingLauncherUrlBlacklist;
            }
        }

        Component.onCompleted: {
            // Runs before launcherList below: setting launcherList inserts
            // launcher rows through the same incremental path a running
            // window uses, which only queues a row for launcher-position
            // matching if separateLaunchers is already at its final value.
            tasks.applyModelConfiguration();
            launcherList = tasks.config.launchers;
            groupingAppIdBlacklist = tasks.config.groupingAppIdBlacklist;
            groupingLauncherUrlBlacklist = tasks.config.groupingLauncherUrlBlacklist;
            startupTimer.start();
        }
    }

    KItemModels.KSortFilterProxyModel {
        id: internalFilteredTasksModel
        sourceModel: internalTasksModel
        filterRowCallback: (source_row, source_parent) => {
            const idx = internalTasksModel.index(source_row, 0, source_parent);

            // Minimized Filter
            const isMinimized = internalTasksModel.data(idx, TaskManager.AbstractTasksModel.IsMinimized) === true;
            if (tasks.config.minimizedFilter === 1) { // Only Minimized
                if (!isMinimized)
                    return false;
            } else if (tasks.config.minimizedFilter === 2) { // Only Not Minimized
                if (isMinimized)
                    return false;
            }

            // Reverse Filters (hide instead of show)
            if (tasks.config.reverseFilters) {
                // Screen Filter: hide tasks on the current screen
                if (tasks.config.showOnlyCurrentScreen) {
                    const taskScreen = internalTasksModel.data(idx, TaskManager.AbstractTasksModel.ScreenGeometry);
                    const currentScreen = tasks.tasksModel.screenGeometry;
                    if (taskScreen && taskScreen.x === currentScreen.x && taskScreen.y === currentScreen.y && taskScreen.width === currentScreen.width && taskScreen.height === currentScreen.height) {
                        return false;
                    }
                }

                // Desktop Filter: hide tasks on the current virtual desktop
                if (tasks.config.showOnlyCurrentDesktop) {
                    const isOnAllDesktops = internalTasksModel.data(idx, TaskManager.AbstractTasksModel.IsOnAllVirtualDesktops) === true;
                    const demandsAttention = internalTasksModel.data(idx, TaskManager.AbstractTasksModel.IsDemandingAttention) === true;
                    if (!isOnAllDesktops && !demandsAttention) {
                        const virtualDesktops = internalTasksModel.data(idx, TaskManager.AbstractTasksModel.VirtualDesktops);
                        const currentDesktop = tasks.tasksModel.virtualDesktop;
                        if (Array.isArray(virtualDesktops) && virtualDesktops.indexOf(currentDesktop) !== -1) {
                            return false;
                        }
                    }
                }

                // Activity Filter: hide tasks on the current activity
                if (tasks.config.showOnlyCurrentActivity) {
                    const demandsAttention = internalTasksModel.data(idx, TaskManager.AbstractTasksModel.IsDemandingAttention) === true;
                    if (!demandsAttention) {
                        const activities = internalTasksModel.data(idx, TaskManager.AbstractTasksModel.Activities);
                        const currentActivity = tasks.tasksModel.activity;
                        if (Array.isArray(activities) && activities.length > 0) {
                            const isOnAllActivities = activities.indexOf("00000000-0000-0000-0000-000000000000") !== -1;
                            if (!isOnAllActivities && activities.indexOf(currentActivity) !== -1) {
                                return false;
                            }
                        }
                    }
                }
            }

            return true;
        }
    }

    readonly property var effectiveTasksModel: (tasks.config.minimizedFilter === 0 && !tasks.config.reverseFilters) ? internalTasksModel : internalFilteredTasksModel

    Timer {
        id: modelUpdateTimer
        interval: 100
        repeat: false
        onTriggered: tasks.applyModelConfiguration()
    }

    function applyModelConfiguration() {
        if (!tasks.tasksModel)
            return;

        tasks._isApplyingConfig = true;

        tasks.tasksModel.filterByVirtualDesktop = tasks.config.showOnlyCurrentDesktop && !tasks.config.reverseFilters;
        tasks.tasksModel.filterByScreen = tasks.config.showOnlyCurrentScreen && !tasks.config.reverseFilters;
        tasks.tasksModel.filterByActivity = tasks.config.showOnlyCurrentActivity && !tasks.config.reverseFilters;
        // tasks.tasksModel.filterNotMinimized = tasks.config.showOnlyMinimized;
        // The above is now handled by filteredTasksModel proxy to prevent crashes.
        tasks.tasksModel.filterNotMinimized = false;

        // Set the launcher flags before sortMode: entering SortManual seeds the
        // sort map from them. separateLaunchers stays on (as upstream does) so
        // libtaskmanager re-sorts launcher-backed windows into their launcher
        // slot on every insert; with it off, a newly opened pinned app lands at
        // the end because its hidden launcher is not found as a sibling.
        const launchInPlace = (tasks.config.sortingStrategy === 1 || tasks.config.sortingStrategy === 0);
        tasks.tasksModel.launchInPlace = launchInPlace;
        tasks.tasksModel.hideActivatedLaunchers = tasks.iconsOnly || launchInPlace;
        tasks.tasksModel.separateLaunchers = true;
        tasks.tasksModel.sortMode = tasks.sortModeEnumValue(tasks.config.sortingStrategy);

        tasks.tasksModel.groupMode = tasks.groupModeEnumValue(tasks.config.groupingStrategy);
        tasks.tasksModel.groupInline = !tasks.config.groupPopups;
        // -1 groups always; otherwise windows of an app are only grouped once the bar can't fit them
        tasks.tasksModel.groupingWindowTasksThreshold = Qt.binding(() => (tasks.config.onlyGroupWhenFull && !tasks.iconsOnly)
            ? LayoutMetrics.optimumCapacity(tasks.width, tasks.height) + 1 : -1);

        internalFilteredTasksModel.invalidateFilter();

        tasks._isApplyingConfig = false;
    }

    function sortModeEnumValue(index) {
        switch (Number(index)) {
        // "Do not sort" runs on SortManual too: under SortDisabled, TasksModel orders
        // launchers by their row in TaskGroupingProxyModel, which re-appends a launcher at
        // its end when it is shown again after its window closes, so a pinned app jumped
        // to the end of the pinned group. SortManual uses the stable launcher-list order.
        // (Ported from upstream 5307a8c.)
        case 0:
            return TaskManager.TasksModel.SortManual;
        case 1:
            return TaskManager.TasksModel.SortManual;
        case 2:
            return TaskManager.TasksModel.SortAlpha;
        case 3:
            return TaskManager.TasksModel.SortVirtualDesktop;
        case 4:
            return TaskManager.TasksModel.SortActivity;
        case 5:
            return TaskManager.TasksModel.SortWindowPositionHorizontal;
        default:
            return TaskManager.TasksModel.SortDisabled;
        }
    }

    function groupModeEnumValue(index) {
        switch (Number(index)) {
        case 0:
            return TaskManager.TasksModel.GroupDisabled;
        case 1:
            return TaskManager.TasksModel.GroupApplications;
        default:
            return TaskManager.TasksModel.GroupApplications;
        }
    }

    DBus.DBusServiceWatcher {
        id: windowViewEffectWatcher
        busType: DBus.BusType.Session
        watchedService: "org.kde.KWin.Effect.WindowView1"
    }

    readonly property Component taskInitComponent: Component {
        Item {}
    }

    Connections {
        target: Plasmoid
        function onLocationChanged(): void {
            if (TaskTools.taskManagerInstanceCount >= 2)
                return;
            iconGeometryTimer.start();
        }
    }

    Connections {
        target: tasks.containment
        function onScreenGeometryChanged(): void {
            iconGeometryTimer.start();
        }
    }

    Mpris.Mpris2Model {
        id: mpris2SourceModel
    }

    // All MPRIS players, to match a player to the window that actually shows its track.
    // A browser exposes its media through plasma-browser-integration under the browser's own
    // desktop entry, so a web app window (e.g. a Spotify app run by the same browser) would
    // otherwise never get it, while the main browser window always would.
    property var mprisPlayers: []
    Instantiator {
        model: mpris2SourceModel
        delegate: QtObject {
            required property var container
        }
        onObjectAdded: (index, object) => tasks.mprisPlayers = tasks.mprisPlayers.concat([object.container])
        onObjectRemoved: (index, object) => tasks.mprisPlayers = tasks.mprisPlayers.filter(p => p !== object.container)
    }

    // {launcherUrl: {track, pid}} for open web app windows that a *playing* browser player is
    // playing from (matched by site in the helper). Refreshed when a tooltip opens and every
    // 5 s while something plays; used for tooltips and for the panel's audio streams.
    property var webAppTracks: ({})
    function setWebAppTracks(map) {
        // Assign only on change, so dependants don't re-evaluate on every refresh
        if (JSON.stringify(map) !== JSON.stringify(tasks.webAppTracks))
            tasks.webAppTracks = map;
    }
    function refreshWebAppTracks() {
        const urls = [];
        const model = tasks.tasksModel;
        const walk = parent => {
            for (let row = 0; row < model.rowCount(parent); ++row) {
                const idx = model.index(row, 0, parent);
                if (model.data(idx, TaskManager.AbstractTasksModel.IsGroupParent))
                    walk(idx);
                const url = String(model.data(idx, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon) || "");
                if (url && urls.indexOf(url) === -1)
                    urls.push(url);
            }
        };
        walk(model.index(-1, -1));
        DesktopActionsManager.webAppTracks(urls, map => tasks.setWebAppTracks(map));
        DesktopActionsManager.webAppLaunchers(urls, list => {
            if (JSON.stringify(list) !== JSON.stringify(tasks.webAppLaunchers))
                tasks.webAppLaunchers = list;
        });
    }

    // Launcher URLs of open windows that are browser web apps (--app=URL). They share their
    // browser's process, so its audio would match them by PID too; they only get it while
    // their own player is playing (see audioStreamsFor).
    property var webAppLaunchers: []
    Connections {
        target: tasks.tasksModel
        function onRowsInserted() { webAppRefreshTimer.restart(); }
    }
    Timer {
        id: webAppRefreshTimer
        interval: 1000
        onTriggered: tasks.refreshWebAppTracks()
    }

    // Keep the web app claims fresh while any player exists, so the panel's audio icons
    // (not only tooltips) follow the media to the right window
    readonly property bool anyPlayerPlaying: tasks.mprisPlayers.some(player => player && player.playbackStatus === Mpris.PlaybackStatus.Playing)
    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: tasks.anyPlayerPlaying
        onTriggered: tasks.refreshWebAppTracks()
        // Playback stopped: one last refresh drops claims of players that no longer play
        onRunningChanged: if (!running) tasks.refreshWebAppTracks()
    }
    onMprisPlayersChanged: if (tasks.mprisPlayers.length === 0) tasks.setWebAppTracks({})

    // The player a web app claim refers to: by the process owning its D-Bus name
    // (instancePid; kdePid is the browser process, shared by its other players), which is
    // stable across track changes, else by track title
    function playerForClaim(claim) {
        if (!claim)
            return null;
        for (const player of tasks.mprisPlayers) {
            if (player && claim.pid && player.instancePid === claim.pid)
                return player;
        }
        return tasks.playerWithTrack(claim.track);
    }

    // Stream app names and MPRIS identities differ between browsers ("Google Chrome" vs
    // "Chrome", "Mozilla Firefox" vs "Firefox"): compare loosely
    function sameBrowserName(a, b) {
        a = String(a || "").toLowerCase();
        b = String(b || "").toLowerCase();
        return a.length > 0 && b.length > 0 && (a.includes(b) || b.includes(a));
    }

    // Audio streams that belong to a window. Browsers play from a helper process tagged only
    // with the browser's name, so name matching would give a web app's audio (e.g. a Spotify
    // app) to the main browser window. While a web app's player is playing, the web app gets
    // its browser's streams and the browser's other windows don't. Limitation: a browser
    // doesn't say which tab a stream comes from, so while its web app plays, sound from a
    // regular tab is attributed to the web app too.
    function audioStreamsFor(pa, appId, pid, appName, launcherUrl) {
        const own = pa.streamsForApp(appId, pid, appName);
        const claims = tasks.webAppTracks || {};
        const myClaim = claims[launcherUrl];
        if (!myClaim && tasks.webAppLaunchers.indexOf(launcherUrl) !== -1)
            return []; // a web app whose player isn't playing: the browser's audio isn't its
        if (myClaim) {
            if (own.length > 0)
                return own;
            const player = tasks.playerForClaim(myClaim);
            return player ? pa.findStreams(stream => tasks.sameBrowserName(stream.appName, player.identity)) : [];
        }
        const claimedBrowsers = Object.keys(claims).map(url => tasks.playerForClaim(claims[url]))
            .filter(player => !!player).map(player => player.identity);
        return own.filter(stream => !claimedBrowsers.some(name => tasks.sameBrowserName(stream.appName, name)));
    }

    // The player playing a given track, or null
    function playerWithTrack(track) {
        for (const player of tasks.mprisPlayers) {
            if (player && track && player.track === track)
                return player;
        }
        return null;
    }

    // A player whose current track this window title shows, or null
    function playerShownInTitle(windowTitle) {
        for (const player of tasks.mprisPlayers) {
            if (player && TaskTools.titleShowsTrack(windowTitle, player.track))
                return player;
        }
        return null;
    }

    // Whether some window other than excludeWinId shows the track in its title
    function trackShownInOtherWindow(track, excludeWinId) {
        if (!String(track || "").trim())
            return false;
        const model = tasks.tasksModel;
        const walk = parent => {
            for (let row = 0; row < model.rowCount(parent); ++row) {
                const idx = model.index(row, 0, parent);
                if (model.data(idx, TaskManager.AbstractTasksModel.IsGroupParent)) {
                    if (walk(idx))
                        return true;
                    continue;
                }
                const winIds = model.data(idx, TaskManager.AbstractTasksModel.WinIdList) || [];
                if (winIds.length > 0 && winIds.indexOf(excludeWinId) === -1
                        && TaskTools.titleShowsTrack(model.data(idx, Qt.DisplayRole), track))
                    return true;
            }
            return false;
        };
        return walk(model.index(-1, -1));
    }

    function handleItemRemoval(taskItem) {
        if (!taskItem || !taskItem.model)
            return;

        // Do not spawn ghosts for Launchers or Startups, as their removal is typically
        // a model transition (e.g. Launcher -> Startup -> Window), not a real closure.
        if (taskItem.model.IsLauncher || taskItem.model.IsStartup)
            return;

        if (tasks.config.smokeExplosionOnClose && tasks.config.iconOnly === 1) {
            if (taskItem.wasMiddleClicked) {
                explosionManager.spawn(tasks, taskItem, true);
            }
        }
    }

    function addLauncher(url: url): void {
        if (Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable && tasks.tasksModel)
            tasks.tasksModel.requestAddLauncher(url);
    }
    function removeLauncher(url: url): void {
        if (Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable && tasks.tasksModel)
            tasks.tasksModel.requestRemoveLauncher(url);
    }
    // Called by plasmashell for the Meta+1..9 shortcuts (org.kde.plasma.multitasking)
    function activateTaskAtIndex(index: var): void {
        if (typeof index !== "number")
            return;
        const task = internalTaskRepeater.itemAt(index) as Task;
        if (task)
            TaskTools.activateTask(task.modelIndex(), task.model, null, task, Plasmoid, tasks, windowViewEffectWatcher.registered);
    }
    // Called by plasmashell for the Meta+Shift+1..9 shortcuts
    function newInstanceForTaskAtIndex(index: var): void {
        if (typeof index !== "number")
            return;
        const task = internalTaskRepeater.itemAt(index) as Task;
        if (task)
            TaskTools.activateTask(task.modelIndex(), task.model, Qt.ShiftModifier, task, Plasmoid, tasks, windowViewEffectWatcher.registered);
    }
    function adjustGlobalVolume(increment: int) {
        const audioManager = audioStreamManagerLoader.item;
        const pSink = "preferredSink";
        const pAdj = "adjustObjectVolume";
        if (!audioManager || !audioManager[pSink])
            return;

        const lastResult = audioManager[pAdj](audioManager[pSink], increment);
        if (lastResult && globalVolumeOverlayLoader.item) {
            const pVol = "volume";
            const pMute = "muted";
            const pShow = "show";
            globalVolumeOverlayLoader.item[pVol] = lastResult.volume;
            globalVolumeOverlayLoader.item[pMute] = lastResult.muted;
            globalVolumeOverlayLoader.item[pShow]();
        }
    }
    function createContextMenu(rootTask, modelIndex, args = {}) {
        const initialArgs = Object.assign(args, {
            visualParent: rootTask,
            modelIndex,
            mpris2Source: mpris2SourceModel,
            tasksModel: tasks.tasksModel,
            virtualDesktopInfo,
            activityInfo,
            tasksRoot: tasks
        });
        return tasks.contextMenuComponent.createObject(rootTask, initialArgs);
    }
    function shouldBeMirrored(reverseMode, layoutDirection, vertical): bool {
        if (vertical)
            return layoutDirection === Qt.RightToLeft;
        if (layoutDirection === Qt.LeftToRight)
            return reverseMode;
        return !reverseMode;
    }

    Item {
        anchors.fill: parent

        HoverHandler {
            id: rootHoverHandler
        }

        TaskManager.VirtualDesktopInfo {
            id: virtualDesktopInfo
        }
        TaskManager.ActivityInfo {
            id: activityInfo
            readonly property string nullUuid: "00000000-0000-0000-0000-000000000000"
        }

        Loader {
            id: audioStreamManagerLoader
            sourceComponent: tasks.audioStreamManagerComponent
            active: tasks.audioStreamManagerComponent.status === Component.Ready
        }

        Loader {
            id: globalVolumeOverlayLoader
            anchors.fill: parent
            source: "TaskVolumeOverlay.qml"
        }

        Timer {
            id: iconGeometryTimer
            interval: 500
            repeat: false
            onTriggered: tasks.publishIconGeometries(taskListView.children)
        }

        Binding {
            target: Plasmoid
            property: "status"
            value: (tasks.tasksModel && (tasks.tasksModel.anyTaskDemandsAttention || BadgeManager.anyUrgent) && tasks.config.unhideOnAttention && !tasks.config.attentionPeek ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.PassiveStatus)
            restoreMode: Binding.RestoreBinding
        }

        Component {
            id: busyIndicator
            PlasmaComponents3.BusyIndicator {
                anchors.fill: parent
                running: true
            }
        }

        Item {
            id: dragHelper
            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction

            // Holds the launcher URL while waiting for the unpin animation to finish.
            property string pendingUnpinUrl: ""

            // Delays the actual model removal so the explosion animation has time to play.
            Timer {
                id: unpinDelayTimer
                interval: 300
                repeat: false
                onTriggered: {
                    if (dragHelper.pendingUnpinUrl !== "") {
                        tasks.removeLauncher(dragHelper.pendingUnpinUrl);
                        dragHelper.pendingUnpinUrl = "";
                    }
                }
            }

            Drag.onDragFinished: dropAction => {
                // If a pure launcher (no running windows) is dragged outside the panel,
                // treat it as an "unpin" gesture.
                // We check both Qt.IgnoreAction (nothing accepted the drop) AND
                // dragEndedOutsidePanel (set by position check in Task.qml's DragHandler),
                // because Plasma desktop or other shell components may accept the drag
                // and return a non-IgnoreAction even when the user clearly dropped outside.
                const source = tasks.dragSource;
                let pModel = "model";
                let pWinIdList = "winIdList";
                if (tasks.config.unpinByDrag && (dropAction === Qt.IgnoreAction || tasks.dragEndedOutsidePanel) && source && source[pModel] && source[pModel].IsLauncher && source[pWinIdList].length === 0) {
                    if (tasks.config.unpinByDragExplosion && tasks.config.iconOnly === 1) {
                        explosionManager.spawn(tasks, source, true);
                        // Delay removal so the explosion animation plays before the item disappears.
                        dragHelper.pendingUnpinUrl = source[pModel].LauncherUrlWithoutIcon.toString();
                        unpinDelayTimer.start();
                    } else {
                        tasks.removeLauncher(source[pModel].LauncherUrlWithoutIcon);
                    }
                }
                tasks.dragEndedOutsidePanel = false;
                tasks.dragSource = null;
                tasks.dropIndicator.visible = false;
            }
        }

        Rectangle {
            id: dropIndicatorRect
            color: Kirigami.Theme.highlightColor
            width: tasks.vertical ? parent.width : 2
            height: tasks.vertical ? 2 : parent.height
            visible: false
            z: 999

            Behavior on x {
                enabled: tasks.dropIndicator.visible
                NumberAnimation {
                    duration: Kirigami.Units.shortDuration
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on y {
                enabled: tasks.dropIndicator.visible
                NumberAnimation {
                    duration: Kirigami.Units.shortDuration
                    easing.type: Easing.OutQuad
                }
            }
        }

        KSvg.FrameSvgItem {
            id: taskFrame
            visible: false
            imagePath: "widgets/tasks"
            prefix: TaskTools.taskPrefix("normal", tasks.effectiveLocation)
        }

        MouseHandler {
            id: mouseHandler
            anchors.fill: parent
            target: taskList
            tasks: tasks
            tasksModel: tasks.tasksModel
            proxyModel: internalFilteredTasksModel
            onUrlsDropped: urls => {
                const isApp = url => {
                    let s = url.toString();
                    return s.endsWith(".desktop") || s.startsWith("applications:") || s.startsWith("application://");
                };
                const createLaunchers = urls.every(isApp);
                if (createLaunchers) {
                    urls.forEach(item => tasks.addLauncher(item));
                    return;
                }
                if (!hoveredItem)
                    return;
                const task = hoveredItem as Task;
                if (tasks.tasksModel)
                    tasks.tasksModel.requestOpenUrls(task.modelIndex(), urls);
            }
        }

        // Cursor-following glow drawn on the panel underneath the task buttons.
        // Sized to the task list area so it never bleeds onto other applets.
        Shape {
            id: hoverGlow
            anchors.fill: tmf
            visible: tasks.config.cursorGlow
            preferredRendererType: Shape.CurveRenderer

            // Kept after the cursor leaves so the glow fades out in place
            property real cursorX: 0
            property real cursorY: 0
            property color glowColor: Kirigami.Theme.highlightColor

            function tint(alpha: real): color {
                return Qt.rgba(glowColor.r, glowColor.g, glowColor.b, alpha);
            }

            opacity: rootHoverHandler.hovered && tasks.instantHoveredTask !== null ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutQuad
                }
            }
            Behavior on glowColor {
                ColorAnimation {
                    duration: Kirigami.Units.longDuration
                }
            }

            Connections {
                target: rootHoverHandler
                function onPointChanged(): void {
                    if (!rootHoverHandler.hovered) {
                        return;
                    }
                    hoverGlow.cursorX = rootHoverHandler.point.position.x - hoverGlow.x;
                    hoverGlow.cursorY = rootHoverHandler.point.position.y - hoverGlow.y;
                    if (tasks.instantHoveredTask) {
                        hoverGlow.glowColor = tasks.instantHoveredTask.frame.indicatorColor;
                    }
                }
            }

            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: hoverGlow.cursorX
                    centerY: hoverGlow.cursorY
                    centerRadius: (tasks.vertical ? hoverGlow.width : hoverGlow.height) * 1.4
                    focalX: centerX
                    focalY: centerY
                    GradientStop { position: 0.0; color: hoverGlow.tint(0.35) }
                    GradientStop { position: 0.35; color: hoverGlow.tint(0.14) }
                    GradientStop { position: 0.7; color: hoverGlow.tint(0.04) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                PathRectangle {
                    width: hoverGlow.width
                    height: hoverGlow.height
                }
            }
        }

        TriangleMouseFilter {
            id: tmf
            filterTimeOut: 300
            active: tasks.currentHoveredTask !== null
            blockFirstEnter: false
            edge: {
                switch (tasks.effectiveLocation) {
                case PlasmaCore.Types.BottomEdge:
                    return Qt.TopEdge;
                case PlasmaCore.Types.TopEdge:
                    return Qt.BottomEdge;
                case PlasmaCore.Types.LeftEdge:
                    return Qt.RightEdge;
                case PlasmaCore.Types.RightEdge:
                    return Qt.LeftEdge;
                default:
                    return Qt.TopEdge;
                }
            }
            readonly property bool centerAlign: tasks.iconsOnly && tasks.config.fill && tasks.config.fillAlignment === 1
            LayoutMirroring.enabled: tasks.shouldBeMirrored(tasks.config.reverseMode, Qt.locale().textDirection, tasks.vertical)
            x: centerAlign && !tasks.vertical ? Math.round((parent.width - width) / 2) : 0
            y: centerAlign && tasks.vertical ? Math.round((parent.height - height) / 2) : 0
            height: taskListView.height
            width: taskListView.width

            TaskList {
                id: taskListView
                tasks: tasks
                tasksModel: tasks.effectiveTasksModel
                LayoutMirroring.enabled: tasks.shouldBeMirrored(tasks.config.reverseMode, Qt.locale().textDirection, tasks.vertical)
                anchors {
                    left: parent.left
                    top: parent.top
                }
                readonly property real widthOccupation: internalTaskRepeater.count / columns
                readonly property real heightOccupation: internalTaskRepeater.count / rows
                Layout.maximumWidth: {
                    if (widthOccupation <= 0)
                        return 0;
                    if (tasks.iconsOnly) {
                        return Math.round((internalTaskRepeater.count * LayoutMetrics.preferredMaxWidth()) / widthOccupation);
                    }
                    return Math.round(children.reduce((acc, child) => (child && child.visible && isFinite(child.Layout.maximumWidth)) ? acc + child.Layout.maximumWidth : acc, 0) / widthOccupation);
                }
                Layout.maximumHeight: {
                    if (heightOccupation <= 0)
                        return 0;
                    if (tasks.iconsOnly) {
                        return Math.round((internalTaskRepeater.count * LayoutMetrics.preferredMaxHeight()) / heightOccupation);
                    }
                    return Math.round(children.reduce((acc, child) => (child && child.visible && isFinite(child.Layout.maximumHeight)) ? acc + child.Layout.maximumHeight : acc, 0) / heightOccupation);
                }
                width: tasks.shouldShrinkToZero ? 0 : (tasks.vertical ? tasks.width * Math.min(1, widthOccupation) : Math.min(tasks.width, Layout.maximumWidth))
                height: tasks.shouldShrinkToZero ? 0 : (tasks.vertical ? Math.min(tasks.height, Layout.maximumHeight) : tasks.height * Math.min(1, heightOccupation))
                flow: tasks.vertical ? (tasks.config.forceStripes ? Grid.LeftToRight : Grid.TopToBottom) : (tasks.config.forceStripes ? Grid.TopToBottom : Grid.LeftToRight)
                onAnimatingChanged: if (!animating)
                    iconGeometryTimer.restart()

                Repeater {
                    id: internalTaskRepeater
                    model: tasks.effectiveTasksModel
                    delegate: Task {
                        tasksRoot: tasks
                    }
                }

                Connections {
                    target: tasks.effectiveTasksModel
                    function onRowsAboutToBeRemoved(parent, first, last) {
                        // Child rows of a group are not delegates of this repeater.
                        if (parent && parent.valid)
                            return;
                        for (let i = first; i <= last; ++i) {
                            tasks.handleItemRemoval(internalTaskRepeater.itemAt(i));
                        }
                    }
                }
            }
        }
    }

    // --- Attention peek (icon bouncing out of the screen edge for auto-hidden panels) ---
    // Panel visibility mode from plasmashellrc via the helper: 1 = auto-hide, 4 = dodge windows
    property int panelVisibility: -1
    readonly property bool panelAutoHides: panelVisibility === 1 || panelVisibility === 4
    Timer {
        interval: 10000
        repeat: true
        triggeredOnStart: true
        running: tasks.config.attentionPeek && !!Plasmoid.containment
        onTriggered: DesktopActionsManager.panelVisibility(Plasmoid.containment.id, value => tasks.panelVisibility = value)
    }

    readonly property bool attentionPeekWanted: tasks.config.attentionPeek && tasks.panelAutoHides
        && tasks.effectiveLocation !== PlasmaCore.Types.Floating
        && !!tasks.tasksModel && (tasks.tasksModel.anyTaskDemandsAttention || BadgeManager.anyUrgent)

    // Whether the auto-hidden panel is currently on screen: a shown panel renders the small
    // heartbeat below, a hidden one gets no frame callbacks from the compositor and stops.
    property bool panelOnScreen: true
    property double lastPanelFrame: 0
    property bool activeWindowFullScreen: false
    readonly property bool showAttentionPeek: attentionPeekWanted && !panelOnScreen && !activeWindowFullScreen

    Connections {
        target: tasks.attentionPeekWanted ? tasks.Window.window : null
        function onFrameSwapped() {
            tasks.lastPanelFrame = Date.now();
            tasks.panelOnScreen = true;
        }
    }

    // Heartbeat: a nearly invisible 1px change every 150 ms (~7 redraws/s, not every vsync)
    Rectangle {
        id: attentionHeartbeat
        width: 1
        height: 1
        color: "black"
        opacity: 0.002
        visible: tasks.attentionPeekWanted
    }
    Timer {
        interval: 150
        repeat: true
        running: tasks.attentionPeekWanted
        onTriggered: {
            attentionHeartbeat.opacity = attentionHeartbeat.opacity > 0.003 ? 0.002 : 0.004;
            // No frame for a while: the panel is hidden. 500 ms tolerates short render stalls.
            tasks.panelOnScreen = Date.now() - tasks.lastPanelFrame < 500;
            const active = tasks.tasksModel.activeTask;
            tasks.activeWindowFullScreen = !!active && active.valid
                && tasks.tasksModel.data(active, TaskManager.AbstractTasksModel.IsFullScreen) === true;
        }
        onRunningChanged: {
            if (running) {
                // Assume shown until proven hidden, so a visible panel never flashes the peek
                tasks.lastPanelFrame = Date.now();
                tasks.panelOnScreen = true;
            }
        }
    }

    Component.onCompleted: {
        TaskTools.taskManagerInstanceCount += 1;
        requestLayout.connect(iconGeometryTimer.restart);
    }
    Component.onDestruction: TaskTools.taskManagerInstanceCount -= 1

    PlasmaCore.Dialog {
        id: windowTooltipDialog

        location: tasks.effectiveLocation
        type: PlasmaCore.Dialog.Tooltip
        // Qt.ToolTip makes libplasma keep all frame borders (and rounded corners) on the panel side too
        flags: Qt.ToolTip | Qt.FramelessWindowHint
        hideOnWindowDeactivate: false

        readonly property bool shouldShow: tasks.config.enableToolTips && tasks.currentHoveredTask !== null && !tasks.currentHoveredTask.inPopup
        visible: shouldShow && tooltipContent.width > 0 && tooltipContent.height > 0
        visualParent: tasks.currentHoveredTask ? tasks.currentHoveredTask.tooltipAnchor : tasks.lastTooltipParent

        mainItem: Item {
            id: tooltipContent

            // Inner padding on top of the theme frame's margins, like Plasma's default tooltip,
            // so content (e.g. thumbnail tiles) doesn't run into the frame's rounded corners
            readonly property int padding: Kirigami.Units.smallSpacing

            // The Loader-based content drops to 0x0 for a moment while it switches between
            // tasks; keep the last real size so the dialog doesn't unmap and flicker
            property real lastWidth: 0
            property real lastHeight: 0
            readonly property real contentWidth: toolTipInstance.implicitWidth > 0 ? toolTipInstance.implicitWidth : lastWidth
            readonly property real contentHeight: toolTipInstance.implicitHeight > 0 ? toolTipInstance.implicitHeight : lastHeight
            Connections {
                target: toolTipInstance
                function onImplicitWidthChanged() {
                    if (toolTipInstance.implicitWidth > 0)
                        tooltipContent.lastWidth = toolTipInstance.implicitWidth;
                }
                function onImplicitHeightChanged() {
                    if (toolTipInstance.implicitHeight > 0)
                        tooltipContent.lastHeight = toolTipInstance.implicitHeight;
                }
            }

            width: contentWidth > 0 ? contentWidth + padding * 2 : 0
            height: contentHeight > 0 ? contentHeight + padding * 2 : 0

            ToolTipDelegate {
                id: toolTipInstance

                Kirigami.Theme.colorSet: Kirigami.Theme.Tooltip
                Kirigami.Theme.inherit: false

                x: tooltipContent.padding
                y: tooltipContent.padding
                width: tooltipContent.contentWidth
                height: tooltipContent.contentHeight

                onContainsMouseChanged: tasks.isTooltipHovered = containsMouse

                parentTask: tasks.currentHoveredTask
                tasksModel: tasks.tasksModel
                mpris2Model: mpris2Source
                audioStreamManager: tasks.audioStreamManager

                readonly property var taskModel: parentTask ? parentTask.model : null

                // parentTask.index is a row in the filtered proxy; map it to the source model,
                // otherwise lookups below read the wrong task whenever filters are active
                rootIndex: {
                    if (parentTask) {
                        const idx = parentTask.modelIndex();
                        if (idx !== undefined && idx !== null) return idx;
                    }
                    return internalTasksModel.makeModelIndex(parentTask ? parentTask.index : 0, -1);
                }
                appName: taskModel ? taskModel.AppName : ""
                pidParent: taskModel ? taskModel.AppPid : 0
                windows: taskModel ? taskModel.WinIdList : []
                isGroup: taskModel ? taskModel.IsGroupParent : false
                icon: taskModel ? taskModel.decoration : ""
                launcherUrl: taskModel ? taskModel.LauncherUrlWithoutIcon : ""
                isLauncher: taskModel ? taskModel.IsLauncher : false
                isMinimized: taskModel ? taskModel.IsMinimized : false
                display: taskModel ? taskModel.display : ""
                genericName: taskModel ? taskModel.GenericName : ""
                virtualDesktops: taskModel ? taskModel.VirtualDesktops : []
                isOnAllVirtualDesktops: taskModel ? taskModel.IsOnAllVirtualDesktops : false
                activities: taskModel ? taskModel.Activities : []

                isPlayingAudio: taskModel ? (taskModel.IsPlayingAudio === true) : false
                isMuted: taskModel ? (taskModel.IsMuted === true) : false

                forceTextMode: tasks.toolTipOpenedByClick !== null && tasks.config.groupedTaskVisualization !== 1
            }
        }
    }
}
