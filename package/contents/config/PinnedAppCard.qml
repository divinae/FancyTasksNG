/*
    SPDX-FileCopyrightText: 2025-2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-FileCopyrightText: 2025 SushiTrash <strash137@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "../ui/code/singletones"

// A single row in ConfigPinnedApps.qml's pinned-launchers ListView: icon,
// name, drag-to-reorder, and remove button. Styled like a Kirigami Addons
// FormCard delegate (padding, hover feedback, inset separators) since it sits
// inside a FormCard.FormCard on the page.
Item {
    id: pinnedAppDelegate

    required property var model
    required property int index

    required property var pageRoot
    required property var cardStyle
    required property var pinnedModel

    width: ListView.view.width
    height: beingDragged ? 0 : dragContent.implicitHeight
    clip: true

    // index is -1 while a delegate is being torn down after a model reset;
    // don't mistake that for the dragged row (it would get reparented).
    property bool beingDragged: index !== -1 && index === pinnedAppDelegate.pageRoot.dragItemIndex

    // FormCard delegate paddings (FormCardUnits is private to Kirigami Addons)
    readonly property int horizontalPadding: Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing
    readonly property int verticalPadding: Kirigami.Units.largeSpacing

    // Drop insertion indicator (arrows + line), shown above/below a row
    // while dragging.
    Component {
        id: dropIndicatorComponent
        Item {
            height: 2
            Canvas {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 10
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.fillStyle = pinnedAppDelegate.pageRoot.themeHighlightColor;
                    ctx.beginPath();
                    ctx.moveTo(0, 0);
                    ctx.lineTo(width, height / 2);
                    ctx.lineTo(0, height);
                    ctx.closePath();
                    ctx.fill();
                }
            }
            Canvas {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 10
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    ctx.fillStyle = pinnedAppDelegate.pageRoot.themeHighlightColor;
                    ctx.beginPath();
                    ctx.moveTo(width, 0);
                    ctx.lineTo(0, height / 2);
                    ctx.lineTo(width, height);
                    ctx.closePath();
                    ctx.fill();
                }
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                height: 2
                color: pinnedAppDelegate.pageRoot.themeHighlightColor
            }
        }
    }

    // Top insertion indicator
    Loader {
        active: pinnedAppDelegate.pageRoot.isDragging && pinnedAppDelegate.pageRoot.dropItemIndex === pinnedAppDelegate.index && !pinnedAppDelegate.beingDragged
        anchors.left: parent.left
        anchors.right: parent.right
        y: -1
        z: 20
        sourceComponent: dropIndicatorComponent
    }

    // Bottom insertion indicator (insert at end of list)
    Loader {
        active: {
            if (!pinnedAppDelegate.pageRoot.isDragging || pinnedAppDelegate.beingDragged) return false;
            if (pinnedAppDelegate.pageRoot.dropItemIndex !== pinnedAppDelegate.pinnedModel.count) return false;
            var lastIdx = pinnedAppDelegate.pageRoot.dragItemIndex === pinnedAppDelegate.pinnedModel.count - 1
                ? pinnedAppDelegate.pinnedModel.count - 2
                : pinnedAppDelegate.pinnedModel.count - 1;
            return pinnedAppDelegate.index === lastIdx;
        }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 20
        sourceComponent: dropIndicatorComponent
    }

    // Row separator, FormCard style: thin and inset, drawn above every row
    // but the first. Hidden while the row is lifted out by a drag.
    Kirigami.Separator {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Kirigami.Units.largeSpacing
        anchors.rightMargin: Kirigami.Units.largeSpacing
        visible: pinnedAppDelegate.index > 0 && !pinnedAppDelegate.beingDragged
        opacity: 0.5
        z: 1
    }

    Item {
        id: dragContent
        width: pinnedAppDelegate.width
        implicitHeight: contentRow.implicitHeight + pinnedAppDelegate.verticalPadding * 2

        // Same colour set as the FormCard the row sits in, so the lifted row
        // keeps the card look after it is reparented to the page.
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false

        Drag.active: dragMouseArea.drag.active
        Drag.source: pinnedAppDelegate
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        states: [
            State {
                when: pinnedAppDelegate.beingDragged
                ParentChange {
                    target: dragContent
                    parent: pinnedAppDelegate.pageRoot
                }
                PropertyChanges {
                    dragContent.z: 100
                    dragContent.opacity: 0.9
                }
            }
        ]

        HoverHandler {
            id: rowHoverHandler
        }

        ToolTip.text: pinnedAppDelegate.model.comment || pinnedAppDelegate.model.name || ""
        ToolTip.visible: rowHoverHandler.hovered && !removeButton.hovered && !pinnedAppDelegate.pageRoot.isDragging && ToolTip.text !== ""
        ToolTip.delay: 1000

        // Card surface, only while the row is lifted out of the card by a drag
        Rectangle {
            anchors.fill: parent
            visible: pinnedAppDelegate.beingDragged
            color: Kirigami.Theme.backgroundColor
            radius: Kirigami.Units.cornerRadius
            border.width: 1
            border.color: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.15)
        }

        // Hover / press feedback, same as FormCard's FormDelegateBackground
        Rectangle {
            anchors.fill: parent
            color: Kirigami.Theme.textColor
            opacity: dragMouseArea.pressed ? 0.2
                : (rowHoverHandler.hovered && !pinnedAppDelegate.pageRoot.isDragging && !Kirigami.Settings.tabletMode) ? 0.07
                : 0
            Behavior on opacity {
                NumberAnimation { duration: Kirigami.Units.shortDuration }
            }
        }

        MouseArea {
            id: dragMouseArea
            anchors.fill: parent
            z: -1
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            drag.target: dragContent
            drag.axis: Drag.YAxis

            onPressed: {
                pinnedAppDelegate.pageRoot.dragItemIndex = pinnedAppDelegate.index;
                pinnedAppDelegate.pageRoot.isDragging = true;
            }

            onReleased: {
                pinnedAppDelegate.pageRoot.isDragging = false;

                var dropIdx = pinnedAppDelegate.pageRoot.dropItemIndex;
                var dragIdx = pinnedAppDelegate.pageRoot.dragItemIndex;

                pinnedAppDelegate.pageRoot.dragItemIndex = -1;
                pinnedAppDelegate.pageRoot.dropItemIndex = -1;

                // A plain click (no drag over the list) leaves dropItemIndex
                // at -1; clamping that to 0 would move the row to the top.
                if (dropIdx === -1) {
                    pinnedAppDelegate.pageRoot.refreshPinnedAppsModel();
                    return;
                }

                var targetIndex = dropIdx <= dragIdx ? dropIdx : dropIdx - 1;
                if (targetIndex < 0) targetIndex = 0;
                if (targetIndex >= pinnedAppDelegate.pinnedModel.count) targetIndex = pinnedAppDelegate.pinnedModel.count - 1;

                if (dragIdx !== -1 && targetIndex !== dragIdx) {
                    pinnedAppDelegate.pageRoot.moveItem(dragIdx, targetIndex);
                } else {
                    pinnedAppDelegate.pageRoot.refreshPinnedAppsModel();
                }
            }
        }

        RowLayout {
            id: contentRow
            anchors.fill: parent
            anchors.leftMargin: pinnedAppDelegate.horizontalPadding
            anchors.rightMargin: pinnedAppDelegate.horizontalPadding
            anchors.topMargin: pinnedAppDelegate.verticalPadding
            anchors.bottomMargin: pinnedAppDelegate.verticalPadding
            spacing: Kirigami.Units.largeSpacing

            // Visual cue only; the whole row is the drag area
            Kirigami.Icon {
                source: "handle-sort"
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                opacity: 0.6
            }

            Kirigami.Icon {
                source: pinnedAppDelegate.model.icon
                Layout.preferredWidth: pinnedAppDelegate.cardStyle.iconSize
                Layout.preferredHeight: pinnedAppDelegate.cardStyle.iconSize
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Kirigami.Units.smallSpacing

                Label {
                    Layout.fillWidth: true
                    text: pinnedAppDelegate.model.name
                    elide: Text.ElideRight
                }

                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: pinnedAppDelegate.model.genericName || ""
                    elide: Text.ElideRight
                    color: Kirigami.Theme.disabledTextColor
                    font: Kirigami.Theme.smallFont
                }
            }

            ToolButton {
                id: removeButton
                visible: !pinnedAppDelegate.beingDragged
                icon.name: "list-remove"
                text: Wrappers.i18n("Remove")
                display: AbstractButton.IconOnly

                onClicked: {
                    let currentLaunchers = Array.from(pinnedAppDelegate.pageRoot.pinnedLaunchers);
                    currentLaunchers.splice(pinnedAppDelegate.index, 1);
                    pinnedAppDelegate.pageRoot.cfg_launchers = currentLaunchers;
                    pinnedAppDelegate.pageRoot.refreshPinnedAppsModel();
                }

                ToolTip.text: text
                ToolTip.visible: hovered
                ToolTip.delay: 1000
            }
        }
    }
}
