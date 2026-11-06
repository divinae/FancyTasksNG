/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "code/singletones"
import "code/media.js" as Media

RowLayout {
    id: controlsRoot

    required property var mediaController

    readonly property int smallSpacing: Kirigami.Units.smallSpacing
    readonly property int gridUnit: Kirigami.Units.gridUnit

    spacing: controlsRoot.smallSpacing
    
    // Strict width constraint for text mode to prevent stretching tooltips
    Layout.maximumWidth: mediaController && mediaController.toolTipDelegate ? mediaController.toolTipDelegate.tooltipInstanceMaximumWidth : controlsRoot.gridUnit * 14
    Layout.fillWidth: true

    // MPRIS Player Controls (Compact: no text, just buttons)
    PlayerController {
        visible: controlsRoot.mediaController ? controlsRoot.mediaController.showPlayerControls : false
        showText: false // Keep text mode ultra-compact by hiding duplicate/long track details
        playerData: controlsRoot.mediaController && controlsRoot.mediaController.playerData ? controlsRoot.mediaController.playerData : Media.emptyPlayer
        isWin: controlsRoot.mediaController && controlsRoot.mediaController.toolTipDelegate ? controlsRoot.mediaController.toolTipDelegate.isWin : false
    }

    // Volume Controls (Inline inside the same row)
    MediaVolumeRow {
        visible: controlsRoot.mediaController ? controlsRoot.mediaController.showVolumeControls : false
        Layout.fillWidth: true
        mediaController: controlsRoot.mediaController

        muteButton.implicitWidth: controlsRoot.gridUnit * 1.2
        muteButton.implicitHeight: controlsRoot.gridUnit * 1.2
        muteButton.padding: 0
        muteButton.text: Wrappers.i18n("Mute")
        percentLabel.font.pixelSize: 10
    }
}
