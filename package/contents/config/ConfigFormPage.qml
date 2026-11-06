/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

// Shared scaffold for a settings page that's just a Live Preview above a
// scrollable column of FormCard cards: ConfigAppearance/Behavior/Indicators/
// Advanced each instantiate this once. Content declared inside a
// `ConfigFormPage { ... }` instance (FormCard.FormHeader, FormCard.FormCard, ...)
// is stacked in the column.
//
// Not used by ConfigPinnedApps.qml, which has its own StackView-based root
// layout - opt-in via explicit instantiation, not a base-class default
// property, so pages with a different root layout are unaffected.
ColumnLayout {
    id: formPage

    required property var cfg_page

    default property alias formContent: pageFormLayout.data

    anchors.fill: parent
    spacing: formPage.cfg_page.largeSpacing

    LivePreview {
        cfg_page: formPage.cfg_page
        location: formPage.cfg_page.plasmoidLocation
        Layout.fillWidth: true
        visible: formPage.cfg_page.plasmoidLocation !== PlasmaCore.Types.Floating
    }

    ConfigScrollView {
        cfg_page: formPage.cfg_page

        // Cards (FormCard.FormHeader + FormCard.FormCard) stacked like a SimpleKCM page,
        // matching the look of other Kirigami Addons based settings
        ColumnLayout {
            id: pageFormLayout
            width: parent.width
            spacing: 0
        }
    }
}
