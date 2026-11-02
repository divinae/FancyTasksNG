/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
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

    readonly property int iconSize: Kirigami.Units.iconSizes.large
    // Window is a bit longer than the icon in the jump direction, so the bounce has room
    readonly property int jumpRoom: Math.round(iconSize * 0.35)
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

    mainItem: Item {
        width: peek.vertical ? peek.iconSize + peek.jumpRoom : peek.iconSize
        height: peek.vertical ? peek.iconSize : peek.iconSize + peek.jumpRoom
        clip: true

        Kirigami.Icon {
            id: peekIcon
            width: peek.iconSize
            height: peek.iconSize
            source: peek.task && peek.task.model ? peek.task.model.decoration : ""

            // 0 = hidden behind the screen edge, 1 = fully out, >1 = bounce overshoot room
            property real lift: 0
            readonly property real travel: peek.iconSize + peek.jumpRoom
            x: {
                switch (peek.edgeLocation) {
                case PlasmaCore.Types.LeftEdge: return -peek.iconSize + travel * lift - peek.jumpRoom;
                case PlasmaCore.Types.RightEdge: return parent.width - travel * lift + peek.jumpRoom;
                default: return 0;
                }
            }
            y: {
                switch (peek.edgeLocation) {
                case PlasmaCore.Types.TopEdge: return -peek.iconSize + travel * lift - peek.jumpRoom;
                case PlasmaCore.Types.LeftEdge:
                case PlasmaCore.Types.RightEdge: return 0;
                default: return parent.height - travel * lift + peek.jumpRoom;
                }
            }

            SequentialAnimation on lift {
                running: peek.visible
                loops: Animation.Infinite
                // Pop out of the edge, settle partly out, hop twice, then rest peeking
                NumberAnimation { from: 0; to: 1; duration: 260; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0.75; duration: 380; easing.type: Easing.OutBounce }
                NumberAnimation { to: 1; duration: 180; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0.75; duration: 320; easing.type: Easing.OutBounce }
                PauseAnimation { duration: 1200 }
                NumberAnimation { to: 0; duration: 200; easing.type: Easing.InQuad }
                PauseAnimation { duration: 300 }
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
