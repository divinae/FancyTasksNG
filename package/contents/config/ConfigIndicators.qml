/*
    SPDX-FileCopyrightText: 2025-2026 Vitaliy Elin <daydve@smbit.pro>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigamiaddons.formcard as FormCard

import "../ui/code/singletones"

ConfigPage {
    id: indicatorsPage

    // Silence KCM errors for legacy/removed properties
    readonly property bool plasmaPaAvailable: true

    readonly property bool isLineStyle: indicatorsPage.cfg_indicatorStyle === 0

    readonly property bool indicatorsOn: indicatorsPage.cfg_indicatorsEnabled
    readonly property bool resizeOn: indicatorsPage.indicatorsOn && indicatorsPage.cfg_indicatorResize
    readonly property bool progressOn: indicatorsPage.cfg_indicatorProgressStyle > 0

    ConfigFormPage {
        cfg_page: indicatorsPage

        // ---- Indicators ----------------------------------------------------
        FormCard.FormHeader {
            title: Wrappers.i18n("Active application indicators")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                text: Wrappers.i18nc("State", "Enabled")
                description: Wrappers.i18n("Marks under the task buttons of running applications.")
                checked: indicatorsPage.cfg_indicatorsEnabled
                onToggled: indicatorsPage.cfg_indicatorsEnabled = checked
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.indicatorsOn }

            FormCard.FormSwitchDelegate {
                visible: indicatorsPage.indicatorsOn
                text: Wrappers.i18n("Animate indicators")
                checked: indicatorsPage.cfg_indicatorsAnimated
                onToggled: indicatorsPage.cfg_indicatorsAnimated = checked
            }
        }

        // ---- Style ---------------------------------------------------------
        FormCard.FormHeader {
            visible: indicatorsPage.indicatorsOn
            title: Wrappers.i18n("Style")
        }

        FormCard.FormCard {
            visible: indicatorsPage.indicatorsOn

            FormCard.FormComboBoxDelegate {
                text: Wrappers.i18n("Style")
                model: [
                    Wrappers.i18n("Line"),
                    Wrappers.i18n("Dashes")
                ]
                currentIndex: indicatorsPage.cfg_indicatorStyle
                onActivated: (index) => indicatorsPage.cfg_indicatorStyle = index
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Override indicator location")
                checked: indicatorsPage.cfg_indicatorOverride
                onToggled: indicatorsPage.cfg_indicatorOverride = checked
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.cfg_indicatorOverride }

            FormCard.FormComboBoxDelegate {
                visible: indicatorsPage.cfg_indicatorOverride
                text: Wrappers.i18n("Location")
                model: [
                    Wrappers.i18n("Bottom"),
                    Wrappers.i18n("Left"),
                    Wrappers.i18n("Right"),
                    Wrappers.i18n("Top")
                ]
                currentIndex: indicatorsPage.cfg_indicatorLocation
                onActivated: (index) => indicatorsPage.cfg_indicatorLocation = index
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSpinBoxDelegate {
                label: Wrappers.i18n("Edge offset (px)")
                from: 0
                to: 999
                value: indicatorsPage.cfg_indicatorEdgeOffset
                onValueModified: indicatorsPage.cfg_indicatorEdgeOffset = value
            }
        }

        // ---- Size ----------------------------------------------------------
        FormCard.FormHeader {
            visible: indicatorsPage.indicatorsOn
            title: Wrappers.i18n("Size")
        }

        FormCard.FormCard {
            visible: indicatorsPage.indicatorsOn

            FormCard.FormSpinBoxDelegate {
                label: Wrappers.i18n("Thickness (px)")
                from: 1
                to: 999
                value: indicatorsPage.cfg_indicatorSize
                onValueModified: indicatorsPage.cfg_indicatorSize = value
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSpinBoxDelegate {
                label: Wrappers.i18n("Segment length (px)")
                from: 1
                to: 999
                value: indicatorsPage.cfg_indicatorLength
                onValueModified: indicatorsPage.cfg_indicatorLength = value
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSpinBoxDelegate {
                label: Wrappers.i18n("Roundness (%)")
                from: 0
                to: 100
                value: indicatorsPage.cfg_indicatorRadius
                onValueModified: indicatorsPage.cfg_indicatorRadius = value
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.isLineStyle }

            FormCard.FormSpinBoxDelegate {
                visible: indicatorsPage.isLineStyle
                label: Wrappers.i18n("Side padding (px)")
                from: 0
                to: 999
                value: indicatorsPage.cfg_indicatorShrink
                onValueModified: indicatorsPage.cfg_indicatorShrink = value
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSpinBoxDelegate {
                label: Wrappers.i18n("Max segments")
                from: 1
                to: 99
                value: indicatorsPage.cfg_indicatorMaxLimit
                onValueModified: indicatorsPage.cfg_indicatorMaxLimit = value
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Show '+' on overflow")
                checked: indicatorsPage.cfg_indicatorShowPlus
                onToggled: indicatorsPage.cfg_indicatorShowPlus = checked
            }
        }

        // ---- Activation and hover -------------------------------------------
        FormCard.FormHeader {
            visible: indicatorsPage.indicatorsOn
            title: Wrappers.i18n("Activation and hover")
        }

        FormCard.FormCard {
            visible: indicatorsPage.indicatorsOn

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Resize indicators on activation/hover")
                checked: indicatorsPage.cfg_indicatorResize
                onToggled: indicatorsPage.cfg_indicatorResize = checked
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.resizeOn }

            FormCard.FormSpinBoxDelegate {
                visible: indicatorsPage.resizeOn
                label: Wrappers.i18n("Active thickness (px)")
                from: 1
                to: 999
                value: indicatorsPage.cfg_indicatorActiveSize
                onValueModified: indicatorsPage.cfg_indicatorActiveSize = value
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.resizeOn }

            FormCard.FormSpinBoxDelegate {
                visible: indicatorsPage.resizeOn
                label: Wrappers.i18n("Active length (px)")
                from: 1
                to: 999
                value: indicatorsPage.cfg_indicatorActiveLength
                onValueModified: indicatorsPage.cfg_indicatorActiveLength = value
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.resizeOn }

            FormCard.FormComboBoxDelegate {
                visible: indicatorsPage.resizeOn
                text: Wrappers.i18n("Segment alignment")
                model: {
                    let isVertical = indicatorsPage.cfg_indicatorOverride ?
                        (indicatorsPage.cfg_indicatorLocation === 1 || indicatorsPage.cfg_indicatorLocation === 2) :
                        (indicatorsPage.plasmoidLocation === PlasmaCore.Types.LeftEdge || indicatorsPage.plasmoidLocation === PlasmaCore.Types.RightEdge);

                    return isVertical ? [
                        Wrappers.i18n("Align Left"),
                        Wrappers.i18n("Align Center"),
                        Wrappers.i18n("Align Right")
                    ] : [
                        Wrappers.i18n("Align Top"),
                        Wrappers.i18n("Align Center"),
                        Wrappers.i18n("Align Bottom")
                    ];
                }
                currentIndex: indicatorsPage.cfg_indicatorAlignment
                onActivated: (index) => indicatorsPage.cfg_indicatorAlignment = index
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.resizeOn }

            FormCard.FormSwitchDelegate {
                visible: indicatorsPage.resizeOn
                text: Wrappers.i18n("Separate settings for hovered indicators")
                checked: indicatorsPage.cfg_indicatorHoverSeparate
                onToggled: indicatorsPage.cfg_indicatorHoverSeparate = checked
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.resizeOn && indicatorsPage.cfg_indicatorHoverSeparate }

            FormCard.FormSpinBoxDelegate {
                visible: indicatorsPage.resizeOn && indicatorsPage.cfg_indicatorHoverSeparate
                label: Wrappers.i18n("Hovered thickness (px)")
                from: 1
                to: 999
                value: indicatorsPage.cfg_indicatorHoverSize
                onValueModified: indicatorsPage.cfg_indicatorHoverSize = value
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.resizeOn && indicatorsPage.cfg_indicatorHoverSeparate }

            FormCard.FormSpinBoxDelegate {
                visible: indicatorsPage.resizeOn && indicatorsPage.cfg_indicatorHoverSeparate
                label: Wrappers.i18n("Hovered length (px)")
                from: 1
                to: 999
                value: indicatorsPage.cfg_indicatorHoverLength
                onValueModified: indicatorsPage.cfg_indicatorHoverLength = value
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.resizeOn }

            FormCard.FormSwitchDelegate {
                visible: indicatorsPage.resizeOn
                text: Wrappers.i18n("Separate settings for group indicators")
                checked: indicatorsPage.cfg_indicatorGroupSeparate
                onToggled: indicatorsPage.cfg_indicatorGroupSeparate = checked
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.resizeOn && indicatorsPage.cfg_indicatorGroupSeparate }

            FormCard.FormSpinBoxDelegate {
                visible: indicatorsPage.resizeOn && indicatorsPage.cfg_indicatorGroupSeparate
                label: Wrappers.i18n("Group thickness (px)")
                from: 1
                to: 999
                value: indicatorsPage.cfg_indicatorGroupSize
                onValueModified: indicatorsPage.cfg_indicatorGroupSize = value
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.resizeOn && indicatorsPage.cfg_indicatorGroupSeparate }

            FormCard.FormSpinBoxDelegate {
                visible: indicatorsPage.resizeOn && indicatorsPage.cfg_indicatorGroupSeparate
                label: Wrappers.i18n("Group length (px)")
                from: 1
                to: 999
                value: indicatorsPage.cfg_indicatorGroupLength
                onValueModified: indicatorsPage.cfg_indicatorGroupLength = value
            }
        }

        // ---- Colors --------------------------------------------------------
        FormCard.FormHeader {
            visible: indicatorsPage.indicatorsOn
            title: Wrappers.i18n("Colors")
        }

        FormCard.FormCard {
            visible: indicatorsPage.indicatorsOn

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Use plasma accent color")
                checked: indicatorsPage.cfg_indicatorAccentColor
                onToggled: indicatorsPage.cfg_indicatorAccentColor = checked
            }

            FormCard.FormDelegateSeparator { visible: !indicatorsPage.cfg_indicatorAccentColor }

            FormCard.FormSwitchDelegate {
                visible: !indicatorsPage.cfg_indicatorAccentColor
                text: Wrappers.i18n("Use theme text color")
                description: Wrappers.i18n("Dark on light themes, light on dark themes.")
                checked: indicatorsPage.cfg_indicatorTextColor
                onToggled: indicatorsPage.cfg_indicatorTextColor = checked
            }

            FormCard.FormDelegateSeparator { visible: !indicatorsPage.cfg_indicatorAccentColor && !indicatorsPage.cfg_indicatorTextColor }

            FormCard.FormSwitchDelegate {
                visible: !indicatorsPage.cfg_indicatorAccentColor && !indicatorsPage.cfg_indicatorTextColor
                text: Wrappers.i18n("Use dominant icon color")
                checked: indicatorsPage.cfg_indicatorDominantColor
                onToggled: indicatorsPage.cfg_indicatorDominantColor = checked
            }

            FormCard.FormDelegateSeparator {
                visible: !indicatorsPage.cfg_indicatorAccentColor && !indicatorsPage.cfg_indicatorTextColor && !indicatorsPage.cfg_indicatorDominantColor
            }

            FormColorDelegate {
                visible: !indicatorsPage.cfg_indicatorAccentColor && !indicatorsPage.cfg_indicatorTextColor && !indicatorsPage.cfg_indicatorDominantColor
                label: Wrappers.i18n("Custom color")
                showAlphaChannel: true
                color: indicatorsPage.cfg_indicatorCustomColor
                onColorPicked: c => indicatorsPage.cfg_indicatorCustomColor = c
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Use the attention color when a window wants attention")
                checked: indicatorsPage.cfg_indicatorAttentionColor
                onToggled: indicatorsPage.cfg_indicatorAttentionColor = checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Outline for contrast")
                checked: indicatorsPage.cfg_indicatorOutline
                onToggled: indicatorsPage.cfg_indicatorOutline = checked
            }
        }

        // ---- Behavior ------------------------------------------------------
        FormCard.FormHeader {
            visible: indicatorsPage.indicatorsOn
            title: Wrappers.i18n("Behavior")
        }

        FormCard.FormCard {
            visible: indicatorsPage.indicatorsOn

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Highlight active window in group")
                checked: indicatorsPage.cfg_indicatorHighlightActive
                onToggled: indicatorsPage.cfg_indicatorHighlightActive = checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSpinBoxDelegate {
                label: Wrappers.i18n("Focused indicator opacity (%)")
                from: 10
                to: 100
                stepSize: 5
                value: indicatorsPage.cfg_indicatorActiveOpacity
                onValueModified: indicatorsPage.cfg_indicatorActiveOpacity = value
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Dim inactive indicators")
                checked: indicatorsPage.cfg_indicatorDimInactive
                onToggled: indicatorsPage.cfg_indicatorDimInactive = checked
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.cfg_indicatorDimInactive }

            FormCard.FormSpinBoxDelegate {
                visible: indicatorsPage.cfg_indicatorDimInactive
                label: Wrappers.i18n("Inactive indicator opacity (%)")
                from: 0
                to: 100
                stepSize: 5
                value: indicatorsPage.cfg_indicatorInactiveOpacity
                onValueModified: indicatorsPage.cfg_indicatorInactiveOpacity = value
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Desaturate when minimized")
                checked: indicatorsPage.cfg_indicatorDesaturate
                onToggled: indicatorsPage.cfg_indicatorDesaturate = checked
            }
        }

        // ---- Badges --------------------------------------------------------
        FormCard.FormHeader {
            title: Wrappers.i18n("Badges")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Show badges")
                checked: indicatorsPage.cfg_showBadges
                onToggled: indicatorsPage.cfg_showBadges = checked
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.cfg_showBadges }

            FormCard.FormSwitchDelegate {
                visible: indicatorsPage.cfg_showBadges
                text: Wrappers.i18n("Highlight new notifications")
                checked: indicatorsPage.cfg_badgeHighlightNew
                onToggled: indicatorsPage.cfg_badgeHighlightNew = checked
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.cfg_showBadges }

            FormCard.FormSwitchDelegate {
                visible: indicatorsPage.cfg_showBadges
                text: Wrappers.i18n("Show badges on pinned application icons")
                description: Wrappers.i18n("Show counters even when the application has no windows in the current view (e.g., minimized to tray or on another screen/desktop/activity).")
                checked: indicatorsPage.cfg_showBadgesOnLaunchers
                onToggled: indicatorsPage.cfg_showBadgesOnLaunchers = checked
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.cfg_showBadges }

            FormCard.FormComboBoxDelegate {
                visible: indicatorsPage.cfg_showBadges
                text: Wrappers.i18n("Badge background color")
                model: [
                    Wrappers.i18n("Adaptive (theme color)"),
                    Wrappers.i18n("Fixed red (Classic)"),
                    Wrappers.i18n("System accent color"),
                    Wrappers.i18n("Custom color")
                ]
                currentIndex: indicatorsPage.cfg_badgeColorMode
                onActivated: (index) => indicatorsPage.cfg_badgeColorMode = index
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.cfg_showBadges && indicatorsPage.cfg_badgeColorMode === 3 }

            FormColorDelegate {
                visible: indicatorsPage.cfg_showBadges && indicatorsPage.cfg_badgeColorMode === 3
                label: Wrappers.i18n("Custom badge color")
                showAlphaChannel: true
                color: indicatorsPage.cfg_badgeCustomColor
                onColorPicked: c => indicatorsPage.cfg_badgeCustomColor = c
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Show the number of windows on apps with several windows")
                checked: indicatorsPage.cfg_showWindowCount
                onToggled: indicatorsPage.cfg_showWindowCount = checked
            }
        }

        // ---- Audio ---------------------------------------------------------
        FormCard.FormHeader {
            visible: indicatorsPage.plasmaPaAvailable
            title: Wrappers.i18n("Audio")
        }

        FormCard.FormCard {
            visible: indicatorsPage.plasmaPaAvailable

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Mark applications playing audio")
                checked: indicatorsPage.cfg_indicateAudioStreams
                onToggled: indicatorsPage.cfg_indicateAudioStreams = checked
            }
        }

        // ---- Progress ------------------------------------------------------
        FormCard.FormHeader {
            title: Wrappers.i18n("Progress")
        }

        FormCard.FormCard {
            FormCard.FormComboBoxDelegate {
                text: Wrappers.i18n("Progress style")
                model: [
                    Wrappers.i18nc("State", "Disabled"),
                    Wrappers.i18n("Fill (Left-Right)"),
                    Wrappers.i18n("Fill (Bottom-Top)"),
                    Wrappers.i18n("Strip (Top)"),
                    Wrappers.i18n("Strip (Bottom)"),
                    Wrappers.i18n("Strip (Left)"),
                    Wrappers.i18n("Strip (Right)")
                ]
                currentIndex: indicatorsPage.cfg_indicatorProgressStyle
                onActivated: (index) => indicatorsPage.cfg_indicatorProgressStyle = index
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.progressOn }

            FormCard.FormSwitchDelegate {
                visible: indicatorsPage.progressOn
                text: Wrappers.i18n("Use theme accent color for progress")
                checked: indicatorsPage.cfg_indicatorProgressThemeColor
                onToggled: indicatorsPage.cfg_indicatorProgressThemeColor = checked
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.progressOn && !indicatorsPage.cfg_indicatorProgressThemeColor }

            FormColorDelegate {
                visible: indicatorsPage.progressOn && !indicatorsPage.cfg_indicatorProgressThemeColor
                label: Wrappers.i18n("Progress color")
                showAlphaChannel: true
                color: indicatorsPage.cfg_indicatorProgressColor
                onColorPicked: c => indicatorsPage.cfg_indicatorProgressColor = c
            }

            // Thickness only applies to the strip styles
            FormCard.FormDelegateSeparator { visible: indicatorsPage.cfg_indicatorProgressStyle >= 3 }

            FormCard.AbstractFormDelegate {
                visible: indicatorsPage.cfg_indicatorProgressStyle >= 3
                background: null
                focusPolicy: Qt.NoFocus

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Label {
                        Layout.fillWidth: true
                        text: Wrappers.i18n("Thickness")
                        elide: Text.ElideRight
                    }
                    Slider {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                        from: 1
                        to: 10
                        stepSize: 1
                        value: indicatorsPage.cfg_indicatorProgressThickness
                        onMoved: indicatorsPage.cfg_indicatorProgressThickness = value
                    }
                    Label {
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 2
                        horizontalAlignment: Text.AlignRight
                        text: Wrappers.i18nc("unit: pixels", "%1 px", indicatorsPage.cfg_indicatorProgressThickness)
                    }
                }
            }

            FormCard.FormDelegateSeparator { visible: indicatorsPage.progressOn }

            FormCard.AbstractFormDelegate {
                visible: indicatorsPage.progressOn
                background: null
                focusPolicy: Qt.NoFocus

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    Label {
                        Layout.fillWidth: true
                        text: Wrappers.i18n("Opacity")
                        elide: Text.ElideRight
                    }
                    Slider {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                        from: 10
                        to: 100
                        stepSize: 5
                        value: indicatorsPage.cfg_indicatorProgressOpacity
                        onMoved: indicatorsPage.cfg_indicatorProgressOpacity = value
                    }
                    Label {
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 2
                        horizontalAlignment: Text.AlignRight
                        text: indicatorsPage.cfg_indicatorProgressOpacity + "%"
                    }
                }
            }
        }
    }
}
