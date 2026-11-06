/*
    SPDX-FileCopyrightText: 2025-2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-FileCopyrightText: 2024 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2022-2023 Alexandra <alexankitty@gmail.com>
    SPDX-FileCopyrightText: 2023 Marco Martin <notmart@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

Item {
    id: root
    property var parentTask: null
    anchors.fill: parent

    // ── Core geometry ──────────────────────────────────────────────
    readonly property bool iconsOnly: parentTask && parentTask.tasksRoot.iconsOnly
    readonly property var icon: parentTask ? parentTask.taskIcon : null

    // R is based on the iconBox (parent) size — the "square minus margins"
    // This equals the icon at 100% scale, and shrinks with icon scale.
    readonly property real boxW: parent ? parent.width : 0
    readonly property real boxH: parent ? parent.height : 0

    readonly property real iconR: Math.min(boxW, boxH) / 2
    readonly property real badgeR: iconR / 3
    readonly property real badgeDiam: badgeR * 2

    // Dot mode only for tiny panels (< 30px effective icon area)
    readonly property bool dotMode: badgeDiam < 10
    readonly property real effectiveBadgeDiam: Math.max(6, badgeDiam)

    // ── Panel location ─────────────────────────────────────────────
    readonly property int location: Plasmoid.location
    readonly property var config: Plasmoid.configuration
    readonly property bool isVertPanel: location === PlasmaCore.Types.LeftEdge
                                        || location === PlasmaCore.Types.RightEdge

    readonly property real innerSign: {
        if (location === PlasmaCore.Types.TopEdge) return 1;
        if (location === PlasmaCore.Types.LeftEdge) return 1;
        if (location === PlasmaCore.Types.RightEdge) return -1;
        return -1; // BottomEdge / Floating
    }

    // ── Proportional Layout (Resolution Independent) ─────────────
    // Calculated based on a standard 44px panel ratio
    // Audio badge: centered 15% from the left, the notification badge's mirror image
    readonly property real audioCenterX: boxW * 0.15

    // Notification badge: center X = 36px (85%), y = 3px
    readonly property real notifBaseCX: isVertPanel ? (boxW * 0.5) : (boxW * 0.85)
    readonly property real notifBaseCY: isVertPanel ? (boxH * 0.85) : (boxH * 0.068)

    // ── Dive offset when zoomed ────────────────────────────────────
    // qmllint disable missing-property
    readonly property real parentGrow: (iconsOnly && parent && parent.growSize !== undefined) ? parent.growSize : 0
    // qmllint enable missing-property

    readonly property real _diveTarget: {
        if (!iconsOnly || !parentTask || !parentTask.highlighted) return 0;
        if (parentGrow <= 0) return 0;
        return parentGrow * 0.35;
    }
    property real diveOffset: _diveTarget

    Behavior on diveOffset {
        NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
    }

    on_DiveTargetChanged: {
        diveOffset = _diveTarget;
    }

    readonly property real diveDx: isVertPanel ? (-innerSign * diveOffset) : 0
    readonly property real diveDy: isVertPanel ? (diveOffset * 0.5) : diveOffset

    // Helper: clamp value to [min, max]
    function clamp(val, lo, hi) { return Math.max(lo, Math.min(hi, val)); }

    // ── Audio Badge ────────────────────────────────────────────────
    // Symbolic speaker on a small round plate in the icon's top-left corner, mirroring the
    // notification badge on the right; readable on light and dark themes alike
    Item {
        id: audioBadge
        readonly property bool muted: !!root.parentTask?.muted
        readonly property real diam: root.iconsOnly
            ? Math.round(Math.max(12, Math.min(Math.min(root.boxW, root.boxH) * 0.4, Kirigami.Units.iconSizes.smallMedium)))
            : Math.round(Kirigami.Units.gridUnit * 0.85)
        readonly property real idealX: root.audioCenterX - diam / 2 + root.diveDx
        // Top edge like the horizontal notification badge (on vertical panels that one sits
        // at the bottom, so the top-left corner is free there too)
        readonly property real idealY: root.boxH * 0.068 + root.diveDy

        x: root.iconsOnly ? idealX : 0
        y: root.iconsOnly ? idealY : 0
        width: diam
        height: diam

        Behavior on x {
            enabled: root.iconsOnly
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: root.iconsOnly
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }

        visible: root.parentTask ? (root.config.indicateAudioStreams && (root.parentTask.playingAudio || audioBadge.muted)) : false
        scale: audioMouseArea.containsMouse ? 1.15 : 1.0
        Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Kirigami.Theme.backgroundColor
            opacity: 0.9
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
        }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.round(parent.width * 0.7)
            height: width
            source: audioBadge.muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"
            color: audioBadge.muted ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            isMask: true
        }

        MouseArea {
            id: audioMouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton

            onContainsMouseChanged: {
                if (root.parentTask) {
                    root.parentTask.isAudioHovered = audioMouseArea.containsMouse;
                }
            }
            onExited: {
                if (root.parentTask) root.parentTask.isAudioHovered = false;
            }
            onClicked: (mouse) => {
                mouse.accepted = true;
                if (root.parentTask) root.parentTask.toggleMuted();
            }
        }
    }

    // ── Notification Badge ─────────────────────────────────────────
    Badge {
        id: notificationBadge

        readonly property real idealCenterX: root.notifBaseCX + root.diveDx
        readonly property real idealY: root.notifBaseCY + root.diveDy

        x: root.iconsOnly
            ? (idealCenterX - width / 2)
            : (root.boxW - width)
        y: root.iconsOnly
            ? idealY
            : 0

        Behavior on x {
            enabled: root.iconsOnly
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: root.iconsOnly
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }

        height: root.iconsOnly
            ? (root.dotMode ? Math.round(root.effectiveBadgeDiam * 0.5) : root.effectiveBadgeDiam)
            : Math.round(Kirigami.Units.gridUnit * 0.85)

        visible: !!root.parentTask?.badgeVisible
        appId: root.parentTask?.model?.AppId || ""

        isUrgent: (root.config.badgeHighlightNew && !!root.parentTask?.hasUnseenNotifications)
                  || !!root.parentTask?.demandsAttention
        isRound: true
        isBold: false
        fontFactor: 0.7
        showNumber: !root.dotMode
    }

    // ── Window Count Badge ─────────────────────────────────────────
    // Same place and look as the notification badge; shown only when there is no unread badge
    Badge {
        id: windowCountBadge

        readonly property real idealCenterX: root.notifBaseCX + root.diveDx
        readonly property real idealY: root.notifBaseCY + root.diveDy

        x: root.iconsOnly
            ? (idealCenterX - width / 2)
            : (root.boxW - width)
        y: root.iconsOnly
            ? idealY
            : 0

        Behavior on x {
            enabled: root.iconsOnly
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            enabled: root.iconsOnly
            NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
        }

        height: root.iconsOnly
            ? root.effectiveBadgeDiam
            : Math.round(Kirigami.Units.gridUnit * 0.85)

        visible: root.config.showWindowCount && !root.parentTask?.badgeVisible && (root.parentTask?.childCount || 0) >= 2
        number: root.parentTask?.childCount || 0

        isUrgent: false
        isRound: true
        isBold: false
        fontFactor: 0.7
        showNumber: true
    }
}
