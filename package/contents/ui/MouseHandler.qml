/*
    SPDX-FileCopyrightText: 2025-2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-FileCopyrightText: 2023-2024 Marco Martin <notmart@gmail.com>
    SPDX-FileCopyrightText: 2024 Māris Nartišs <maris.kde@gmail.com>
    SPDX-FileCopyrightText: 2024 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2022-2023 Alexandra <alexankitty@gmail.com>
    SPDX-FileCopyrightText: 2023 Fushan Wen <qydwhotmail@gmail.com>
    SPDX-FileCopyrightText: 2012-2016 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.plasma.plasmoid
import org.kde.taskmanager as TaskManager

import "code/tools.js" as TaskTools

DropArea {
    id: dropArea
    signal urlsDropped(var urls)

    property var target
    property var hoveredItem
    readonly property var config: Plasmoid.configuration

    required property var tasks
    required property var tasksModel
    required property var proxyModel

    //ignore anything that is neither internal to TaskManager or a URL list
    onEntered: event => {
        if (event.formats.indexOf("text/x-plasmoidservicename") >= 0) {
            event.accepted = false;
        }
        target.animating = false;
        dropArea.tasks.dragEndedOutsidePanel = false;
    }

    // The task list item under a point in this DropArea's coordinates. The list sits inside
    // a container that is offset when the tasks are centered, so map before childAt().
    function itemAt(x: real, y: real): var {
        const pos = dropArea.mapToItem(dropArea.target, x, y);
        return dropArea.target.childAt(pos.x, pos.y);
    }

    onPositionChanged: event => {
        // Still over the panel; see onExited
        dropArea.tasks.dragEndedOutsidePanel = false;

        const above = dropArea.itemAt(event.x, event.y);

        if (!above) {
            hoveredItem = null;
            activationTimer.stop();

            return;
        }

        if (above.model && config.sortingStrategy <= 1) {
            const dragSource = dropArea.tasks.dragSource;
            if (dragSource && dragSource.model) {
                const tasks = dropArea.tasks;
                const dropIndicator = tasks.dropIndicator;
                
                // Work in the indicator's coordinates (the applet root). Tasks there run
                // top-to-bottom when vertical (reverse mode rotates the whole applet, and each
                // task again about its own center, so the item's local axes can't be used), and
                // left-to-right horizontally unless the layout is mirrored (RTL / reverse mode).
                const pos = tasks.mapFromItem(dropArea, event.x, event.y);
                const rect = tasks.mapFromItem(above, 0, 0, above.width, above.height);

                let dropIndex;
                if (tasks.vertical) {
                    const upperHalf = pos.y < rect.y + rect.height / 2;
                    dropIndex = upperHalf ? above.index : above.index + 1;
                    dropIndicator.x = rect.x;
                    dropIndicator.y = upperHalf ? rect.y : rect.y + rect.height;
                } else {
                    const leftHalf = pos.x < rect.x + rect.width / 2;
                    const mirrored = tasks.shouldBeMirrored(dropArea.config.reverseMode, Qt.locale().textDirection, false);
                    dropIndex = leftHalf !== mirrored ? above.index : above.index + 1;
                    dropIndicator.x = leftHalf ? rect.x : rect.x + rect.width;
                    dropIndicator.y = rect.y;
                }
                
                const allowed = dropArea.canMoveTo(dragSource.index, dropIndex);
                tasks.dropIndex = allowed ? dropIndex : -1;
                dropIndicator.visible = allowed;
                return; // Don't process normal hover when dragging
            }
        }

        if (!dropArea.tasks.dragSource && hoveredItem !== above) {
            if (hoveredItem && hoveredItem !== above && hoveredItem.toolTipOpen) {
                let oldHovered = hoveredItem;
                hideTooltipTimer.itemToHide = oldHovered;
                hideTooltipTimer.restart();
            }
            hoveredItem = above;
            activationTimer.restart();
        }
    }

    // Launchers are always kept separate, so TasksModel::move() keeps pinned apps (and their
    // windows) in front of everything else and refuses moves across that boundary; only show
    // the drop indicator where the drop will be accepted. (Ported from upstream d4f9a70.)
    function isPinnedAt(row: int): bool {
        const url = dropArea.proxyModel.data(dropArea.proxyModel.index(row, 0), TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon);
        return !!url && String(url) !== "" && dropArea.tasksModel.launcherPosition(url) !== -1;
    }

    function canMoveTo(from: int, dropIndex: int): bool {
        // Same adjustment as onDropped: the moved item leaves a gap
        const to = Math.max(0, Math.min(dropIndex > from ? dropIndex - 1 : dropIndex, dropArea.proxyModel.count - 1));
        return dropArea.isPinnedAt(from) === dropArea.isPinnedAt(to);
    }

    onExited: {
        // Tells Drag.onDragFinished (main.qml) that a task drag was released off the panel;
        // cleared again if the drag comes back (onEntered/onPositionChanged) or drops here
        if (dropArea.tasks.dragSource)
            dropArea.tasks.dragEndedOutsidePanel = true;
        dropArea.tasks.dropIndicator.visible = false;
        if (hoveredItem && hoveredItem.toolTipOpen) {
            hideTooltipTimer.itemToHide = hoveredItem;
            hideTooltipTimer.restart();
        }
        hoveredItem = null;
        activationTimer.stop();
    }

    Timer {
        id: hideTooltipTimer
        interval: 500
        repeat: false
        property var itemToHide: null
        onTriggered: {
            if (itemToHide && itemToHide.toolTipOpen && !dropArea.tasks.isTooltipHovered) {
                itemToHide.toolTipOpen = false;
            }
        }
    }

    onDropped: event => {
        dropArea.tasks.dragEndedOutsidePanel = false;
        // Handle internal task reordering
        if (event.formats.indexOf("application/x-orgkdeplasmataskmanager_taskbuttonitem") >= 0) {
            const dragSource = dropArea.tasks.dragSource;
            if (dragSource && dropArea.tasks.dropIndex !== -1) {
                let targetProxyIndex = dropArea.tasks.dropIndex;

                // If moving forward, adjust the target index to account for the gap left by the moved item.
                // This ensures that "dropping between items" lands the item in the expected spot.
                if (targetProxyIndex > dragSource.index) {
                    targetProxyIndex--;
                }

                // Safety clamp
                targetProxyIndex = Math.max(0, Math.min(targetProxyIndex, dropArea.proxyModel.count - 1));

                // Get the source indices from the proxy model
                const fromIdx = dropArea.proxyModel.mapToSource(dropArea.proxyModel.index(dragSource.index, 0));
                const toIdx = dropArea.proxyModel.mapToSource(dropArea.proxyModel.index(targetProxyIndex, 0));

                if (fromIdx.row !== -1 && toIdx.row !== -1 && fromIdx.row !== toIdx.row) {
                    dropArea.tasksModel.move(fromIdx.row, toIdx.row);
                }
            }
            dropArea.tasks.dropIndicator.visible = false;
            event.accepted = true;
            return;
        }

        // Reject plasmoid drops.
        if (event.formats.indexOf("text/x-plasmoidservicename") >= 0) {
            event.accepted = false;
            return;
        }

        if (event.hasUrls) {
            urlsDropped(event.urls);
            return;
        }
    }

    Connections {
        target: dropArea.tasks

        function onDragSourceChanged(): void {
            if (!dropArea.tasks.dragSource) {
                dropArea.tasks.dropIndicator.visible = false;
            }
        }
    }



    Timer {
        id: activationTimer

        interval: 250
        repeat: false

        onTriggered: {
            if (parent.hoveredItem.model.IsGroupParent) {
                parent.hoveredItem.tasksRoot.currentHoveredTask = parent.hoveredItem;
                parent.hoveredItem.toolTipOpen = true;
            } else if (!parent.hoveredItem.model.IsLauncher) {
                dropArea.tasks.tasksModel.requestActivate(parent.hoveredItem.modelIndex());
            }
        }
    }

    property real _rotationAccumulator: 0
    WheelHandler {
        id: wheelHandler

        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        property bool handleWheelEvents: true

        enabled: handleWheelEvents && (dropArea.config.wheelAction !== 0 || (dropArea.config.wheelCtrlActionEnabled && dropArea.config.wheelCtrlAction !== 0))

        onWheel: event => {
            dropArea._rotationAccumulator += (event.angleDelta.y / 8.0);
            let increment = 0;
            while (dropArea._rotationAccumulator >= 15) {
                dropArea._rotationAccumulator -= 15;
                increment++;
            }
            while (dropArea._rotationAccumulator <= -15) {
                dropArea._rotationAccumulator += 15;
                increment--;
            }

            if (increment === 0) return;

            const anchor = dropArea.itemAt(event.x, event.y);
            const isCtrl = (event.modifiers & Qt.ControlModifier) && dropArea.config.wheelCtrlActionEnabled;
            const action = isCtrl ? dropArea.config.wheelCtrlAction : dropArea.config.wheelAction;

            if (action >= 1 && action <= 4) { // Cycle Tasks
                const skipMinimized = (action === 2 || action === 4);
                const groupOnly = (action === 3 || action === 4);
                while (increment !== 0) {
                    TaskTools.activateNextPrevTask(anchor, increment < 0, skipMinimized, dropArea.tasks, groupOnly);
                    increment += (increment < 0) ? 1 : -1;
                }
            } else if (action === 5) { // Adjust Volume
                const isShift = (event.modifiers & Qt.ShiftModifier) && dropArea.config.wheelShiftSystemVolumeEnabled;
                if (anchor && anchor.adjustVolume) {
                    anchor.adjustVolume(increment, isShift);
                } else if (isShift && dropArea.tasks.adjustGlobalVolume) {
                    dropArea.tasks.adjustGlobalVolume(increment);
                }
            }
        }
    }
}
