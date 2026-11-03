/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.taskmanager as TaskManager

// Small frameless window at the screen edge, where the task sits in an auto-hidden panel.
// While the app wants attention its icon bounces out of the edge; clicking it activates the
// app. Lets an auto-hidden panel stay hidden instead of covering the window being worked in.
PlasmaCore.Dialog {
    id: peek

    required property Item task
    required property var tasksRoot

    readonly property int iconSize: Math.round(Kirigami.Units.iconSizes.large * 1.15)
    // At the top of a jump the icon is fully out and lifted this far above the edge (macOS Dock style)
    readonly property int rise: Math.round(iconSize * 0.55)
    // Room for the drop shadow
    readonly property int shadowPad: Kirigami.Units.smallSpacing * 2
    // Window length along the jump direction / across it
    readonly property int alongLength: iconSize + rise + shadowPad
    readonly property int acrossLength: iconSize + shadowPad * 2
    readonly property int edgeLocation: tasksRoot.effectiveLocation
    readonly property bool vertical: edgeLocation === PlasmaCore.Types.LeftEdge || edgeLocation === PlasmaCore.Types.RightEdge

    type: PlasmaCore.Dialog.Notification
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowStaysOnTopHint
    location: PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Types.NoBackground
    hideOnWindowDeactivate: false

    // Place it at the screen edge, centered on the task's position along the edge
    function updatePosition() {
        const screen = peek.tasksRoot.containment ? peek.tasksRoot.containment.screenGeometry : null;
        if (!screen || !peek.task)
            return;
        const center = peek.task.mapToGlobal(peek.task.width / 2, peek.task.height / 2);
        const w = peek.mainItem.width;
        const h = peek.mainItem.height;
        switch (peek.edgeLocation) {
        case PlasmaCore.Types.TopEdge:
            peek.x = center.x - w / 2;
            peek.y = screen.y;
            break;
        case PlasmaCore.Types.LeftEdge:
            peek.x = screen.x;
            peek.y = center.y - h / 2;
            break;
        case PlasmaCore.Types.RightEdge:
            peek.x = screen.x + screen.width - w;
            peek.y = center.y - h / 2;
            break;
        default:
            peek.x = center.x - w / 2;
            peek.y = screen.y + screen.height - h;
            break;
        }
    }
    onVisibleChanged: if (visible) updatePosition()

    // Shown only while the panel itself is hidden (and nothing is fullscreen); see main.qml
    visible: tasksRoot.showAttentionPeek

    mainItem: Item {
        width: peek.vertical ? peek.alongLength : peek.acrossLength
        height: peek.vertical ? peek.acrossLength : peek.alongLength
        // Everything beyond the window edge (= the screen edge) is hidden, so the icon
        // appears to come out from under the screen
        clip: true


        Kirigami.Icon {
            id: peekIcon
            width: peek.iconSize
            height: peek.iconSize
            source: peek.task && peek.task.model ? peek.task.model.decoration : ""

            // 0 = fully hidden under the screen edge, 1 = top of the jump
            property real lift: 0
            // Distance of the icon's edge-side boundary from the screen edge (negative = under it)
            readonly property real offset: -peek.iconSize + lift * (peek.iconSize + peek.rise)

            x: {
                switch (peek.edgeLocation) {
                case PlasmaCore.Types.LeftEdge: return offset;
                case PlasmaCore.Types.RightEdge: return parent.width - offset - peek.iconSize;
                default: return peek.shadowPad;
                }
            }
            y: {
                switch (peek.edgeLocation) {
                case PlasmaCore.Types.TopEdge: return offset;
                case PlasmaCore.Types.LeftEdge:
                case PlasmaCore.Types.RightEdge: return peek.shadowPad;
                default: return parent.height - offset - peek.iconSize;
                }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowBlur: 0.6
                shadowOpacity: 0.45
                shadowVerticalOffset: 2
                autoPaddingEnabled: true
            }

            // Ball-like bounce: fast up, accelerating fall back under the edge, a smaller
            // second hop, then a short rest hidden
            // One bounce, then a rest: 1 s during the 30 s burst, 5 minutes afterwards
            // (Task.attentionRestMs)
            SequentialAnimation {
                id: peekBounce
                NumberAnimation { target: peekIcon; property: "lift"; from: 0; to: 1; duration: 280; easing.type: Easing.OutQuad }
                NumberAnimation { target: peekIcon; property: "lift"; to: 0; duration: 300; easing.type: Easing.InQuad }
                NumberAnimation { target: peekIcon; property: "lift"; to: 0.4; duration: 170; easing.type: Easing.OutQuad }
                NumberAnimation { target: peekIcon; property: "lift"; to: 0; duration: 170; easing.type: Easing.InQuad }
                onFinished: {
                    if (peek.visible) {
                        peekRest.interval = peek.task ? peek.task.attentionRestMs() : 1000;
                        peekRest.start();
                    }
                }
            }
            Timer {
                id: peekRest
                onTriggered: if (peek.visible) peekBounce.start()
            }
            // Becoming visible (e.g. the panel hid again) bounces only during the burst;
            // afterwards it just resumes the 5-minute reminder
            function resume() {
                if (!peek.task || !peek.task.attentionCalm)
                    peekBounce.start();
                else if (!peekRest.running) {
                    peekRest.interval = peek.task.attentionRestMs();
                    peekRest.start();
                }
            }
            Component.onCompleted: if (peek.visible) resume()
            Connections {
                target: peek.task
                ignoreUnknownSignals: true
                function onAttentionCalmChanged() {
                    if (peek.visible && !peek.task.attentionCalm && !peekBounce.running) {
                        peekRest.stop();
                        peekBounce.start();
                    }
                }
            }
            Connections {
                target: peek
                function onVisibleChanged() {
                    if (peek.visible) {
                        peekIcon.resume();
                    } else {
                        peekRest.stop();
                        peekBounce.stop();
                        peekIcon.lift = 0;
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // Activate the window that wants attention (in a group: that child, not the
            // usual cycling), or the task itself for an app-level urgent flag
            onClicked: {
                if (!peek.task || !peek.task.model)
                    return;
                const model = peek.tasksRoot.tasksModel;
                const index = peek.task.modelIndex();
                if (peek.task.model.IsGroupParent) {
                    for (let i = 0; i < model.rowCount(index); ++i) {
                        const child = model.makeModelIndex(index.row, i);
                        if (model.data(child, TaskManager.AbstractTasksModel.IsDemandingAttention) === true) {
                            model.requestActivate(child);
                            return;
                        }
                    }
                }
                model.requestActivate(index);
            }
        }
    }
}
