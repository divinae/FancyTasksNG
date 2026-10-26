/*
    SPDX-FileCopyrightText: 2025-2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-FileCopyrightText: 2025 SushiTrash <strash137@gmail.com>
    SPDX-FileCopyrightText: 2024 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2024 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2022-2023 Alexandra <alexankitty@gmail.com>
    SPDX-FileCopyrightText: 2020 Aleix Pol Gonzalez <aleixpol@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.pipewire as PipeWire
import org.kde.taskmanager as TaskManager

PipeWire.PipeWireSourceItem {
    id: pipeWireSourceItem

    property var winId

    readonly property alias hasThumbnail: pipeWireSourceItem.ready

    // Center it in the parent
    anchors.centerIn: parent

    // Fit the stream's aspect ratio inside the parent, so the item covers exactly the image
    // (needed for the rounded corners to sit on the image, not on empty space beside it)
    readonly property real _aspect: (streamSize.width > 0 && streamSize.height > 0) ? streamSize.width / streamSize.height : 4 / 3
    width: Math.min(parent.width, parent.height * _aspect)
    height: width / _aspect

    nodeId: (waylandItem.nodeId > 0) ? waylandItem.nodeId : 0

    // The stream arrives at full window size and plain linear scaling to thumbnail size
    // (often 6-10x smaller) aliases text badly. Render into a larger texture and let
    // mipmapping do the reduction instead; the same layer rounds the corners.
    // textureSize is in device pixels, so account for the screen scale (e.g. 1.3)
    readonly property real _devicePixelRatio: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    readonly property real _supersample: streamSize.width > 0 ? Math.max(1, Math.min(3, streamSize.width / Math.max(1, width * _devicePixelRatio))) : 1
    layer.enabled: ready
    layer.smooth: true
    layer.mipmap: true
    layer.textureSize: Qt.size(Math.round(width * _devicePixelRatio * _supersample), Math.round(height * _devicePixelRatio * _supersample))
    layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: roundedMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    // Translucent windows (e.g. a terminal with background opacity) keep their alpha in the
    // layer, so the tile behind showed through and grayed the thumbnail. Draw an opaque
    // view-colored backing underneath (z: -1 renders below this item's own content).
    // Only under the painted image: the stream buffer can be larger than the window content
    Rectangle {
        x: pipeWireSourceItem.paintedRect.x
        y: pipeWireSourceItem.paintedRect.y
        width: pipeWireSourceItem.paintedRect.width
        height: pipeWireSourceItem.paintedRect.height
        z: -1
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false
        color: Kirigami.Theme.backgroundColor
    }

    Item {
        id: roundedMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        // Round the corners of the painted image, not of the item
        Rectangle {
            x: pipeWireSourceItem.paintedRect.x
            y: pipeWireSourceItem.paintedRect.y
            width: pipeWireSourceItem.paintedRect.width
            height: pipeWireSourceItem.paintedRect.height
            radius: Kirigami.Units.cornerRadius
        }
    }

    TaskManager.ScreencastingRequest {
        id: waylandItem
        uuid: pipeWireSourceItem.winId ? pipeWireSourceItem.winId : ""
    }
}
