/*
    SPDX-FileCopyrightText: 2025-2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-FileCopyrightText: 2013 Eike Hein <hein@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard
import org.kde.plasma.core as PlasmaCore

import "../ui/code/singletones"

ConfigPage {
    id: behaviorPage
    ConfigFormPage {
        cfg_page: behaviorPage

        FormCard.FormHeader {
            title: Wrappers.i18n("Grouping")
        }

        FormCard.FormCard {
            ButtonGroup {
                id: groupingButtonGroup
            }

            FormCard.FormRadioDelegate {
                id: groupDisabled
                text: Wrappers.i18nc("State", "Disabled")
                ButtonGroup.group: groupingButtonGroup
                checked: behaviorPage.cfg_groupingStrategy === 0
                onToggled: if (checked)
                    behaviorPage.cfg_groupingStrategy = 0
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormRadioDelegate {
                id: groupSideBySide
                text: Wrappers.i18n("Place windows of one application side-by-side")
                ButtonGroup.group: groupingButtonGroup
                checked: behaviorPage.cfg_groupingStrategy === 1 && !behaviorPage.cfg_groupPopups
                onToggled: if (checked) {
                    behaviorPage.cfg_groupingStrategy = 1;
                    behaviorPage.cfg_groupPopups = false;
                }
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormRadioDelegate {
                id: groupCollapsed
                text: Wrappers.i18n("Combine into one button by application name")
                ButtonGroup.group: groupingButtonGroup
                checked: behaviorPage.cfg_groupingStrategy === 1 && behaviorPage.cfg_groupPopups
                onToggled: if (checked) {
                    behaviorPage.cfg_groupingStrategy = 1;
                    behaviorPage.cfg_groupPopups = true;
                }
            }

            FormCard.FormDelegateSeparator {
                visible: groupIconEnabled.visible
            }

            FormCard.FormSwitchDelegate {
                id: groupIconEnabled
                visible: groupCollapsed.checked
                text: Wrappers.i18n("Standard group overlay")
                checked: behaviorPage.cfg_groupIconEnabled
                onToggled: behaviorPage.cfg_groupIconEnabled = checked
            }

            FormCard.FormDelegateSeparator {
                visible: onlyGroupWhenFull.visible
            }

            FormCard.FormSwitchDelegate {
                id: onlyGroupWhenFull
                visible: !groupDisabled.checked
                enabled: behaviorPage.cfg_iconOnly === 0
                text: Wrappers.i18n("Only when the task manager is full")
                checked: behaviorPage.cfg_onlyGroupWhenFull
                onToggled: behaviorPage.cfg_onlyGroupWhenFull = checked
            }
        }

        // Apps excluded with "Allow this program to be grouped" in the task context menu
        FormCard.FormHeader {
            visible: neverGroupedCard.visible
            title: Wrappers.i18n("Never grouped")
        }

        FormCard.FormCard {
            id: neverGroupedCard
            visible: !groupDisabled.checked && (behaviorPage.cfg_groupingAppIdBlacklist || []).length > 0

            Repeater {
                model: groupDisabled.checked ? [] : (behaviorPage.cfg_groupingAppIdBlacklist || [])

                delegate: ColumnLayout {
                    id: blockedApp
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0

                    FormCard.FormDelegateSeparator {
                        visible: blockedApp.index > 0
                    }

                    FormCard.AbstractFormDelegate {
                        Layout.fillWidth: true
                        background: null
                        focusPolicy: Qt.NoFocus

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.largeSpacing

                            Kirigami.Icon {
                                source: blockedApp.modelData
                                fallback: "application-x-executable"
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                            }
                            Label {
                                Layout.fillWidth: true
                                text: blockedApp.modelData
                                elide: Text.ElideRight
                            }
                            ToolButton {
                                icon.name: "edit-delete-remove"
                                text: Wrappers.i18n("Allow grouping")
                                display: AbstractButton.IconOnly
                                ToolTip.visible: hovered
                                ToolTip.text: text
                                onClicked: behaviorPage.allowGrouping(blockedApp.modelData)
                            }
                        }
                    }
                }
            }
        }

        FormCard.FormHeader {
            title: Wrappers.i18n("Order")
        }

        FormCard.FormCard {
            FormCard.FormComboBoxDelegate {
                id: cfg_sortingStrategy
                text: Wrappers.i18n("Sort tasks")
                model: [Wrappers.i18n("Do not sort"), Wrappers.i18n("Manually"), Wrappers.i18n("Alphabetically"), Wrappers.i18n("By desktop"), Wrappers.i18n("By activity"), Wrappers.i18n("By horizontal window position")]
                currentIndex: behaviorPage.cfg_sortingStrategy
                onActivated: index => behaviorPage.cfg_sortingStrategy = index
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormTextDelegate {
                text: Wrappers.i18n("New tasks appear")
            }

            FormCard.FormRadioSelectorDelegate {
                id: reverseModeSelector
                consistentWidth: true
                actions: [
                    Kirigami.Action {
                        text: {
                            if (behaviorPage.plasmoidFormFactor === PlasmaCore.Types.Vertical) {
                                return Wrappers.i18n("On the bottom");
                            }
                            // horizontal
                            if (!LayoutMirroring.enabled) {
                                return Wrappers.i18n("To the right");
                            } else {
                                return Wrappers.i18n("To the left");
                            }
                        }
                        onTriggered: behaviorPage.cfg_reverseMode = false
                    },
                    Kirigami.Action {
                        text: {
                            if (behaviorPage.plasmoidFormFactor === PlasmaCore.Types.Vertical) {
                                return Wrappers.i18n("On the top");
                            }
                            // horizontal
                            if (!LayoutMirroring.enabled) {
                                return Wrappers.i18n("To the left");
                            } else {
                                return Wrappers.i18n("To the right");
                            }
                        }
                        onTriggered: behaviorPage.cfg_reverseMode = true
                    }
                ]
            }

            // The selector writes selectedIndex itself when clicked, which would break a
            // plain binding; this re-asserts it from the config (e.g. after Defaults)
            Binding {
                target: reverseModeSelector
                property: "selectedIndex"
                value: behaviorPage.cfg_reverseMode ? 1 : 0
                restoreMode: Binding.RestoreBindingOrValue
            }
        }

        FormCard.FormHeader {
            title: Wrappers.i18n("Mouse")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: cfg_minimizeActiveTaskOnClick
                text: Wrappers.i18n("Clicking active task minimizes the task")
                checked: behaviorPage.cfg_minimizeActiveTaskOnClick
                onToggled: behaviorPage.cfg_minimizeActiveTaskOnClick = checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormComboBoxDelegate {
                id: cfg_groupedTaskVisualization
                text: Wrappers.i18n("Clicking group button")
                model: [Wrappers.i18n("Cycles through tasks"), Wrappers.i18n("Shows small window previews"), Wrappers.i18n("Shows large window previews"), Wrappers.i18n("Shows textual list"),]
                currentIndex: behaviorPage.cfg_groupedTaskVisualization
                onActivated: index => behaviorPage.cfg_groupedTaskVisualization = index
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormComboBoxDelegate {
                id: cfg_middleClickAction
                text: Wrappers.i18n("Middle-clicking any task")
                model: [Wrappers.i18n("Does nothing"), Wrappers.i18n("Closes window or group"), Wrappers.i18n("Opens a new window"), Wrappers.i18n("Minimizes/Restores window or group"), Wrappers.i18n("Toggles grouping"), Wrappers.i18n("Brings it to the current virtual desktop")]
                currentIndex: behaviorPage.cfg_middleClickAction
                onActivated: index => behaviorPage.cfg_middleClickAction = index
            }

            FormCard.FormDelegateSeparator {
                visible: cfg_smokeExplosionOnClose.visible
            }

            FormCard.FormSwitchDelegate {
                id: cfg_smokeExplosionOnClose
                visible: behaviorPage.cfg_iconOnly === 1 && cfg_middleClickAction.currentIndex === 1
                text: Wrappers.i18n("Animation of closing/removing an icon from the panel")
                checked: behaviorPage.cfg_smokeExplosionOnClose
                onToggled: behaviorPage.cfg_smokeExplosionOnClose = checked
            }
        }

        FormCard.FormHeader {
            title: Wrappers.i18n("Mouse wheel")
        }

        FormCard.FormCard {
            FormCard.FormComboBoxDelegate {
                id: cfg_wheelAction
                text: Wrappers.i18n("Scrolling over a task")
                model: [Wrappers.i18n("Does nothing"), Wrappers.i18n("Cycles through all tasks"), Wrappers.i18n("Cycles through all tasks (skip minimized)"), Wrappers.i18n("Cycles through tasks of the current group"), Wrappers.i18n("Cycles through tasks of the current group (skip minimized)"), Wrappers.i18n("Adjusts volume of the window")]
                currentIndex: behaviorPage.cfg_wheelAction
                onActivated: index => {
                    behaviorPage.cfg_wheelAction = index;
                    if (index === 5 && behaviorPage.cfg_wheelCtrlAction === 5) {
                        behaviorPage.cfg_wheelCtrlAction = 0;
                    }
                }
            }

            FormCard.FormDelegateSeparator {
                visible: wheelShiftSystemVolume.visible
            }

            // Shift option for the main action
            FormCard.FormSwitchDelegate {
                id: wheelShiftSystemVolume
                visible: cfg_wheelAction.currentIndex === 5
                text: Wrappers.i18n("Adjust system volume with Shift key")
                checked: behaviorPage.cfg_wheelShiftSystemVolumeEnabled
                onToggled: behaviorPage.cfg_wheelShiftSystemVolumeEnabled = checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: cfg_wheelCtrlActionEnabled
                text: Wrappers.i18n("Additional action with Ctrl key")
                checked: behaviorPage.cfg_wheelCtrlActionEnabled
                onToggled: behaviorPage.cfg_wheelCtrlActionEnabled = checked
            }

            FormCard.FormDelegateSeparator {
                visible: cfg_wheelCtrlAction.visible
            }

            // Ctrl sub-options: every action except the one already on the plain wheel
            FormCard.FormComboBoxDelegate {
                id: cfg_wheelCtrlAction
                visible: cfg_wheelCtrlActionEnabled.checked
                text: Wrappers.i18n("Ctrl + mouse wheel")
                model: {
                    const fullModel = cfg_wheelAction.model;
                    const filtered = [];
                    for (let i = 0; i < fullModel.length; i++) {
                        if (i !== cfg_wheelAction.currentIndex) {
                            filtered.push({
                                text: fullModel[i],
                                originalIndex: i
                            });
                        }
                    }
                    return filtered;
                }
                textRole: "text"
                currentIndex: {
                    for (let i = 0; i < model.length; i++) {
                        if (model[i].originalIndex === behaviorPage.cfg_wheelCtrlAction)
                            return i;
                    }
                    return 0;
                }
                onActivated: index => behaviorPage.cfg_wheelCtrlAction = model[index].originalIndex
            }

            FormCard.FormDelegateSeparator {
                visible: wheelCtrlShiftSystemVolume.visible
            }

            FormCard.FormSwitchDelegate {
                id: wheelCtrlShiftSystemVolume
                visible: cfg_wheelCtrlAction.visible && cfg_wheelCtrlAction.model[cfg_wheelCtrlAction.currentIndex]?.originalIndex === 5
                text: Wrappers.i18n("Adjust system volume with Shift key")
                checked: behaviorPage.cfg_wheelShiftSystemVolumeEnabled
                onToggled: behaviorPage.cfg_wheelShiftSystemVolumeEnabled = checked
            }
        }

        FormCard.FormHeader {
            title: Wrappers.i18n("Tooltips")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: enableToolTips
                text: Wrappers.i18n("Show tooltips when hovering over task buttons")
                checked: behaviorPage.cfg_enableToolTips
                onToggled: behaviorPage.cfg_enableToolTips = checked
            }

            FormCard.FormDelegateSeparator {
                visible: enableToolTips.checked
            }

            FormCard.FormSwitchDelegate {
                id: showToolTips
                visible: enableToolTips.checked
                text: Wrappers.i18n("Show window thumbnails in tooltips")
                checked: behaviorPage.cfg_showToolTips
                onToggled: behaviorPage.cfg_showToolTips = checked
            }

            FormCard.FormDelegateSeparator {
                visible: enableToolTips.checked
            }

            FormCard.FormSpinBoxDelegate {
                visible: enableToolTips.checked
                label: Wrappers.i18n("Tooltip delay (ms)")
                from: 0
                to: 2000
                stepSize: 50
                value: behaviorPage.cfg_tooltipDelay
                // Only on user edits: on load the delegate may clamp before the binding settles
                onValueModified: behaviorPage.cfg_tooltipDelay = value
            }

            FormCard.FormDelegateSeparator {
                visible: tooltipRecentFirst.visible
            }

            FormCard.FormSwitchDelegate {
                id: tooltipRecentFirst
                // Only grouped tooltips have several windows to order
                visible: enableToolTips.checked && behaviorPage.cfg_groupingStrategy !== 0
                text: Wrappers.i18n("List most recently used windows first")
                checked: behaviorPage.cfg_tooltipRecentFirst
                onToggled: behaviorPage.cfg_tooltipRecentFirst = checked
            }

            FormCard.FormDelegateSeparator {
                visible: enableToolTips.checked
            }

            FormCard.FormSwitchDelegate {
                id: highlightWindows
                visible: enableToolTips.checked
                text: Wrappers.i18n("Hide other windows when hovering over a window in the tooltip")
                checked: behaviorPage.cfg_highlightWindows
                onToggled: behaviorPage.cfg_highlightWindows = checked
            }

            FormCard.FormDelegateSeparator {
                visible: enableToolTips.checked
            }

            FormCard.FormSwitchDelegate {
                id: showMediaControls
                visible: enableToolTips.checked
                text: Wrappers.i18n("Show media controls")
                checked: behaviorPage.cfg_showMediaControls
                onToggled: behaviorPage.cfg_showMediaControls = checked
            }

            FormCard.FormDelegateSeparator {
                visible: cfg_mediaControlsLocation.visible
            }

            FormCard.FormComboBoxDelegate {
                id: cfg_mediaControlsLocation
                visible: enableToolTips.checked && showToolTips.checked && showMediaControls.checked
                text: Wrappers.i18n("Media controls location")
                model: [Wrappers.i18n("On thumbnails (Overlay)"), Wrappers.i18n("Under thumbnails")]
                currentIndex: behaviorPage.cfg_mediaControlsLocation
                onActivated: index => behaviorPage.cfg_mediaControlsLocation = index
            }
        }

        FormCard.FormHeader {
            title: Wrappers.i18n("Show only tasks")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: cfg_showOnlyCurrentScreen
                text: Wrappers.i18n("From current screen")
                checked: behaviorPage.cfg_showOnlyCurrentScreen
                onToggled: behaviorPage.cfg_showOnlyCurrentScreen = checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: cfg_showOnlyCurrentDesktop
                text: Wrappers.i18n("From current desktop")
                checked: behaviorPage.cfg_showOnlyCurrentDesktop
                onToggled: behaviorPage.cfg_showOnlyCurrentDesktop = checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: cfg_showOnlyCurrentActivity
                text: Wrappers.i18n("From current activity")
                checked: behaviorPage.cfg_showOnlyCurrentActivity
                onToggled: behaviorPage.cfg_showOnlyCurrentActivity = checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: cfg_reverseFilters
                text: Wrappers.i18n("Invert selected filters")
                description: Wrappers.i18n("Hide matching tasks instead of showing them.")
                checked: behaviorPage.cfg_reverseFilters
                enabled: cfg_showOnlyCurrentScreen.checked || cfg_showOnlyCurrentDesktop.checked || cfg_showOnlyCurrentActivity.checked
                onToggled: behaviorPage.cfg_reverseFilters = checked
            }
        }

        FormCard.FormHeader {
            title: Wrappers.i18n("Window state")
        }

        FormCard.FormCard {
            ButtonGroup {
                id: minimizedFilterButtonGroup
            }

            FormCard.FormRadioDelegate {
                checked: behaviorPage.cfg_minimizedFilter === 0
                text: Wrappers.i18n("In any state")
                ButtonGroup.group: minimizedFilterButtonGroup
                onToggled: if (checked)
                    behaviorPage.cfg_minimizedFilter = 0
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormRadioDelegate {
                checked: behaviorPage.cfg_minimizedFilter === 1
                text: Wrappers.i18n("Only minimized")
                ButtonGroup.group: minimizedFilterButtonGroup
                onToggled: if (checked)
                    behaviorPage.cfg_minimizedFilter = 1
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormRadioDelegate {
                checked: behaviorPage.cfg_minimizedFilter === 2
                text: Wrappers.i18n("Only not minimized")
                ButtonGroup.group: minimizedFilterButtonGroup
                onToggled: if (checked)
                    behaviorPage.cfg_minimizedFilter = 2
            }
        }
    }

    // Remove an app from both grouping blocklists (the context menu adds it to both)
    function allowGrouping(appId) {
        behaviorPage.cfg_groupingAppIdBlacklist = (behaviorPage.cfg_groupingAppIdBlacklist || []).filter(id => id !== appId);
        // Compare the launcher's desktop file name (e.g. applications:org.kde.konsole.desktop
        // or file:///.../org.kde.konsole.desktop) with the app id, not a substring of the URL
        const launcherId = url => decodeURIComponent(String(url)).replace(/^[a-z]+:(\/\/)?/, "").split("/").pop().replace(/\.desktop$/, "");
        behaviorPage.cfg_groupingLauncherUrlBlacklist = (behaviorPage.cfg_groupingLauncherUrlBlacklist || []).filter(url => launcherId(url) !== appId);
    }
}
