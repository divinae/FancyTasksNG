/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.mpris as Mpris

import "code/singletones"
import "code/media.js" as Media

Item {
    id: barRoot

    required property var mediaController

    // Emitted when the track title is clicked: this row sits below the thumbnail, outside
    // its activate-on-click area, so the title activates the window itself
    signal activateRequested()

    width: parent.width
    height: controlsRow.height + (canSeek ? seekSlider.implicitHeight : 0)

    readonly property bool hasPlayer: mediaController ? mediaController.showPlayerControls : false
    readonly property bool hasVolume: mediaController ? mediaController.showVolumeControls : false
    // Volume-only mode: no player controls, just audio stream
    readonly property bool volumeOnlyMode: hasVolume && !hasPlayer

    // Local cached properties for optimized property bindings and less verbosity
    readonly property var player: mediaController ? mediaController.playerData : null
    readonly property var streamMgr: mediaController ? mediaController.audioStreamManager : null
    readonly property real appVolume: mediaController ? mediaController.appVolume : 0
    readonly property bool muted: mediaController ? mediaController.muted : false
    // Seek bar is shown for players that report a track length and accept seeking
    readonly property bool canSeek: hasPlayer && !!player && player.canSeek && player.length > 0

    RowLayout {
        id: controlsRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Kirigami.Units.gridUnit * 1.4
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // [prev][play/pause][next] Buttons
        RowLayout {
            id: playerButtons
            visible: barRoot.hasPlayer
            spacing: 2
            Layout.alignment: Qt.AlignVCenter

            TransportButton {
                enabled: barRoot.player ? barRoot.player.canGoPrevious : false
                icon.name: mirrored ? "media-skip-forward" : "media-skip-backward"
                onClicked: if (barRoot.player) barRoot.player.Previous()
            }

            TransportButton {
                readonly property bool isPlaying: barRoot.player ? barRoot.player.playbackStatus === Mpris.PlaybackStatus.Playing : false
                enabled: barRoot.player ? (isPlaying ? barRoot.player.canPause : DesktopActionsManager.canPlay(barRoot.player)) : false
                icon.name: isPlaying ? "media-playback-pause" : "media-playback-start"
                onClicked: {
                    if (barRoot.player) {
                        if (!isPlaying) {
                            DesktopActionsManager.play(barRoot.player);
                        } else {
                            barRoot.player.Pause();
                        }
                    }
                }
            }

            TransportButton {
                enabled: barRoot.player ? barRoot.player.canGoNext : false
                icon.name: mirrored ? "media-skip-backward" : "media-skip-forward"
                onClicked: if (barRoot.player) barRoot.player.Next()
            }
        }

        // Scrollable track/artist title with fade hint when text overflows
        ScrollableTextWrapper {
            id: songTextWrapper
            visible: barRoot.hasPlayer
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: songText.height
            implicitWidth: songText.implicitWidth

            // songTextWrapper declines presses (it only scrolls on hover), so this one
            // receives clicks on the title
            MouseArea {
                anchors.fill: parent
                onClicked: barRoot.activateRequested()
            }

            // Fade the right edge to transparent so users know the text continues.
            // A mask instead of a background-colored gradient keeps it correct on a translucent theme frame.
            readonly property bool overflowing: state === "" && songText.implicitWidth > width
            layer.enabled: overflowing
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: songFadeMask
                maskThresholdMin: 0.0
                maskSpreadAtMin: 1.0
            }

            textItem: PlasmaComponents3.Label {
                id: songText
                maximumLineCount: 1
                wrapMode: Text.NoWrap
                elide: parent.state ? Text.ElideNone : Text.ElideRight
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                textFormat: Text.PlainText
                text: {
                    if (!barRoot.player) return "";
                    let track = barRoot.player.track || "";
                    let artist = barRoot.player.artist || "";
                    if (track && artist) {
                        return artist + " - " + track;
                    }
                    return track || artist || "";
                }
            }

            Item {
                id: songFadeMask
                anchors.fill: parent
                visible: false
                layer.enabled: true

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "white" }
                        GradientStop { position: Math.max(0, 1 - Kirigami.Units.gridUnit * 1.5 / Math.max(1, songTextWrapper.width)); color: "white" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
            }
        }

        // [D] - Mute & Hover Volume Button (only when player controls are present)
        PlasmaComponents3.ToolButton {
            id: volumeButton
            visible: barRoot.hasVolume && !barRoot.volumeOnlyMode
            implicitWidth: Kirigami.Units.gridUnit * 1.2
            implicitHeight: Kirigami.Units.gridUnit * 1.2
            padding: 0
            icon.width: Kirigami.Units.iconSizes.small
            icon.height: Kirigami.Units.iconSizes.small
            Layout.alignment: Qt.AlignVCenter

            icon.name: Media.volumeIconName(barRoot.muted, barRoot.appVolume / 65536)

            text: Wrappers.i18n("Mute")
            display: PlasmaComponents3.AbstractButton.IconOnly
            checkable: true
            checked: barRoot.muted
            onClicked: {
                if (barRoot.mediaController) {
                    barRoot.mediaController.toggleMuted();
                }
            }

            // Hover tracking to show vertical slider
            HoverHandler {
                id: volumeButtonHover
            }

            // Mouse wheel support directly on the icon!
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: (wheel) => {
                    if (barRoot.mediaController) {
                        // Scale by actual scroll delta so touchpad kinetic micro-events
                        // don't cause full 5% jumps. Standard wheel notch = 120 units = 5%.
                        let step = Math.round(65536 * 0.05 * wheel.angleDelta.y / 120);
                        if (step !== 0)
                            barRoot.mediaController.adjustAppVolume(step);
                        wheel.accepted = true;
                    }
                }
            }

            // Vertical Pop-up Volume Slider (Declared inside the button to allow proper anchors to parent)
            Item {
                id: volumePopup
                visible: barRoot.showSlider && barRoot.hasVolume
                Kirigami.Theme.colorSet: Kirigami.Theme.Complementary
                Kirigami.Theme.inherit: false
                width: Kirigami.Units.gridUnit * 1.7
                height: Kirigami.Units.gridUnit * 6.5
                
                // Align right edge of popup to right edge of the button
                // so it never overflows the tooltip boundary
                anchors.bottom: parent.top
                anchors.bottomMargin: Kirigami.Units.smallSpacing
                anchors.right: parent.right
                z: 99999

                // Keep popup alive when hovered
                HoverHandler {
                    id: sliderHover
                }

                // Global wheel listener for the entire popup (including Label and Slider)
                // Using acceptedButtons: Qt.NoButton lets clicks/drags pass through to the Slider below,
                // while cleanly intercepting all scroll events!
                MouseArea {
                    anchors.fill: parent
                    z: 99999
                    acceptedButtons: Qt.NoButton
                    onWheel: (wheel) => {
                        if (barRoot.mediaController) {
                            let step = Math.round(65536 * 0.05 * wheel.angleDelta.y / 120);
                            if (step !== 0)
                                barRoot.mediaController.adjustAppVolume(step);
                            wheel.accepted = true;
                        }
                    }
                }

                // Semi-transparent background so slider doesn't blend into thumbnail
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.55)
                    radius: Kirigami.Units.cornerRadius
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: 2

                    PlasmaComponents3.Label {
                        text: {
                            let volPercent = Math.round(barRoot.appVolume / 65536 * 100);
                            return volPercent + "%";
                        }
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    PlasmaComponents3.Slider {
                        id: volumeSlider
                        orientation: Qt.Vertical
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        
                        topPadding: 6
                        bottomPadding: 6

                        from: barRoot.streamMgr ? barRoot.streamMgr.item.minimalVolume : 0
                        to: barRoot.streamMgr ? barRoot.streamMgr.item.normalVolume : 65536
                        // Block built-in QML Slider wheel handling completely to prevent duplicate scroll bugs!
                        WheelHandler {
                            acceptedButtons: Qt.NoButton
                            onWheel: (event) => {
                                event.accepted = true;
                            }
                        }

                        Binding {
                            target: volumeSlider
                            property: "value"
                            value: barRoot.appVolume
                            when: !volumeSlider.pressed
                        }

                        onMoved: {
                            if (barRoot.mediaController) {
                                barRoot.mediaController.setVolume(value);
                            }
                        }

                        

                     }
                }
            }
        }

        // Inline horizontal volume slider for volume-only mode (no player controls)
        Item {
            visible: barRoot.volumeOnlyMode
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter

            MediaVolumeRow {
                anchors.fill: parent
                mediaController: barRoot.mediaController

                muteButton.implicitWidth: Kirigami.Units.gridUnit * 1.2
                muteButton.implicitHeight: Kirigami.Units.gridUnit * 1.2
                muteButton.padding: 0
                muteButton.text: Wrappers.i18n("Mute")
                slider.topPadding: 4
                slider.bottomPadding: 4
                percentLabel.font: Kirigami.Theme.smallFont
            }

            MouseArea {
                anchors.fill: parent
                z: 1
                acceptedButtons: Qt.NoButton
                onWheel: (wheel) => {
                    if (barRoot.mediaController) {
                        let step = Math.round(65536 * 0.05 * wheel.angleDelta.y / 120);
                        if (step !== 0)
                            barRoot.mediaController.adjustAppVolume(step);
                        wheel.accepted = true;
                    }
                }
            }
        }
    }

    // Hover State Logic for vertical slider
    property bool showSlider: volumeButtonHover.hovered || sliderHover.hovered || hoverTimer.running

    PlasmaComponents3.Slider {
        id: seekSlider
        visible: barRoot.canSeek
        anchors.top: controlsRow.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing

        // MPRIS position and length are in microseconds
        from: 0
        to: barRoot.player ? barRoot.player.length : 0

        Binding on value {
            value: barRoot.player ? barRoot.player.position : 0
            when: !seekSlider.pressed
            restoreMode: Binding.RestoreNone
        }

        // Don't let the wheel scrub through the track by accident
        WheelHandler {
            acceptedButtons: Qt.NoButton
            onWheel: event => event.accepted = true
        }

        onPressedChanged: {
            if (!pressed && barRoot.player)
                barRoot.player.Seek(Math.round(value - barRoot.estimatedPosition()));
        }
    }

    // player.position is only refreshed when polled, so extrapolate it from the time of the
    // last update while playing; Seek() is relative and needs the real current position
    property double positionStamp: Date.now()
    Connections {
        target: barRoot.player
        ignoreUnknownSignals: true
        function onPositionChanged() {
            barRoot.positionStamp = Date.now();
        }
    }
    function estimatedPosition(): real {
        const player = barRoot.player;
        if (player.playbackStatus !== Mpris.PlaybackStatus.Playing)
            return player.position;
        return player.position + (Date.now() - positionStamp) * 1000 * (player.rate || 1);
    }

    // The player only reports position on changes; poll it while the bar is visible and playing
    Timer {
        interval: 1000
        repeat: true
        running: barRoot.canSeek && barRoot.visible && barRoot.player.playbackStatus === Mpris.PlaybackStatus.Playing
        onTriggered: barRoot.player.updatePosition()
    }

    onShowSliderChanged: {
        if (!showSlider) {
            hoverTimer.stop();
        }
    }

    Timer {
        id: hoverTimer
        interval: 250 // highly responsive and smooth fade-out delay
        repeat: false
    }

    // Trigger timer when mouse leaves
    Connections {
        target: volumeButtonHover
        function onHoveredChanged() {
            if (!volumeButtonHover.hovered && !sliderHover.hovered) {
                hoverTimer.start();
            } else {
                hoverTimer.stop();
            }
        }
    }

    Connections {
        target: sliderHover
        function onHoveredChanged() {
            if (!volumeButtonHover.hovered && !sliderHover.hovered) {
                hoverTimer.start();
            } else {
                hoverTimer.stop();
            }
        }
    }

}
