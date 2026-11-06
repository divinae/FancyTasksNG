/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "code/media.js" as Media

Item {
    id: overlayRoot

    // Drawn over the window thumbnail, so use the theme's dark-on-content color set
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary
    Kirigami.Theme.inherit: false

    required property var mediaController
    required property bool hoveredState

    readonly property int smallSpacing: Kirigami.Units.smallSpacing
    readonly property int longDuration: Kirigami.Units.longDuration

    width: parent.width
    height: controlsColumn.implicitHeight + (overlayRoot.smallSpacing * 2)

    readonly property bool isHovered: overlayHover.hovered

    HoverHandler {
        id: overlayHover
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        radius: Kirigami.Units.cornerRadius

        opacity: overlayRoot.hoveredState ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation {
                duration: overlayRoot.longDuration
            }
        }
    }

    ColumnLayout {
        id: controlsColumn
        anchors.centerIn: parent
        width: parent.width - (overlayRoot.smallSpacing * 2)
        spacing: overlayRoot.smallSpacing

        opacity: overlayRoot.hoveredState ? 1.0 : 0.4
        Behavior on opacity {
            NumberAnimation {
                duration: overlayRoot.longDuration
            }
        }

        // MPRIS Player Controls (with track name and scrolling)
        PlayerController {
            visible: overlayRoot.mediaController ? overlayRoot.mediaController.showPlayerControls : false
            Layout.fillWidth: true
            showText: true // Show track details in the visual overlay as it fits nicely on thumbnails
            playerData: overlayRoot.mediaController && overlayRoot.mediaController.playerData ? overlayRoot.mediaController.playerData : Media.emptyPlayer
            isWin: overlayRoot.mediaController && overlayRoot.mediaController.toolTipDelegate ? overlayRoot.mediaController.toolTipDelegate.isWin : false
        }

        // Volume Controls
        MediaVolumeRow {
            visible: overlayRoot.mediaController ? overlayRoot.mediaController.showVolumeControls : false
            Layout.fillWidth: true
            mediaController: overlayRoot.mediaController

            percentLabel.font: Kirigami.Theme.smallFont
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 99999
        acceptedButtons: Qt.NoButton
        onWheel: (wheel) => {
            if (overlayRoot.mediaController && overlayRoot.mediaController.showVolumeControls) {
                let step = Math.round(65536 * 0.05 * wheel.angleDelta.y / 120);
                if (step !== 0) {
                    overlayRoot.mediaController.adjustAppVolume(step);
                }
                wheel.accepted = true;
            }
        }
    }
}
