/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "code/media.js" as Media

// [mute] [volume slider] [percent] row of a ToolTipMediaController's audio streams.
// Users tweak the parts through the muteButton, slider and percentLabel aliases.
RowLayout {
    id: volumeRow

    required property var mediaController

    property alias muteButton: muteButton
    property alias slider: slider
    property alias percentLabel: percentLabel

    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents3.ToolButton {
        id: muteButton

        icon.width: Kirigami.Units.iconSizes.small
        icon.height: Kirigami.Units.iconSizes.small
        icon.name: Media.volumeIconName(checked, slider.value / slider.to)

        display: PlasmaComponents3.AbstractButton.IconOnly
        checkable: true
        checked: volumeRow.mediaController ? volumeRow.mediaController.muted : false
        onClicked: {
            if (volumeRow.mediaController) {
                volumeRow.mediaController.toggleMuted();
            }
        }
    }

    PlasmaComponents3.Slider {
        id: slider
        Layout.fillWidth: true

        from: volumeRow.mediaController && volumeRow.mediaController.audioStreamManager ? volumeRow.mediaController.audioStreamManager.item.minimalVolume : 0
        to: volumeRow.mediaController && volumeRow.mediaController.audioStreamManager ? volumeRow.mediaController.audioStreamManager.item.normalVolume : 65536

        // Block built-in QML Slider wheel handling completely to prevent duplicate scroll bugs!
        WheelHandler {
            acceptedButtons: Qt.NoButton
            onWheel: (event) => {
                event.accepted = true;
            }
        }

        Binding {
            target: slider
            property: "value"
            value: volumeRow.mediaController ? volumeRow.mediaController.appVolume : 0
            when: !slider.pressed
        }

        onMoved: {
            if (volumeRow.mediaController) {
                volumeRow.mediaController.setVolume(value);
            }
        }
    }

    PlasmaComponents3.Label {
        id: percentLabel
        text: Math.round(slider.value / slider.to * 100) + "%"
        Layout.minimumWidth: Kirigami.Units.gridUnit * 1.5
        horizontalAlignment: Text.AlignHCenter
    }
}
