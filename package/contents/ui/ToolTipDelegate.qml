/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-FileCopyrightText: 2025 SushiTrash <strash137@gmail.com>
    SPDX-FileCopyrightText: 2023-2024 Fushan Wen <qydwhotmail@gmail.com>
    SPDX-FileCopyrightText: 2024 Nicolas Fella <nicolas.fella@gmx.de>
    SPDX-FileCopyrightText: 2024 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2022-2023 Alexandra <alexankitty@gmail.com>
    SPDX-FileCopyrightText: 2023 Marco Martin <notmart@gmail.com>
    SPDX-FileCopyrightText: 2023 Nate Graham <nate@kde.org>
    SPDX-FileCopyrightText: 2017 Roman Gilg <subdiff@gmail.com>
    SPDX-FileCopyrightText: 2016 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2014 Martin Gräßlin <mgraesslin@kde.org>
    SPDX-FileCopyrightText: 2013 Sebastian Kügler <sebas@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQml.Models
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import org.kde.plasma.plasmoid
import org.kde.taskmanager as TaskManager

import "code/singletones"
import "code/tools.js" as TaskTools

Loader {
    id: toolTipDelegate

    required property Task parentTask
    required property var rootIndex
    property var tasksModel
    property var mpris2Model
    property var audioStreamManager: null
    
    // Pass Cache from Root (tasks) down to Instances
    property var thumbnailCache: tasks.thumbnailCache
    readonly property int thumbnailCacheTtlMs: tasks.thumbnailCacheTtlMs

    readonly property var config: Plasmoid.configuration

    readonly property bool isActive: (tasksModel && rootIndex.valid) ? tasksModel.data(rootIndex, TaskManager.AbstractTasksModel.IsActive) === true : false
    
    property int innerDragCount: 0
    
    function getHovered(target) {
        return (target && target.isHovered) || innerDragCount > 0;
    }
    readonly property bool containsMouse: getHovered(item)
    onContainsMouseChanged: {
        if (!containsMouse && parentTask && parentTask.tasksRoot) {
             parentTask.tasksRoot.cancelHighlightWindows();
        }
    }

    function generateSubText(): string {
        const subTextEntries = [];

        // Include Generic Name (Description) for Pinned Apps (no windows) or if relevant
        if (!isWin && genericName.length > 0 && genericName !== calculatedAppName) {
            subTextEntries.push(genericName);
        }

        return subTextEntries.concat(TaskTools.locationSubTextEntries(Wrappers.i18nc, toolTipDelegate.config, virtualDesktopInfo, activityInfo,
            virtualDesktops, isOnAllVirtualDesktops, activities)).join("\n");
    }

    property string appName
    property int pidParent

    // --- Which window of a group plays the media (computed once per group, not per tile) ---
    // Browsers play audio from one process for all windows and don't tag streams with a
    // window id; the only per-window hint is the title, which is the active tab's title.
    property int _titlesVersion: 0
    Connections {
        target: toolTipDelegate.tasksModel
        // Only the group bindings below read the counter, and they all depend on isGroup
        // too, so they re-evaluate on their own when isGroup turns true
        enabled: toolTipDelegate.isGroup
        function onDataChanged() { toolTipDelegate._titlesVersion++; }
        function onRowsInserted() { toolTipDelegate._titlesVersion++; }
        function onRowsRemoved() { toolTipDelegate._titlesVersion++; }
        function onModelReset() { toolTipDelegate._titlesVersion++; }
    }
    readonly property var groupPlayer: (toolTipDelegate.mpris2Model && toolTipDelegate.mpris2Model.playerForLauncherUrl)
        ? toolTipDelegate.mpris2Model.playerForLauncherUrl(toolTipDelegate.launcherUrl, toolTipDelegate.pidParent) : null


    // Prefix/suffix shared by the cleaned titles of this group's windows, so tiles can
    // emphasize what differs (see TaskTools.titleAffixes / styledTitle)
    readonly property var titleAffixes: {
        void toolTipDelegate._titlesVersion; // re-evaluate when titles or rows change
        const model = toolTipDelegate.tasksModel;
        const parentIndex = toolTipDelegate.rootIndex;
        if (!toolTipDelegate.isGroup || !model || !parentIndex || !parentIndex.valid)
            return {prefix: "", suffix: ""};
        const titles = [];
        for (let i = 0; i < model.rowCount(parentIndex); ++i) {
            const childTitle = TaskTools.cleanWindowTitle(model.data(model.index(i, 0, parentIndex), Qt.DisplayRole), toolTipDelegate.calculatedAppName);
            if (childTitle)
                titles.push(childTitle);
        }
        return TaskTools.titleAffixes(titles);
    }

    // Window ids (WinIdList[0]) in this group whose title shows the playing track
    readonly property var trackWindowIds: {
        void toolTipDelegate._titlesVersion; // re-evaluate when titles or rows change
        const track = toolTipDelegate.groupPlayer ? String(toolTipDelegate.groupPlayer.track || "").trim() : "";
        const model = toolTipDelegate.tasksModel;
        const parentIndex = toolTipDelegate.rootIndex;
        if (!toolTipDelegate.isGroup || !track || !model || !parentIndex || !parentIndex.valid)
            return [];
        const ids = [];
        for (let i = 0; i < model.rowCount(parentIndex); ++i) {
            const childIndex = model.index(i, 0, parentIndex);
            if (TaskTools.titleShowsTrack(model.data(childIndex, Qt.DisplayRole), track)) {
                const winIds = model.data(childIndex, TaskManager.AbstractTasksModel.WinIdList) || [];
                if (winIds.length > 0)
                    ids.push(winIds[0]);
            }
        }
        return ids;
    }
    property bool isGroup
    property var windows: []
    readonly property bool isWin: windows.length > 0
    property var icon
    property url launcherUrl
    property bool isLauncher
    property bool isMinimized
    property string display
    property string genericName
    property var virtualDesktops: []
    property bool isOnAllVirtualDesktops
    property list<string> activities: []
    property string appId: (tasksModel && rootIndex.valid) ? tasksModel.data(rootIndex, TaskManager.AbstractTasksModel.AppId) : ""
    property bool isPlayingAudio

    readonly property string calculatedAppName: TaskTools.appNameFromTitle(appName, display)

    readonly property bool isVerticalPanel: tasks.vertical
    // Thumbnail tiles are wider than text-only entries, and use a fixed 16:10 box instead of
    // the screen's aspect ratio (on ultrawide screens that made thumbnails very flat)
    readonly property int tooltipInstanceMaximumWidth: Kirigami.Units.gridUnit * (showThumbnails ? 15 : 14)
    readonly property real thumbnailAspectRatio: 16 / 10

    // Thumbnail tiles keep a fixed height and take the window's own shape for their width,
    // so tall windows (e.g. terminals) get narrow tiles with a bigger image
    readonly property int thumbnailBoxHeight: Math.round(Kirigami.Units.gridUnit * 15 / thumbnailAspectRatio)
    function tileWidthFor(geometry) {
        if (!geometry || !(geometry.width > 0) || !(geometry.height > 0))
            return toolTipDelegate.tooltipInstanceMaximumWidth;
        const width = thumbnailBoxHeight * geometry.width / geometry.height;
        return Math.round(Math.max(Kirigami.Units.gridUnit * 9,
            Math.min(width, Kirigami.Units.gridUnit * 15 * 1.5)));
    }
    // Sum of the tile widths of this group's windows (horizontal thumbnail list)
    readonly property real groupTilesWidth: {
        void toolTipDelegate._titlesVersion; // re-evaluate when windows change
        const model = toolTipDelegate.tasksModel;
        const parentIndex = toolTipDelegate.rootIndex;
        if (!toolTipDelegate.isGroup || !model || !parentIndex || !parentIndex.valid)
            return 0;
        const count = model.rowCount(parentIndex);
        let total = Math.max(0, count - 1) * Kirigami.Units.smallSpacing;
        for (let i = 0; i < count; ++i)
            total += tileWidthFor(model.data(model.index(i, 0, parentIndex), TaskManager.AbstractTasksModel.Geometry));
        return total;
    }

    property bool forceTextMode: false

    // Thumbnails are shown only when both the parent tooltip toggle and the thumbnail sub-option are enabled.
    readonly property bool showThumbnails: toolTipDelegate.config.enableToolTips && toolTipDelegate.config.showToolTips && !forceTextMode

    function getAppLayoutDirection(app) {
        return app.layoutDirection;
    }
    LayoutMirroring.enabled: getAppLayoutDirection(Qt.application) === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    // Do not load the tooltip at all when tooltips are disabled — prevents PipeWireThumbnail from
    // attempting to grab invisible window images and emitting "grabToImage: item's window is not visible".
    active: rootIndex !== undefined && toolTipDelegate.config.enableToolTips
    asynchronous: false

    sourceComponent: isGroup ? groupToolTip : singleTooltip

    Component {
        id: singleTooltip

        Item {
            id: singleRoot
            implicitWidth: singleLayout.implicitWidth
            implicitHeight: singleLayout.implicitHeight

            property bool isHovered: singleHover.hovered || singleDrop.containsDrag

            HoverHandler {
                id: singleHover
            }

            DropArea {
                id: singleDrop
                anchors.fill: parent
            }

            ColumnLayout {
                id: singleLayout
                spacing: Kirigami.Units.smallSpacing

                // App name (+ badge) on the left; for windows the desktop/activity info goes on the right
                RowLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: toolTipDelegate.tooltipInstanceMaximumWidth
                    Layout.leftMargin: Kirigami.Units.gridUnit / 2
                    Layout.rightMargin: Kirigami.Units.gridUnit / 2
                    visible: toolTipDelegate.calculatedAppName.length > 0 && (!toolTipDelegate.isWin || toolTipDelegate.showThumbnails)
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        id: nameLabel
                        level: 3
                        maximumLineCount: 1
                        textFormat: Text.PlainText
                        text: toolTipDelegate.calculatedAppName
                        elide: Text.ElideRight
                        Layout.maximumWidth: implicitWidth
                        Layout.fillWidth: true
                    }

                    // Badge sizes its own width from its height; keep it out of the layout's control
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: badge.width
                        implicitHeight: badge.height
                        visible: toolTipDelegate.config.showBadges && (toolTipDelegate.parentTask ? toolTipDelegate.parentTask.badgeVisible : false)

                        Badge {
                            id: badge
                            anchors.verticalCenter: parent.verticalCenter
                            appId: toolTipDelegate.appId
                            isUrgent: (toolTipDelegate.config.badgeHighlightNew && toolTipDelegate.parentTask) ? toolTipDelegate.parentTask.hasUnseenNotifications : false
                            height: Math.round(Kirigami.Units.gridUnit * 0.85)
                            isRound: false
                            fontPointSize: 8
                            maxNumber: 0
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    PlasmaComponents3.Label {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        Layout.maximumWidth: implicitWidth
                        horizontalAlignment: Text.AlignRight
                        text: toolTipDelegate.isWin ? toolTipDelegate.generateSubText().replace(/\n/g, " · ") : ""
                        elide: Text.ElideLeft
                        maximumLineCount: 1
                        visible: text.length > 0
                        opacity: 0.6
                        textFormat: Text.PlainText
                    }
                }

            PlasmaComponents3.Label {
                Layout.alignment: Qt.AlignLeft
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit / 2
                Layout.rightMargin: Kirigami.Units.gridUnit / 2
                Layout.maximumWidth: toolTipDelegate.tooltipInstanceMaximumWidth - Layout.leftMargin - Layout.rightMargin
                horizontalAlignment: Text.AlignLeft
                
                text: toolTipDelegate.generateSubText()
                wrapMode: Text.Wrap
                // Windows show this on the title row instead
                visible: text.length > 0 && !toolTipDelegate.isWin
                opacity: 0.6
                textFormat: Text.PlainText
            }

            Loader {
                id: singleInstanceLoader
                visible: toolTipDelegate.windows.length > 0
                
                property var currentWin: toolTipDelegate.isWin ? toolTipDelegate.windows[0] : undefined
                
                // Recreate the instance for the new window: unload now, load again on the next tick
                function reactivate(): void {
                    singleInstanceLoader.active = true;
                }

                onCurrentWinChanged: {
                    active = false;
                    Qt.callLater(singleInstanceLoader.reactivate);
                }
                
                sourceComponent: ToolTipInstance {    
                    index: 0 
                    // A single window keeps the fixed-size tile; only groups fit tiles to the windows
                    height: implicitHeight
                    submodelIndex: toolTipDelegate.rootIndex
                    explicitWinId: singleInstanceLoader.currentWin
                    
                    appPid: toolTipDelegate.pidParent
                    appId: (toolTipDelegate.parentTask && toolTipDelegate.parentTask.appId) ? toolTipDelegate.parentTask.appId : ""
                    display: toolTipDelegate.display
                    isMinimized: toolTipDelegate.isMinimized
                    isOnAllVirtualDesktops: toolTipDelegate.isOnAllVirtualDesktops
                    virtualDesktops: toolTipDelegate.virtualDesktops
                    activities: toolTipDelegate.activities
                    
                    isWindowActive: toolTipDelegate.isActive
                    
                    tasksModel: toolTipDelegate.tasksModel
                    toolTipDelegate: toolTipDelegate

                    mpris2Model: toolTipDelegate.mpris2Model
                    audioStreamManager: toolTipDelegate.audioStreamManager
                    
                    isPlayingAudio: toolTipDelegate.isPlayingAudio
                }
            }
        }
    }
}

    Component {
        id: groupToolTip

        Item {
            id: groupRoot
            implicitWidth: groupLayout.implicitWidth
            implicitHeight: groupLayout.implicitHeight

            property bool isHovered: groupHover.hovered || groupDrop.containsDrag

            HoverHandler {
                id: groupHover
            }

            DropArea {
                id: groupDrop
                anchors.fill: parent
            }

            ColumnLayout {
                id: groupLayout
                spacing: Kirigami.Units.smallSpacing
                
                readonly property int safeCount: toolTipDelegate.isWin ? toolTipDelegate.windows.length : 1
                readonly property int maxTooltipWidth: Screen.width - Kirigami.Units.gridUnit * 2
                readonly property int maxTooltipHeight: Screen.height - Kirigami.Units.gridUnit * 2
                readonly property real contentTargetWidth: {
                     // Use same logic as DelegateModel
                     if (toolTipDelegate.showThumbnails && !toolTipDelegate.isVerticalPanel && groupLayout.safeCount > 1 && toolTipDelegate.groupTilesWidth > 0)
                         return Math.ceil(toolTipDelegate.groupTilesWidth);
                     return Math.ceil(toolTipDelegate.tooltipInstanceMaximumWidth);
                }
                
                // App name (+ badge) on the left, desktop/activity info on the right
                RowLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: groupLayout.contentTargetWidth
                    Layout.leftMargin: Kirigami.Units.gridUnit / 2
                    Layout.rightMargin: Kirigami.Units.gridUnit / 2
                    visible: toolTipDelegate.calculatedAppName.length > 0 && toolTipDelegate.showThumbnails
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        id: groupNameLabel
                        level: 3
                        maximumLineCount: 1
                        textFormat: Text.PlainText
                        text: toolTipDelegate.calculatedAppName
                        elide: Text.ElideRight
                        Layout.maximumWidth: implicitWidth
                        Layout.fillWidth: true
                    }

                    // Badge sizes its own width from its height; keep it out of the layout's control
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: groupBadge.width
                        implicitHeight: groupBadge.height
                        visible: toolTipDelegate.config.showBadges && (toolTipDelegate.parentTask ? toolTipDelegate.parentTask.badgeVisible : false)

                        Badge {
                            id: groupBadge
                            anchors.verticalCenter: parent.verticalCenter
                            appId: toolTipDelegate.appId
                            isUrgent: (toolTipDelegate.config.badgeHighlightNew && toolTipDelegate.parentTask) ? toolTipDelegate.parentTask.hasUnseenNotifications : false
                            height: Math.round(Kirigami.Units.gridUnit * 0.85)
                            isRound: false
                            fontPointSize: 8
                            maxNumber: 0
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    PlasmaComponents3.Label {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        Layout.maximumWidth: implicitWidth
                        horizontalAlignment: Text.AlignRight
                        text: toolTipDelegate.generateSubText().replace(/\n/g, " · ")
                        elide: Text.ElideLeft
                        maximumLineCount: 1
                        visible: text.length > 0
                        opacity: 0.6
                        textFormat: Text.PlainText
                    }
                }

            PlasmaComponents3.ScrollView {
                id: scrollView
                // hovered is now handled by groupHover on the parent ColumnLayout
                
                // In text mode (no thumbnails), extend to tooltip edges
                Layout.leftMargin: toolTipDelegate.showThumbnails ? 0 : -6
                Layout.rightMargin: toolTipDelegate.showThumbnails ? 0 : -6
                Layout.bottomMargin: toolTipDelegate.showThumbnails ? 0 : -6
                
                // Remove default padding/background to prevent size mismatch
                padding: 0
                background: null
                
                // Hide scrollbars unless content strictly exceeds screen limits (prevents resize flickering)
                ScrollBar.horizontal.policy: (groupLayout.contentTargetWidth > groupLayout.maxTooltipWidth) ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: (groupToolTipListView.contentHeight > groupLayout.maxTooltipHeight) ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

                // Explicitly bind ListView as the scrollable content item for native wheel/touch handling
                contentItem: groupToolTipListView

                // Enable clipping to ensure scrollbars render correctly within bounds
                clip: true
                
                // Match content size strictly, but cap at screen limits
                Layout.preferredWidth: Math.min(groupLayout.contentTargetWidth, groupLayout.maxTooltipWidth)
                Layout.preferredHeight: Math.min(Math.max(groupToolTipListView.contentHeight, toolTipDelegate.showThumbnails ? delegateModel.estimatedHeight : 0), groupLayout.maxTooltipHeight)
                Layout.fillWidth: false 
                
                implicitHeight: Math.min(Math.max(groupToolTipListView.contentHeight, toolTipDelegate.showThumbnails ? delegateModel.estimatedHeight : 0), groupLayout.maxTooltipHeight)
                implicitWidth: Math.min(groupToolTipListView.width, groupLayout.maxTooltipWidth)

                ListView {
                    id: groupToolTipListView

                    // Content Width Logic
                    width: groupLayout.contentTargetWidth
                    // Height is managed by ScrollView (fills viewport)
     
                    model: delegateModel
                    
                    // FORCE VERTICAL LIST if thumbnails are disabled
                    orientation: (!toolTipDelegate.showThumbnails || toolTipDelegate.isVerticalPanel) ?
                        ListView.Vertical : ListView.Horizontal
                        
                    reuseItems: true
                    spacing: Kirigami.Units.smallSpacing
                    
                    clip: false
                }

                DelegateModel {
                    id: delegateModel

                    readonly property int safeCount: toolTipDelegate.isWin ? toolTipDelegate.windows.length : count

                    
                    // If thumbnails disabled -> height is 0
                    readonly property int instanceThumbHeight: toolTipDelegate.showThumbnails ? 
                        Math.round(toolTipDelegate.tooltipInstanceMaximumWidth / toolTipDelegate.thumbnailAspectRatio) : 0
                    
                    // Tallest delegate seen so far: a tile is the thumbnail plus its header and
                    // margins, so the thumbnail height alone would cut the bottom off
                    property real delegateHeight: 0

                    // Fallback to 2 grid units for Text Mode items
                    readonly property real singleItemHeight: Math.max(delegateHeight,
                        instanceThumbHeight > 0 ? instanceThumbHeight : Kirigami.Units.gridUnit * 2)


                    
                    readonly property real estimatedHeight: {
                        const count = (!toolTipDelegate.showThumbnails || toolTipDelegate.isVerticalPanel) ? safeCount : 1;
                        return count * singleItemHeight + Math.max(0, count - 1) * Kirigami.Units.smallSpacing;
                    }

                    model: toolTipDelegate.tasksModel
                    rootIndex: toolTipDelegate.rootIndex
                    onRootIndexChanged: {
                        delegateHeight = 0;
                        groupToolTipListView.positionViewAtBeginning();
                    }

                    // Optional "most recently used first" order. Only the display order of the
                    // items group changes; each delegate's index stays its source row, so
                    // submodelIndex and window actions still target the right window.
                    // The order is set when the list is (re)populated and then kept while the
                    // tooltip is open, so tiles never move under the cursor.
                    readonly property bool recentFirst: !!toolTipDelegate.config.tooltipRecentFirst
                    property bool _sorting: false
                    function sortRecentFirst() {
                        if (!recentFirst || _sorting)
                            return;
                        _sorting = true;
                        // Read every activation time once, then selection-sort with moves
                        const keys = [];
                        for (let i = 0; i < items.count; ++i) {
                            const value = items.get(i).model.LastActivated;
                            keys.push(value ? new Date(value).getTime() || 0 : 0);
                        }
                        for (let target = 0; target < keys.length - 1; ++target) {
                            let newest = target;
                            for (let i = target + 1; i < keys.length; ++i) {
                                if (keys[i] > keys[newest])
                                    newest = i;
                            }
                            if (newest !== target) {
                                items.move(newest, target, 1);
                                keys.splice(target, 0, keys.splice(newest, 1)[0]);
                            }
                        }
                        _sorting = false;
                        groupToolTipListView.positionViewAtBeginning();
                    }
                    // Windows added or removed (also the initial population); ignores our own moves
                    items.onChanged: if (!_sorting) Qt.callLater(sortRecentFirst)
                    onRecentFirstChanged: Qt.callLater(sortRecentFirst)

                    delegate: ToolTipInstance {
                        required property var model

                        // Fit tiles to the windows' shapes only when there are several windows
                        tileWidth: toolTipDelegate.showThumbnails && !toolTipDelegate.isVerticalPanel && delegateModel.count > 1
                            ? toolTipDelegate.tileWidthFor(model.Geometry) : toolTipDelegate.tooltipInstanceMaximumWidth
                        width: tileWidth
                        height: implicitHeight
                        onImplicitHeightChanged: delegateModel.delegateHeight = Math.max(delegateModel.delegateHeight, implicitHeight)
                        Component.onCompleted: delegateModel.delegateHeight = Math.max(delegateModel.delegateHeight, implicitHeight)
                        
                        index: index 
                        
                        // FIX: Get Window ID from current task model
                        explicitWinId: (model.WinIdList !== undefined && model.WinIdList.length > 0) ? model.WinIdList[0] : undefined

                        display: model.display !== undefined ? model.display : ""
                        appPid: model.AppPid !== undefined ? model.AppPid : 0
                        appId: model.AppId !== undefined ? model.AppId : ""
                        isMinimized: model.IsMinimized !== undefined ? model.IsMinimized : false
                        isDemandingAttention: model.IsDemandingAttention === true
                        isOnAllVirtualDesktops: model.IsOnAllVirtualDesktops !== undefined ? model.IsOnAllVirtualDesktops : false
                        virtualDesktops: model.VirtualDesktops !== undefined ? model.VirtualDesktops : []
                        activities: model.Activities !== undefined ? model.Activities : []
                        
                        isPlayingAudio: model.IsPlayingAudio !== undefined ? model.IsPlayingAudio : false
                        isWindowActive: model.IsActive !== undefined ? model.IsActive : false

                        submodelIndex: toolTipDelegate.tasksModel.makeModelIndex(toolTipDelegate.rootIndex.row, index)
                        tasksModel: toolTipDelegate.tasksModel
                        toolTipDelegate: toolTipDelegate

                        mpris2Model: toolTipDelegate.mpris2Model
                        audioStreamManager: toolTipDelegate.audioStreamManager
                    }
                }
            }
        }
    }
}
}
