/*
    SPDX-FileCopyrightText: 2025-2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-FileCopyrightText: 2025 SushiTrash <strash137@gmail.com>
    SPDX-FileCopyrightText: 2023-2024 Fushan Wen <qydwhotmail@gmail.com>
    SPDX-FileCopyrightText: 2024 Vlad Zahorodnii <vlad.zahorodnii@kde.org>
    SPDX-FileCopyrightText: 2024 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2020-2023 Nate Graham <nate@kde.org>
    SPDX-FileCopyrightText: 2022-2023 Alexandra <alexankitty@gmail.com>
    SPDX-FileCopyrightText: 2023 Akseli Lahtinen <akselmo@akselmo.dev>
    SPDX-FileCopyrightText: 2023 Marco Martin <notmart@gmail.com>
    SPDX-FileCopyrightText: 2023 Niccolò Venerandi <niccolo@venerandi.com>
    SPDX-FileCopyrightText: 2017 Roman Gilg <subdiff@gmail.com>
    SPDX-FileCopyrightText: 2016 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2014 Martin Gräßlin <mgraesslin@kde.org>
    SPDX-FileCopyrightText: 2013 Sebastian Kügler <sebas@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

import "code/singletones"
import "code/tools.js" as TaskTools

Item {
    id: root
    
    // Cached configuration property for optimization
    readonly property var config: Plasmoid.configuration

    // Cached delegate properties for performance optimization
    readonly property bool showThumbnails: toolTipDelegate ? toolTipDelegate.showThumbnails : false
    readonly property bool isWin: toolTipDelegate ? toolTipDelegate.isWin : false
    readonly property bool isGroup: toolTipDelegate ? toolTipDelegate.isGroup : false
    readonly property var parentTask: toolTipDelegate ? toolTipDelegate.parentTask : null
    readonly property bool isLauncher: toolTipDelegate ? toolTipDelegate.isLauncher : false
    readonly property var icon: toolTipDelegate ? toolTipDelegate.icon : null
    readonly property var thumbnailCache: toolTipDelegate ? toolTipDelegate.thumbnailCache : null
    readonly property int tooltipInstanceMaximumWidth: toolTipDelegate ? toolTipDelegate.tooltipInstanceMaximumWidth : Kirigami.Units.gridUnit * 14

    implicitWidth: mainLayout.implicitWidth
    implicitHeight: mainLayout.implicitHeight

    readonly property alias isHovered: rootHover.hovered

    required property var toolTipDelegate
    required property var tasksModel
    property var mpris2Model

    property var explicitWinId: undefined
    readonly property var currentWinId: explicitWinId !== undefined ? explicitWinId : (toolTipDelegate.windows && root.index < toolTipDelegate.windows.length ? toolTipDelegate.windows[root.index] : undefined)
    
    property var audioStreamManager
    

    readonly property bool useOverlayStyle: root.showThumbnails

    HoverHandler {
        id: rootHover
    }

    PlasmaExtras.Highlight {
        anchors.fill: parent
        anchors.margins: -Kirigami.Units.smallSpacing / 2
        visible: (root.isHovered || (root.isGroup && isWindowActive)) && !root.showThumbnails
        opacity: root.isHovered ? 1.0 : (isWindowActive ? 0.6 : 0.0)

        pressed: (rootHover.item as MouseArea)?.containsPress ?? false
        hovered: true
        z: -1
    }

    // Mouse Interaction for Text Mode (when thumbnails hidden)
    Loader {
        anchors.fill: parent
        active: !root.showThumbnails && root.isWin
        sourceComponent: ToolTipWindowMouseArea {
            rootTask: root.parentTask
            modelIndex: root.submodelIndex
            winId: root.currentWinId
            globalHovered: rootHover.hovered
            tasksModel: root.tasksModel
            toolTipDelegate: root.toolTipDelegate
        }
    }

    required property int index
    required property var submodelIndex
    required property int appPid
    property string appId: ""
    required property string display
    required property bool isMinimized
    required property bool isWindowActive
    required property bool isOnAllVirtualDesktops
    required property var virtualDesktops
    required property list<string> activities

    readonly property string calculatedAppName: {
        let name = "";
        if (toolTipDelegate.appName && toolTipDelegate.appName.length > 0) {
            name = toolTipDelegate.appName;
        } else {
            const text = display;
            const versionRegex = /\s+(?:—|-|–)\s+([^\s(—|-|–)]+)\s+(?:—|-|–)\s+v?\d+(?:\.\d+)+.*$/i;
            const matchVersion = text.match(versionRegex);
            if (matchVersion && matchVersion[1]) {
                name = matchVersion[1];
            } else {
                const lastSepRegex = /.*(?:—|-|–)\s+(.*)$/;
                const matchLast = text.match(lastSepRegex);
                if (matchLast && matchLast[1]) {
                    name = matchLast[1];
                }
            }
        }

        return name;
    }

    readonly property string title: {
        if (!root.isWin) {
            return toolTipDelegate.genericName;
        }

        let text = display;
        if (root.isGroup && text === "") {
            return "";
        }

        let counter = "";
        const counterMatch = text.match(/\s*<\d+>$/);
        if (counterMatch) {
            counter = counterMatch[0];
            text = text.replace(/\s*<\d+>$/, "");
        }

        const appName = root.calculatedAppName;
        if (appName && appName.length > 0) {
            const escapedAppName = appName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            const cleanupRegex = new RegExp(`\\s+(?:—|-|–)\\s+${escapedAppName}.*$`, "i");

            if (text.match(cleanupRegex)) {
                text = text.replace(cleanupRegex, "");
            } else {
                 const greedyMatch = text.match(/.*(?=\s+(—|-|–))/);
                 if (greedyMatch) {
                     text = greedyMatch[0];
                 }
            }
        } else {
            const greedyMatch = text.match(/.*(?=\s+(—|-|–))/);
            if (greedyMatch) {
                text = greedyMatch[0];
            }
        }

        if (text === "") {
            text = "—";
        }

        return text + counter;
    }
    required property bool isPlayingAudio
    required property bool isMuted

    // Media Controller Loader
    Loader {
        id: mediaControllerLoader
        // Lazy load the backend media controller only when media controls are enabled in settings
        active: root.config && root.config.showMediaControls
        sourceComponent: ToolTipMediaController {
            toolTipDelegate: root.toolTipDelegate
            appPid: root.appPid
            appId: root.appId
            title: root.title
            audioStreamManager: root.audioStreamManager
            mpris2Model: root.mpris2Model
            index: root.index
            thumbnailWinId: root.currentWinId
            isPlayingAudio: root.isPlayingAudio
        }
    }

    readonly property var mediaController: mediaControllerLoader.item

    // Bridge Properties to maintain full compatibility with visual overlays and controllers
    readonly property var playerData: mediaController ? mediaController.playerData : null
    readonly property bool titleIncludesTrack: mediaController ? mediaController.titleIncludesTrack : false
    

    readonly property bool controlsAreEffective: mediaController ? mediaController.controlsAreEffective : false
    property bool delayedControlsActive: false
    
    onControlsAreEffectiveChanged: {
        if (controlsAreEffective) {
            controlsHideTimer.stop();
            delayedControlsActive = true;
        } else {
            controlsHideTimer.restart();
        }
    }
    
    Timer {
        id: controlsHideTimer
        interval: 1000
        repeat: false
        onTriggered: delayedControlsActive = false
    }


    PlasmaExtras.Highlight {
        anchors.fill: parent
        anchors.margins: -Kirigami.Units.smallSpacing / 2
        visible: root.isGroup && root.isHovered && !root.showThumbnails
        pressed: (rootHover.item as MouseArea)?.containsPress ?? false
        hovered: true
        z: -1
    }

    ColumnLayout {
        id: mainLayout
        width: parent.width
        spacing: Kirigami.Units.smallSpacing


        Layout.margins: 0
    
    RowLayout {
        id: header
        visible: !root.useOverlayStyle
        Layout.preferredHeight: implicitHeight // Ensure height propagates to root
        spacing: Kirigami.Units.smallSpacing

        Layout.maximumWidth: root.tooltipInstanceMaximumWidth
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
        Layout.margins: root.showThumbnails ? Kirigami.Units.mediumSpacing : Kirigami.Units.smallSpacing
        Layout.fillWidth: true

        Kirigami.Icon {
            source: root.icon
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            Layout.alignment: Qt.AlignVCenter
            visible: !root.showThumbnails && root.isWin
        }

        ColumnLayout {
            spacing: 0
            
            Layout.fillWidth: true
            Layout.preferredWidth: 0 
            Layout.minimumWidth: 0 

            Kirigami.Heading {
                id: appNameHeading
                level: 3
                maximumLineCount: 1
                lineHeight: 1
                
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                
                text: root.calculatedAppName

                opacity: 1
                visible: text.length !== 0 && root.showThumbnails
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignLeft
            }
            PlasmaComponents3.Label {
                id: winTitle
                maximumLineCount: 1
                
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                
                text: root.showThumbnails ? (root.titleIncludesTrack ? "" : root.title) : root.display
                opacity: root.showThumbnails ? 0.75 : 1.0
                horizontalAlignment: Text.AlignLeft
                visible: text.length !== 0
                textFormat: Text.PlainText
            }
            PlasmaComponents3.Label {
                id: subtext
                maximumLineCount: 2
                
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                
                text: toolTipDelegate.isWin ? root.generateSubText() : ""
                opacity: 0.6
                horizontalAlignment: Text.AlignLeft
                visible: root.showThumbnails && text.length !== 0 && text !== appNameHeading.text
                textFormat: Text.PlainText
            }
        }



        PlasmaComponents3.ToolButton {
            id: closeButton
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            visible: root.isWin && (root.showThumbnails || root.isHovered)
            icon.name: "window-close"
            icon.width: !root.showThumbnails ? Kirigami.Units.iconSizes.small : undefined
            icon.height: !root.showThumbnails ? Kirigami.Units.iconSizes.small : undefined
            onClicked: {
                if (root.parentTask && root.parentTask.tasksRoot) {
                    root.parentTask.tasksRoot.cancelHighlightWindows();
                }
                const targetIndex = root.findMatchingTaskIndex();
                tasksModel.requestClose(targetIndex);
            }
        }
    }

    // LIST MEDIA CONTROLS (Only visible in Text Mode)
    Loader {
        id: textModeControlsLoader
        Layout.fillWidth: true
        Layout.maximumWidth: root.tooltipInstanceMaximumWidth
        Layout.topMargin: -Kirigami.Units.smallSpacing // Tighter spacing to header
        
        active: !root.showThumbnails && (root.controlsAreEffective || root.delayedControlsActive)
        visible: active
        
        sourceComponent: ToolTipMediaControls {
            mediaController: root.mediaController
        }
    }

    Item {
        id: thumbnailSourceItem

        readonly property int targetWidth: root.tooltipInstanceMaximumWidth
        readonly property int targetHeight: Math.round(targetWidth / (toolTipDelegate ? toolTipDelegate.thumbnailAspectRatio : 16 / 10))

        Layout.preferredWidth: root.showThumbnails ? targetWidth : 0
        Layout.preferredHeight: root.showThumbnails ? targetHeight : 0

        Layout.alignment: Qt.AlignCenter
        clip: false
        
        visible: root.isWin && root.config.showToolTips && root.showThumbnails

        readonly property bool thumbnailAreaHovered: thumbnailHoverHandler.hovered

        HoverHandler {
            id: thumbnailHoverHandler
        }

        PlasmaExtras.Highlight {
            id: thumbnailHighlight
            anchors.fill: hoverHandler

            // Use opacity for smooth transition matching the player controls
            opacity: thumbnailSourceItem.thumbnailAreaHovered ? 1.0 : ((root.isGroup && isWindowActive) ? 0.6 : 0.0)
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }
            
            visible: opacity > 0 // Optimization
            
            pressed: (hoverHandler.item as MouseArea)?.containsPress ?? false
            hovered: true
        }

        readonly property bool showIcon: Qt.platform.pluginName === "wayland" || root.isMinimized || (pipeWireLoader.item !== null && pipeWireLoader.item !== undefined)

        Loader {
            id: thumbnailLoader
            active: root.showThumbnails && !root.isLauncher && !albumArtImage.visible && (Number.isInteger(root.currentWinId) || pipeWireLoader.item && !pipeWireLoader.item.hasThumbnail) && root.index !== -1
            asynchronous: true
            
            visible: active
            
            anchors.fill: hoverHandler
            // Keep the thumbnail inside the highlight frame so it doesn't cover its outline and rounded corners
            anchors.margins: Math.max(Kirigami.Units.smallSpacing,
                thumbnailHighlight.marginHints.left, thumbnailHighlight.marginHints.top,
                thumbnailHighlight.marginHints.right, thumbnailHighlight.marginHints.bottom)

            source: thumbnailLoader.active && !thumbnailSourceItem.showIcon ? "X11Thumbnail.qml" : ""
            sourceComponent: thumbnailLoader.active && thumbnailSourceItem.showIcon ? iconItem : null

            Binding {
                target: (thumbnailLoader.item && String(thumbnailLoader.source).indexOf("X11Thumbnail.qml") !== -1) ? thumbnailLoader.item : null
                property: "winId"
                value: Number.isInteger(root.currentWinId) ? root.currentWinId : 0
            }

            Component {
                id: iconItem
                Kirigami.Icon {
                    id: realIconItem
                    source: root.icon
                    animated: false
                    visible: valid
                    
                    // Avoid flashing the fallback while the PipeWire stream starts normally.
                    property bool thumbnailReady: pipeWireLoader.active && pipeWireLoader.item && pipeWireLoader.item.hasThumbnail
                    property bool fallbackDelayElapsed: false
                    opacity: thumbnailReady || !fallbackDelayElapsed ? 0 : 1
                    
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit 

                    // Smooth fade out when thumbnail appears
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Kirigami.Units.longDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    Timer {
                        interval: Kirigami.Units.humanMoment
                        running: !realIconItem.thumbnailReady && !realIconItem.fallbackDelayElapsed
                        onTriggered: realIconItem.fallbackDelayElapsed = true
                    }

                    Connections {
                        target: root
                        function onCurrentWinIdChanged(): void {
                            realIconItem.fallbackDelayElapsed = false;
                        }
                    }
                }
            }
        }

        Loader {
            id: pipeWireLoader
            anchors.fill: hoverHandler
            anchors.margins: thumbnailLoader.anchors.margins

            active: root.showThumbnails && !root.isLauncher && !albumArtImage.visible && Qt.platform.pluginName === "wayland" && root.index !== -1
            asynchronous: true
            source: "PipeWireThumbnail.qml"

            Binding {
                target: pipeWireLoader.item
                property: "winId"
                value: root.currentWinId
            }

            Timer {
                id: captureTimer
                interval: 400 
                repeat: false
                running: pipeWireLoader.status === Loader.Ready 
                         && pipeWireLoader.item 
                         && pipeWireLoader.item.hasThumbnail
                         && root.currentWinId !== undefined
                
                onTriggered: {
                    if (pipeWireLoader.item) {
                        if (pipeWireLoader.item.width <= 0 || pipeWireLoader.item.height <= 0) return;
                        pipeWireLoader.item.grabToImage(function(result) {
                            if (result && root.currentWinId) {
                                tasks.cacheThumbnail(root.currentWinId, result);
                            }
                        }, Qt.size(pipeWireLoader.item.width, pipeWireLoader.item.height));
                    }
                }
            }
        }
        
        // Placeholder image showing the cached thumbnail while the live stream initializes
        Image {
             id: cachedThumbnail
             anchors.fill: hoverHandler
             anchors.margins: thumbnailLoader.anchors.margins
             
             // Access .url from the stored { result, stamp } cache entry; stale entries (>TTL) are ignored
             source: {
                 const entry = root.currentWinId ? root.thumbnailCache[root.currentWinId] : null;
                 if (!entry) return "";
                 if (Date.now() - entry.stamp > root.thumbnailCacheTtlMs) return "";
                 return entry.result.url;
             }
             
             readonly property bool liveThumbnailReady: pipeWireLoader.active && pipeWireLoader.item && pipeWireLoader.item.hasThumbnail
             
             visible: !liveThumbnailReady && status === Image.Ready
             
             asynchronous: false
             fillMode: Image.PreserveAspectFit
             cache: false
        }

        Loader {
            active: albumArtImage.visible && albumArtImage.status === Image.Ready && root.index !== -1 
            asynchronous: true
            visible: active
            anchors.centerIn: hoverHandler

            sourceComponent: Item { 
                 id: albumArtBackground
                 readonly property Image source: albumArtImage
            }
        }

        Image {
            id: albumArtImage
            readonly property bool available: (status === Image.Ready || status === Image.Loading) && (!(toolTipDelegate.isGroup || /firefox|chrome|chromium|opera|vivaldi|brave|edge|konqueror/i.test(toolTipDelegate.launcherUrl.toString())) || root.titleIncludesTrack)

            anchors.fill: hoverHandler
            anchors.margins: Kirigami.Units.smallSpacing
            sourceSize: Qt.size(parent.width, parent.height)

            asynchronous: true
            source: root.playerData?.artUrl ?? ""
            fillMode: Image.PreserveAspectFit
            visible: available
        }

        Loader {
            id: hoverHandler
            active: root.index !== -1
            anchors.fill: parent
            sourceComponent: ToolTipWindowMouseArea {
                rootTask: root.parentTask
                modelIndex: root.submodelIndex
                winId: root.currentWinId
                globalHovered: rootHover.hovered
                tasksModel: root.tasksModel
                toolTipDelegate: root.toolTipDelegate
            }
        }

        // Overlay Media Controls (Ghost Controls)
        Loader {
            id: overlayControlsLoader
            active: root.showThumbnails && root.config.mediaControlsLocation === 0 && (root.controlsAreEffective || root.delayedControlsActive)
            visible: active
            
            z: 2002 
            
            anchors.bottom: hoverHandler.bottom
            anchors.horizontalCenter: hoverHandler.horizontalCenter
            anchors.margins: Kirigami.Units.smallSpacing
            width: hoverHandler.width - (anchors.margins * 2)
            
            sourceComponent: ToolTipMediaOverlay {
                mediaController: root.mediaController
                hoveredState: thumbnailSourceItem.thumbnailAreaHovered
            }
        }

        // Title Overlay (Top-Left)
        Item {
            id: titleOverlayContainer
            z: 9999
            visible: root.useOverlayStyle && root.isWin && titleOverlayLabel.text.length > 0
            
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: Kirigami.Units.smallSpacing
            
            // Dynamic Sizing Logic
            readonly property int maxOverlayWidth: parent.width - (closeButtonOverlay.visible ? closeButtonOverlay.width : 0) - Kirigami.Units.largeSpacing
            
            // Padding Constants
            readonly property int hPadding: Kirigami.Units.largeSpacing
            readonly property int vPadding: Kirigami.Units.smallSpacing
            
            // Calculate width based on text content + padding, capped at max
            width: Math.min(titleOverlayLabel.implicitWidth + hPadding * 2, maxOverlayWidth)
            height: titleOverlayLabel.implicitHeight + vPadding * 2
            
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.55)
                radius: Kirigami.Units.cornerRadius
            }
            
            // Text Layer
            PlasmaComponents3.Label {
                id: titleOverlayLabel
                anchors.centerIn: parent
                // Ensure text wraps/elides within the container minus padding
                width: parent.width - parent.hPadding * 2
                
                text: {
                    if (root.titleIncludesTrack) return ""; 

                    let titleText = root.title;
                    
                    // Strip shortcuts like "{Meta+1}"
                    // Regex: Space (optional) + { + anything + } + End
                    titleText = titleText.replace(/\s*\{[^\}]*\}\s*$/, "");
                    
                    // Check redundancy
                    let appName = root.calculatedAppName;
                    if (appName && titleText.toLowerCase() === appName.toLowerCase()) {
                        return ""; // Hide if redundant
                    }
                    
                    if (!titleText && root.display !== appName) {
                          // Fallback to display only if it's not also redundant
                          titleText = root.display;
                          if (titleText && titleText.toLowerCase() === appName.toLowerCase()) return "";
                    }

                    return titleText || ""; 
                }
                
                elide: Text.ElideRight
                // Always light: drawn on a dark scrim over window content
                color: "white"
            }
        }

        // Close Button Overlay (Top-Right)
        PlasmaComponents3.ToolButton {
            id: closeButtonOverlay
            z: 2003
            // Only shown while the mouse is over this window's tile
            opacity: rootHover.hovered ? 1 : 0
            visible: root.useOverlayStyle && root.isWin && opacity > 0
            Behavior on opacity {
                NumberAnimation { duration: Kirigami.Units.shortDuration }
            }

            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Kirigami.Units.smallSpacing

            icon.name: "window-close"
            icon.width: Kirigami.Units.iconSizes.smallMedium
            icon.height: Kirigami.Units.iconSizes.smallMedium
            display: PlasmaComponents3.AbstractButton.IconOnly

            width: height
            // Default flat ToolButton background: nothing until hovered, like stock tooltips

            onClicked: {
                if (root.parentTask && root.parentTask.tasksRoot) {
                    root.parentTask.tasksRoot.cancelHighlightWindows();
                }
                const targetIndex = root.findMatchingTaskIndex();
                tasksModel.requestClose(targetIndex);
            }
        }
    }

    // UNDER-THUMBNAIL MEDIA BAR
    Loader {
        id: mediaBarLoader
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: -Kirigami.Units.smallSpacing // Tighter padding

        active: root.showThumbnails && root.config.mediaControlsLocation === 1 && (root.controlsAreEffective || root.delayedControlsActive)
        visible: active

        sourceComponent: ToolTipMediaBar {
            mediaController: root.mediaController
        }
    }
}

    function generateSubText(): string {
        return TaskTools.locationSubTextEntries(Wrappers.i18nc, root.config, virtualDesktopInfo, activityInfo,
            virtualDesktops, isOnAllVirtualDesktops, activities).join("\n");
    }

    // Used so the close button closes the right window in a group
    function findMatchingTaskIndex() {
        return TaskTools.childIndexForWindow(tasksModel, root.parentTask, root.currentWinId) || submodelIndex;
    }
}
