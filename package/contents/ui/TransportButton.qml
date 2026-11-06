/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Previous / play-pause / next button of the media controls; large next to the track text,
// compact without it
PlasmaComponents3.ToolButton {
    property bool large: false

    implicitWidth: Kirigami.Units.gridUnit * (large ? 1.6 : 1.2)
    implicitHeight: Kirigami.Units.gridUnit * (large ? 1.6 : 1.2)
    padding: large ? Kirigami.Units.smallSpacing : 0
    icon.width: large ? Kirigami.Units.iconSizes.smallMedium : Kirigami.Units.iconSizes.small
    icon.height: large ? Kirigami.Units.iconSizes.smallMedium : Kirigami.Units.iconSizes.small
}
