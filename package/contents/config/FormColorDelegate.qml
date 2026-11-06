/*
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import org.kde.kirigamiaddons.formcard as FormCard

// A FormCard row with a label (and optional description) and a color button,
// for the color settings of the config pages.
FormCard.AbstractFormDelegate {
    id: delegate

    property string label: ""
    property string description: ""
    property alias color: colorButton.color
    property alias showAlphaChannel: colorButton.showAlphaChannel
    // Emitted when the user picks a color (not on external changes to `color`)
    signal colorPicked(color color)

    background: null
    focusPolicy: Qt.NoFocus

    contentItem: RowLayout {
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                text: delegate.label
                elide: Text.ElideRight
                enabled: delegate.enabled
            }
            QQC2.Label {
                Layout.fillWidth: true
                visible: delegate.description.length > 0
                text: delegate.description
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
            }
        }

        KQuickControls.ColorButton {
            id: colorButton
            enabled: delegate.enabled
            onAccepted: color => delegate.colorPicked(color)
        }
    }
}
