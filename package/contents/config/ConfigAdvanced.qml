/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import Qt.labs.platform as Labs
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigamiaddons.formcard as FormCard

import "../ui/code/singletones"

ConfigPage {
    id: advancedPage
    ConfigFormPage {
        cfg_page: advancedPage

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            visible: DesktopActionsManager.helperError !== ""
            type: Kirigami.MessageType.Warning
            text: Wrappers.i18n("The Taskline helper could not start, so jump lists, recent documents and configuration export/import are unavailable. It needs python3 with the dbus-python and PyGObject modules. Error: %1", DesktopActionsManager.helperError)
        }

        FormCard.FormHeader {
            title: Wrappers.i18n("Floating Mode Settings")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            visible: advancedPage.plasmoidLocation !== PlasmaCore.Types.Floating
            type: Kirigami.MessageType.Information
            text: Wrappers.i18n("This option is disabled when the widget is on a panel.")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: overridePlasmaButtonDirection
                text: Wrappers.i18n("Override system direction")
                enabled: advancedPage.plasmoidLocation === PlasmaCore.Types.Floating
                checked: advancedPage.cfg_overridePlasmaButtonDirection
                onToggled: advancedPage.cfg_overridePlasmaButtonDirection = checked
            }

            FormCard.FormDelegateSeparator {
                visible: plasmaButtonDirection.visible
            }

            FormCard.FormComboBoxDelegate {
                id: plasmaButtonDirection
                text: Wrappers.i18n("Direction")
                enabled: overridePlasmaButtonDirection.enabled && overridePlasmaButtonDirection.checked
                visible: overridePlasmaButtonDirection.checked
                model: [
                    Wrappers.i18n("As on top panel"),
                    Wrappers.i18n("As on bottom panel"),
                    Wrappers.i18n("As on left panel"),
                    Wrappers.i18n("As on right panel")
                ]
                currentIndex: advancedPage.cfg_plasmaButtonDirection
                onActivated: (index) => advancedPage.cfg_plasmaButtonDirection = index
            }
        }

        FormCard.FormHeader {
            title: Wrappers.i18n("When a window wants attention")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: cfg_unhideOnAttention
                text: Wrappers.i18n("Unhide panel when a window wants attention")
                enabled: advancedPage.plasmoidLocation !== PlasmaCore.Types.Floating
                checked: advancedPage.cfg_unhideOnAttention
                onToggled: advancedPage.cfg_unhideOnAttention = checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Instead, peek the app's icon out of the screen edge (for auto-hidden panels)")
                leftPadding: Kirigami.Units.gridUnit * 2
                enabled: advancedPage.plasmoidLocation !== PlasmaCore.Types.Floating
                checked: advancedPage.cfg_attentionPeek
                onToggled: advancedPage.cfg_attentionPeek = checked
            }

            FormCard.FormDelegateSeparator {
                visible: cfg_animateAttentionStatus.visible
            }

            FormCard.FormSwitchDelegate {
                id: cfg_animateAttentionStatus
                text: Wrappers.i18n("Animate task icon when a window wants attention")
                checked: advancedPage.cfg_animateAttentionStatus
                onToggled: advancedPage.cfg_animateAttentionStatus = checked
                visible: advancedPage.cfg_iconOnly === 1
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                text: Wrappers.i18n("Bounce the icon while an application is starting")
                checked: advancedPage.cfg_bounceOnLaunch
                onToggled: advancedPage.cfg_bounceOnLaunch = checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: cfg_attentionCustomColorEnabled
                text: Wrappers.i18n("Colorize the task button when a window wants attention")
                checked: advancedPage.cfg_attentionCustomColorEnabled
                onToggled: advancedPage.cfg_attentionCustomColorEnabled = checked
            }

            FormCard.FormDelegateSeparator {
                visible: attentionCustomColorBtn.visible
            }

            FormColorDelegate {
                id: attentionCustomColorBtn
                visible: advancedPage.cfg_attentionCustomColorEnabled
                label: Wrappers.i18n("Attention color")
                showAlphaChannel: true
                color: advancedPage.cfg_attentionCustomColor
                onColorPicked: c => advancedPage.cfg_attentionCustomColor = c
            }
        }

        FormCard.FormHeader {
            title: Wrappers.i18n("Layout settings")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            visible: advancedPage.plasmoidLocation === PlasmaCore.Types.Floating
            type: Kirigami.MessageType.Information
            text: Wrappers.i18n("These options are only available when the widget is on a panel.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            visible: advancedPage.plasmoidLocation !== PlasmaCore.Types.Floating && !advancedPage.cfg_iconOnly
            type: Kirigami.MessageType.Information
            text: Wrappers.i18n("These options are only available in icon-only mode.")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: fill
                text: Wrappers.i18n("Fill free space on panel")
                enabled: advancedPage.plasmoidLocation !== PlasmaCore.Types.Floating && advancedPage.cfg_iconOnly
                checked: advancedPage.cfg_fill
                onToggled: advancedPage.cfg_fill = checked
            }

            FormCard.FormDelegateSeparator {
                visible: fillAlignment.visible
            }

            FormCard.FormComboBoxDelegate {
                id: fillAlignment
                visible: fill.checked && fill.enabled
                text: Wrappers.i18n("Alignment")
                model: [
                    Wrappers.i18n("Edge"),
                    Wrappers.i18n("Center")
                ]
                currentIndex: advancedPage.cfg_fillAlignment
                onActivated: (index) => advancedPage.cfg_fillAlignment = index
            }
        }

        FormCard.FormHeader {
            title: Wrappers.i18n("Context menu")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: cfg_hideMoveToDesktopMenuWithOneDesktop
                text: Wrappers.i18n("Hide 'Move to Desktop' if only one virtual desktop is used")
                checked: advancedPage.cfg_hideMoveToDesktopMenuWithOneDesktop
                onToggled: advancedPage.cfg_hideMoveToDesktopMenuWithOneDesktop = checked
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormSwitchDelegate {
                id: cfg_showBrowserHistory
                text: Wrappers.i18n("Show browsing history in the context menu of web browsers (Experimental)")
                checked: advancedPage.cfg_showBrowserHistory
                onToggled: advancedPage.cfg_showBrowserHistory = checked
            }

            FormCard.FormDelegateSeparator {
                visible: cfg_browserHistoryLimit.visible
            }

            FormCard.FormSpinBoxDelegate {
                id: cfg_browserHistoryLimit
                visible: cfg_showBrowserHistory.checked
                label: Wrappers.i18n("Number of browser history items")
                from: 1
                to: 50
                value: advancedPage.cfg_browserHistoryLimit
                // Only on user edits: on load the delegate may clamp before the binding settles
                onValueModified: advancedPage.cfg_browserHistoryLimit = value
            }
        }

        FormCard.FormHeader {
            title: Wrappers.i18n("Effects")
        }

        FormCard.FormCard {
            FormCard.FormSwitchDelegate {
                id: cfg_cursorGlow
                text: Wrappers.i18n("Glow following the cursor over task buttons")
                checked: advancedPage.cfg_cursorGlow
                onToggled: advancedPage.cfg_cursorGlow = checked
            }
        }

        FormCard.FormHeader {
            title: Wrappers.i18n("Configuration")
        }

        FormCard.FormCard {
            FormCard.FormButtonDelegate {
                text: Wrappers.i18n("Export Configuration…")
                description: Wrappers.i18n("Save all Taskline settings to a JSON file.")
                icon.name: "document-export"
                onClicked: exportFileDialog.open()
            }

            FormCard.FormDelegateSeparator {}

            FormCard.FormButtonDelegate {
                text: Wrappers.i18n("Import Configuration…")
                description: Wrappers.i18n("Load settings from a JSON file; click Apply to keep them.")
                icon.name: "document-import"
                onClicked: importFileDialog.open()
            }
        }

        Kirigami.InlineMessage {
            id: configIoStatusLabel
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            visible: text.length > 0
            type: configIoIsError ? Kirigami.MessageType.Error : Kirigami.MessageType.Positive

            property bool configIoIsError: false
        }

        Labs.FileDialog {
            id: exportFileDialog
            title: Wrappers.i18n("Export Taskline Configuration")
            fileMode: Labs.FileDialog.SaveFile
            nameFilters: [Wrappers.i18n("JSON files (*.json)")]
            defaultSuffix: "json"
            onAccepted: advancedPage.exportConfig(exportFileDialog.file)
        }

        Labs.FileDialog {
            id: importFileDialog
            title: Wrappers.i18n("Import Taskline Configuration")
            fileMode: Labs.FileDialog.OpenFile
            nameFilters: [Wrappers.i18n("JSON files (*.json)")]
            onAccepted: advancedPage.importConfig(importFileDialog.file)
        }

    }

    readonly property string configAppId: "io.github.divinae.taskline"

    function toLocalPath(fileUrl) {
        return decodeURIComponent(fileUrl.toString().replace(/^file:\/\//, ""));
    }

    function helperUnavailableText() {
        return Wrappers.i18n("The Taskline helper is not running. It needs python3 with the dbus-python and PyGObject modules.");
    }

    function showConfigIoStatus(text, isError) {
        configIoStatusLabel.text = text;
        configIoStatusLabel.configIoIsError = isError;
    }

    function collectConfigForExport() {
        const settings = {};
        const keys = Object.keys(advancedPage.plasmoidConfiguration);
        for (const key of keys) {
            if (key === "expanding" || key === "length") continue;
            const propName = "cfg_" + key;
            if (!(propName in advancedPage)) continue;
            settings[key] = advancedPage[propName];
        }
        return { app: advancedPage.configAppId, version: 1, settings: settings };
    }

    function exportConfig(fileUrl) {
        const path = advancedPage.toLocalPath(fileUrl);
        const payload = JSON.stringify(advancedPage.collectConfigForExport(), null, 2);
        configIoStatusLabel.text = "";
        DesktopActionsManager.exportConfig(path, payload, (result) => {
            if (result === "OK") {
                advancedPage.showConfigIoStatus(Wrappers.i18n("Configuration exported successfully."), false);
            } else if (!DesktopActionsManager.isHelperReply(result)) {
                advancedPage.showConfigIoStatus(advancedPage.helperUnavailableText(), true);
            } else {
                advancedPage.showConfigIoStatus(Wrappers.i18n("Failed to export configuration."), true);
            }
        });
    }

    function importConfig(fileUrl) {
        const path = advancedPage.toLocalPath(fileUrl);
        configIoStatusLabel.text = "";
        DesktopActionsManager.importConfig(path, (result) => {
            if (!DesktopActionsManager.isHelperReply(result)) {
                advancedPage.showConfigIoStatus(advancedPage.helperUnavailableText(), true);
                return;
            }
            if (result.startsWith("ERROR:")) {
                advancedPage.showConfigIoStatus(Wrappers.i18n("Failed to read the configuration file."), true);
                return;
            }
            try {
                advancedPage.applyImportedSettings(JSON.parse(result.slice("OK:".length)));
            } catch (e) {
                advancedPage.showConfigIoStatus(Wrappers.i18n("This file is not a valid Taskline configuration."), true);
            }
        });
    }

    function applyImportedSettings(parsed) {
        // Also accept exports from Fancy Tasks NG, which this widget is a fork of
        const knownApps = [advancedPage.configAppId, "io.github.daydve.fancytasksng"];
        if (!parsed || knownApps.indexOf(parsed.app) === -1 || typeof parsed.settings !== "object") {
            advancedPage.showConfigIoStatus(Wrappers.i18n("This file is not a valid Taskline configuration."), true);
            return;
        }
        const keys = Object.keys(parsed.settings);
        for (const key of keys) {
            const propName = "cfg_" + key;
            if (propName in advancedPage) {
                advancedPage[propName] = parsed.settings[key];
            }
        }
        advancedPage.showConfigIoStatus(Wrappers.i18n("Configuration imported. Click Apply to save the changes."), false);
    }
}
