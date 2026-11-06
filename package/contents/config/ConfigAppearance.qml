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
    id: appearancePage

    readonly property bool plasmoidVertical: appearancePage.plasmoidFormFactor === PlasmaCore.Types.Vertical

    ConfigFormPage {
        cfg_page: appearancePage

        // ---------------------------------------------------------------- Display
        FormCard.FormHeader {
            title: Wrappers.i18n("Display")
        }

        FormCard.FormCard {
            FormCard.FormRadioSelectorDelegate {
                id: displaySelector

                consistentWidth: true
                // The binding only shows the stored mode; the actions write it,
                // so an internal index reset can't overwrite the setting.
                selectedIndex: appearancePage.cfg_iconOnly
                actions: [
                    Kirigami.Action {
                        text: Wrappers.i18n("Classic panel")
                        onTriggered: appearancePage.cfg_iconOnly = 0
                    },
                    Kirigami.Action {
                        text: Wrappers.i18n("Show icons only")
                        onTriggered: appearancePage.cfg_iconOnly = 1
                    }
                ]
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: useBorders
                text: Wrappers.i18n("Use plasma borders")
                checked: appearancePage.cfg_useBorders
                onToggled: appearancePage.cfg_useBorders = checked
            }
        }

        // ---------------------------------------------------------------- Icon size
        FormCard.FormHeader {
            title: Wrappers.i18n("Icon size")
        }

        FormCard.FormCard {
            FormCard.FormComboBoxDelegate {
                id: iconSizeOverrideCombo
                text: Wrappers.i18n("Icon size")
                model: [Wrappers.i18n("Relative"), Wrappers.i18n("Absolute")]
                currentIndex: appearancePage.cfg_iconSizeOverride ? 1 : 0
                onActivated: (index) => appearancePage.cfg_iconSizeOverride = (index === 1)
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSliderDelegate {
                id: iconScale
                visible: !appearancePage.cfg_iconSizeOverride
                label: Wrappers.i18n("Icon scale")
                from: 0
                to: 300
                stepSize: 1.0
                value: appearancePage.cfg_iconScale
                onMoved: appearancePage.cfg_iconScale = value

                trailing: RowLayout {
                    spacing: appearancePage.smallSpacing

                    SpinBox {
                        id: iconScaleSpin
                        from: 0
                        to: 300
                        editable: true
                        value: Math.round(appearancePage.cfg_iconScale)
                        onValueModified: appearancePage.cfg_iconScale = value
                    }

                    Label {
                        text: "%"
                    }

                    Button {
                        icon.name: "edit-reset"
                        flat: true
                        onClicked: appearancePage.cfg_iconScale = 100
                        ToolTip.text: Wrappers.i18n("Reset to default")
                        ToolTip.visible: hovered
                        ToolTip.delay: 1000
                    }
                }
            }

            FormCard.FormSliderDelegate {
                id: iconSizePx
                visible: appearancePage.cfg_iconSizeOverride
                label: Wrappers.i18n("Icon size (px)")
                from: 0
                to: 100
                stepSize: 1
                value: appearancePage.cfg_iconSizePx
                onMoved: appearancePage.cfg_iconSizePx = value

                trailing: RowLayout {
                    spacing: appearancePage.smallSpacing

                    SpinBox {
                        id: iconSizePxSpin
                        from: 0
                        to: 100
                        editable: true
                        value: appearancePage.cfg_iconSizePx
                        onValueModified: appearancePage.cfg_iconSizePx = value
                    }

                    Label {
                        text: Wrappers.i18nc("unit: pixels", "px")
                    }

                    Button {
                        icon.name: "edit-reset"
                        flat: true
                        onClicked: appearancePage.cfg_iconSizePx = 32
                        ToolTip.text: Wrappers.i18n("Reset to default")
                        ToolTip.visible: hovered
                        ToolTip.delay: 1000
                    }
                }
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: iconScaleFromEdge
                text: Wrappers.i18n("Scale icons from panel edge")
                checked: appearancePage.cfg_iconScaleFromEdge
                onToggled: appearancePage.cfg_iconScaleFromEdge = checked
            }

            FormCard.FormDelegateSeparator {
                visible: iconEdgeOffset.visible
            }

            FormCard.FormSpinBoxDelegate {
                id: iconEdgeOffset
                visible: iconScaleFromEdge.checked
                label: Wrappers.i18n("Edge offset (px)")
                from: 0
                to: 15
                stepSize: 1
                value: appearancePage.cfg_iconEdgeOffset
                onValueModified: appearancePage.cfg_iconEdgeOffset = value
            }
        }

        // ---------------------------------------------------------------- Hover effects (icons only)
        FormCard.FormHeader {
            visible: appearancePage.cfg_iconOnly === 1
            title: Wrappers.i18n("Hover effects")
        }

        FormCard.FormCard {
            visible: appearancePage.cfg_iconOnly === 1

            FormCard.FormSwitchDelegate {
                id: cfg_taskHoverEffect
                text: Wrappers.i18n("Icon hover effects")
                checked: appearancePage.cfg_taskHoverEffect
                onToggled: appearancePage.cfg_taskHoverEffect = checked
            }

            FormCard.FormDelegateSeparator {
                visible: cfg_taskHoverEffect.checked
            }

            FormCard.FormComboBoxDelegate {
                id: cfg_taskHoverEffectStyle
                visible: appearancePage.cfg_iconOnly === 1 && cfg_taskHoverEffect.checked
                text: Wrappers.i18n("Hover style")
                model: [
                    Wrappers.i18n("Simple"),
                    Wrappers.i18n("Parabolic")
                ]
                currentIndex: appearancePage.cfg_taskHoverEffectStyle
                onActivated: (index) => appearancePage.cfg_taskHoverEffectStyle = index
            }

            FormCard.FormDelegateSeparator {
                visible: cfg_taskHoverEffect.checked
            }

            FormCard.FormSpinBoxDelegate {
                id: iconZoomFactor
                visible: appearancePage.cfg_iconOnly === 1 && cfg_taskHoverEffect.checked
                label: Wrappers.i18n("Icon zoom factor (px)")
                description: Wrappers.i18n("How much the icon should grow when hovered (in pixels)")
                from: 0
                to: 50
                stepSize: 1
                value: appearancePage.cfg_iconZoomFactor
                onValueModified: appearancePage.cfg_iconZoomFactor = value
            }

            FormCard.FormDelegateSeparator {
                visible: cfg_taskHoverEffect.checked
            }

            FormCard.FormSpinBoxDelegate {
                id: iconZoomDuration
                visible: appearancePage.cfg_iconOnly === 1 && cfg_taskHoverEffect.checked
                label: Wrappers.i18n("Zoom animation duration (ms)")
                description: Wrappers.i18n("Duration of the zoom animation in milliseconds")
                from: 0
                to: 1000
                stepSize: 50
                value: appearancePage.cfg_iconZoomDuration
                onValueModified: appearancePage.cfg_iconZoomDuration = value
            }
        }

        // ---------------------------------------------------------------- Button background
        FormCard.FormHeader {
            title: Wrappers.i18n("Button background")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: cfg_disableButtonSvg
                text: Wrappers.i18n("Disable plasma context decorations")
                checked: appearancePage.cfg_disableButtonSvg
                onToggled: appearancePage.cfg_disableButtonSvg = checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormComboBoxDelegate {
                id: buttonColorCombo
                text: Wrappers.i18n("Button colors")
                enabled: !cfg_disableButtonSvg.checked
                model: [
                    Wrappers.i18n("Using Plasma Style/Accent"),
                    Wrappers.i18n("Use dominant icon color"),
                    Wrappers.i18n("Custom color")
                ]
                currentIndex: {
                    if (!appearancePage.cfg_buttonColorize) return 0;
                    if (appearancePage.cfg_buttonColorizeDominant) return 1;
                    return 2;
                }
                onActivated: index => {
                    if (index === 0) {
                        appearancePage.cfg_buttonColorize = false;
                        appearancePage.cfg_buttonColorizeDominant = false;
                    } else if (index === 1) {
                        appearancePage.cfg_buttonColorize = true;
                        appearancePage.cfg_buttonColorizeDominant = true;
                    } else if (index === 2) {
                        appearancePage.cfg_buttonColorize = true;
                        appearancePage.cfg_buttonColorizeDominant = false;
                    }
                }
            }

            FormCard.FormDelegateSeparator {
                visible: cfg_buttonColorizeCustom.visible
            }

            FormColorDelegate {
                id: cfg_buttonColorizeCustom
                label: Wrappers.i18n("Custom color")
                showAlphaChannel: true
                enabled: !cfg_disableButtonSvg.checked
                visible: appearancePage.cfg_buttonColorize && !appearancePage.cfg_buttonColorizeDominant
                color: appearancePage.cfg_buttonColorizeCustom
                onColorPicked: c => appearancePage.cfg_buttonColorizeCustom = c
            }
        }

        // ---------------------------------------------------------------- Inactive buttons
        FormCard.FormHeader {
            title: Wrappers.i18n("Inactive buttons")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: cfg_disableButtonInactiveSvg
                text: Wrappers.i18n("Hide backgrounds for inactive buttons")
                enabled: !cfg_disableButtonSvg.checked
                checked: appearancePage.cfg_disableButtonInactiveSvg
                onToggled: appearancePage.cfg_disableButtonInactiveSvg = checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: cfg_buttonColorizeInactive
                text: Wrappers.i18n("Colorize inactive buttons")
                enabled: !cfg_disableButtonSvg.checked && appearancePage.cfg_buttonColorize && !cfg_disableButtonInactiveSvg.checked
                checked: appearancePage.cfg_buttonColorizeInactive
                onToggled: appearancePage.cfg_buttonColorizeInactive = checked
            }
        }

        // ---------------------------------------------------------------- Button size and spacing
        FormCard.FormHeader {
            title: Wrappers.i18n("Button size and spacing")
        }

        FormCard.FormCard {
            FormCard.FormSpinBoxDelegate {
                id: maxButtonLength
                visible: appearancePage.cfg_iconOnly === 0 && !appearancePage.plasmoidVertical
                label: Wrappers.i18n("Maximum button width (px)")
                from: 40
                to: 1000
                value: appearancePage.cfg_maxButtonLength
                onValueModified: appearancePage.cfg_maxButtonLength = value
            }

            FormCard.FormDelegateSeparator {
                visible: maxButtonLength.visible
            }

            FormCard.FormSpinBoxDelegate {
                id: maxTextLines
                visible: appearancePage.cfg_iconOnly === 0
                label: Wrappers.i18n("Maximum lines of text in a button")
                from: 0
                to: 5
                value: appearancePage.cfg_maxTextLines
                onValueModified: appearancePage.cfg_maxTextLines = value
                textFromValue: (value, locale) => value === 0 ? Wrappers.i18nc("Maximum lines of text", "No limit") : value.toString()
                valueFromText: (text, locale) => parseInt(text) || 0
            }

            FormCard.FormDelegateSeparator {
                visible: maxTextLines.visible
            }

            FormCard.FormSwitchDelegate {
                id: fitButtonToText
                visible: appearancePage.cfg_iconOnly === 0 && !appearancePage.plasmoidVertical
                text: Wrappers.i18n("Fit button width to its title")
                checked: appearancePage.cfg_fitButtonToText
                onToggled: appearancePage.cfg_fitButtonToText = checked
            }

            FormCard.FormDelegateSeparator {
                visible: fitButtonToText.visible
            }

            FormCard.FormSpinBoxDelegate {
                id: minFitButtonLength
                visible: fitButtonToText.visible
                enabled: fitButtonToText.checked
                label: Wrappers.i18n("Minimum button width (px)")
                from: 40
                to: 1000
                value: appearancePage.cfg_minFitButtonLength
                onValueModified: appearancePage.cfg_minFitButtonLength = value
            }

            FormCard.FormDelegateSeparator {
                visible: minFitButtonLength.visible
            }

            FormCard.FormSpinBoxDelegate {
                id: taskSpacingSize
                label: Wrappers.i18n("Space between taskbar items (px)")
                from: 0
                to: 99
                value: appearancePage.cfg_taskSpacingSize
                onValueModified: appearancePage.cfg_taskSpacingSize = value
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormComboBoxDelegate {
                id: iconSpacingCombo
                visible: !appearancePage.tabletMode
                text: Wrappers.i18n("Inner padding")
                model: [
                    {
                        "label": Wrappers.i18n("Small"),
                        "spacing": 0
                    },
                    {
                        "label": Wrappers.i18n("Normal"),
                        "spacing": 1
                    },
                    {
                        "label": Wrappers.i18n("Large"),
                        "spacing": 2
                    },
                    {
                        "label": Wrappers.i18n("Huge"),
                        "spacing": 3
                    },
                ]
                textRole: "label"

                currentIndex: {
                    if (appearancePage.tabletMode) {
                        return 3; // Large
                    }

                    switch (appearancePage.cfg_iconSpacing) {
                    case 0:
                        return 0; // Small
                    case 1:
                        return 1; // Normal
                    case 2:
                        return 2; // Medium
                    case 3:
                        return 3; // Large
                    }
                }
                onActivated: index => {
                    appearancePage.cfg_iconSpacing = model[index]["spacing"];
                }
            }

            FormCard.FormTextDelegate {
                visible: appearancePage.tabletMode
                text: Wrappers.i18n("Inner padding")
                description: Wrappers.i18n("Automatically set to Large when in Touch mode")
            }
        }

        // ---------------------------------------------------------------- Icon shape
        FormCard.FormHeader {
            title: Wrappers.i18n("Icon shape")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: clipIconToShape
                text: Wrappers.i18n("Clip icons to a custom shape")
                checked: appearancePage.cfg_clipIconToShape
                onToggled: appearancePage.cfg_clipIconToShape = checked
            }

            FormCard.FormDelegateSeparator {
                visible: appearancePage.cfg_clipIconToShape
            }

            FormCard.FormSliderDelegate {
                id: iconClipRadiusSlider
                visible: appearancePage.cfg_clipIconToShape
                label: Wrappers.i18n("Icon corner radius")
                from: 0
                to: 100
                stepSize: 1
                value: appearancePage.cfg_iconClipRadius
                onMoved: appearancePage.cfg_iconClipRadius = value

                trailing: SpinBox {
                    id: iconClipRadiusSpin
                    from: 0
                    to: 100
                    editable: true
                    value: appearancePage.cfg_iconClipRadius
                    onValueModified: appearancePage.cfg_iconClipRadius = value
                    textFromValue: function(value, locale) { return value + "%" }
                    valueFromText: function(text, locale) { return parseInt(text) }
                }
            }

            FormCard.FormDelegateSeparator {
                visible: appearancePage.cfg_clipIconToShape
            }

            FormCard.FormSwitchDelegate {
                id: clipIconBackgroundEnabled
                visible: appearancePage.cfg_clipIconToShape
                text: Wrappers.i18n("Show background under clipped icons")
                checked: appearancePage.cfg_clipIconBackgroundEnabled
                onToggled: appearancePage.cfg_clipIconBackgroundEnabled = checked
            }

            FormCard.FormDelegateSeparator {
                visible: cfg_clipIconBackgroundColorMode.visible
            }

            FormCard.FormComboBoxDelegate {
                id: cfg_clipIconBackgroundColorMode
                visible: appearancePage.cfg_clipIconToShape && appearancePage.cfg_clipIconBackgroundEnabled
                text: Wrappers.i18n("Background color source")
                model: [
                    Wrappers.i18n("Custom color"),
                    Wrappers.i18n("Dominant icon color"),
                    Wrappers.i18n("Average icon color"),
                    Wrappers.i18n("Plasma accent color")
                ]
                currentIndex: appearancePage.cfg_clipIconBackgroundColorMode
                onActivated: (index) => appearancePage.cfg_clipIconBackgroundColorMode = index
            }

            FormCard.FormDelegateSeparator {
                visible: clipIconBackgroundColorBtn.visible
            }

            FormColorDelegate {
                id: clipIconBackgroundColorBtn
                visible: cfg_clipIconBackgroundColorMode.visible && appearancePage.cfg_clipIconBackgroundColorMode === 0
                label: Wrappers.i18n("Custom color")
                showAlphaChannel: true
                color: appearancePage.cfg_clipIconBackgroundColor
                onColorPicked: c => appearancePage.cfg_clipIconBackgroundColor = c
            }

            FormCard.FormDelegateSeparator {
                visible: clipIconBackgroundOpacitySlider.visible
            }

            FormCard.FormSliderDelegate {
                id: clipIconBackgroundOpacitySlider
                visible: appearancePage.cfg_clipIconToShape && appearancePage.cfg_clipIconBackgroundEnabled
                label: Wrappers.i18n("Background opacity")
                from: 0
                to: 100
                stepSize: 5
                value: appearancePage.cfg_clipIconBackgroundOpacity
                onMoved: appearancePage.cfg_clipIconBackgroundOpacity = value

                trailing: SpinBox {
                    id: clipIconBackgroundOpacitySpin
                    from: 0
                    to: 100
                    editable: true
                    value: appearancePage.cfg_clipIconBackgroundOpacity
                    onValueModified: appearancePage.cfg_clipIconBackgroundOpacity = value
                    textFromValue: function(value, locale) { return value + "%" }
                    valueFromText: function(text, locale) { return parseInt(text) }
                }
            }
        }

        // ---------------------------------------------------------------- Multi-row view
        FormCard.FormHeader {
            title: appearancePage.plasmoidVertical ? Wrappers.i18n("Use multi-column view") : Wrappers.i18n("Use multi-row view")
        }

        FormCard.FormCard {
            FormCard.FormRadioDelegate {
                id: forbidStripes
                text: Wrappers.i18n("Never")
                checked: appearancePage.cfg_maxStripes === 1
                onToggled: {
                    if (checked) {
                        appearancePage.cfg_maxStripes = 1;
                    }
                }
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormRadioDelegate {
                id: allowStripes
                text: Wrappers.i18n("When panel is low on space and thick enough")
                checked: appearancePage.cfg_maxStripes > 1 && !appearancePage.cfg_forceStripes
                onToggled: {
                    if (checked) {
                        appearancePage.cfg_maxStripes = Math.max(2, appearancePage.cfg_maxStripes);
                        appearancePage.cfg_forceStripes = false;
                    }
                }
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormRadioDelegate {
                id: forceStripes
                text: Wrappers.i18n("Always when panel is thick enough")
                checked: appearancePage.cfg_maxStripes > 1 && appearancePage.cfg_forceStripes
                onToggled: {
                    if (checked) {
                        appearancePage.cfg_maxStripes = Math.max(2, appearancePage.cfg_maxStripes);
                        appearancePage.cfg_forceStripes = true;
                    }
                }
            }

            FormCard.FormDelegateSeparator {
                visible: maxStripes.visible
            }

            FormCard.FormSpinBoxDelegate {
                id: maxStripes
                visible: appearancePage.cfg_maxStripes > 1
                label: appearancePage.plasmoidVertical ? Wrappers.i18n("Maximum columns") : Wrappers.i18n("Maximum rows")
                from: 1
                value: appearancePage.cfg_maxStripes
                onValueModified: appearancePage.cfg_maxStripes = value
            }
        }
    }
}
