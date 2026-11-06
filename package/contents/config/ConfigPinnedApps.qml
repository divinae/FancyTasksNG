/*
    SPDX-FileCopyrightText: 2025-2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-FileCopyrightText: 2025 SushiTrash <strash137@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kirigamiaddons.formcard as FormCard

import org.kde.plasma.plasma5support as P5Support

import "../ui/code/singletones"

ConfigPage {
    id: cfg_page

    property var pinnedLaunchers: cfg_page.cfg_launchers
    onPinnedLaunchersChanged: {
        refreshPinnedAppsModel();
    }
    property bool appsLoaded: false
    property bool initialLoadDone: false
    property bool isLoadingApps: false
    property var appMetadataCache: ({})
    property string currentSearchText: ""

    // ---------------------------------------
    // Unified Style Configuration
    // ---------------------------------------
    QtObject {
        id: appListStyle
        property int iconSize: Kirigami.Units.iconSizes.medium
        property int spacing: cfg_page.smallSpacing
        property int padding: cfg_page.smallSpacing
    }

    // ---------------------------------------

    function cleanUrl(url) {
        // Handle [activity-id] prefix often found in Plasma config
        // e.g. "[uuid] applications:foo.desktop"
        if (url.startsWith("[")) {
            const closingBracket = url.indexOf("]");
            if (closingBracket !== -1) {
                // Return the part after "] " (usually 2 chars, checking simply for applications:)
                // But it might have spaces.
                // Let's rely on finding "applications:"
                const appIndex = url.indexOf("applications:");
                if (appIndex !== -1) {
                    return url.substring(appIndex);
                }
            }
        }
        return url;
    }

    // "foo.desktop" for an "applications:foo.desktop" launcher URL, null for any other URL
    function launcherSource(url) {
        return url.startsWith("applications:") ? url.substring("applications:".length) : null;
    }

    // The built-in "preferred://" launchers
    readonly property var preferredApps: ({
        "preferred://browser": {
            name: Wrappers.i18n("Default Web Browser"),
            comment: Wrappers.i18n("Browse the Web"),
            icon: "internet-web-browser"
        },
        "preferred://filemanager": {
            name: Wrappers.i18n("Default File Manager"),
            comment: Wrappers.i18n("Manage Files"),
            icon: "system-file-manager"
        },
        "preferred://mail": {
            name: Wrappers.i18n("Default Mail Client"),
            comment: Wrappers.i18n("Send and Receive Email"),
            icon: "internet-mail"
        }
    })

    // Initial app loading timer
    Timer {
        id: initialLoadTimer
        interval: 200
        repeat: false
        onTriggered: {
            cfg_page.isLoadingApps = true;
            cfg_page.loadInstalledApps();
        }
    }

    // App loading data source
    P5Support.DataSource {
        id: appsSource
        engine: "apps"
        connectedSources: ["apps"]
        interval: 0

        property var requestedSources: ({})

        onSourceConnected: (source) => {
            // Data usually comes later in onNewData, but sometimes it's immediate if cached.
            // If data is already present, process it.
            if (source === "apps") {
                cfg_page.startBatchProcessing();
                return;
            }
            if (appsSource.data[source] !== undefined) {
                 cfg_page.processAppSource(source, appsSource.data[source]);
            }
        }

        onNewData: (source, data) => {
            if (source === "apps") {
                 cfg_page.startBatchProcessing();
                 return;
            }
            cfg_page.processAppSource(source, data);
        }
    }

    ListModel {
        id: installedAppsModel
    }

    ListModel {
        id: filteredAppsModel
    }

    function loadInstalledApps() {
        // Add default special launchers
        if (installedAppsModel.count === 0) {
            installedAppsModel.append({
                name: Wrappers.i18n("Default Web Browser"),
                icon: "internet-web-browser",
                url: "preferred://browser",
                keywords: "web browser internet"
            });
            installedAppsModel.append({
                name: Wrappers.i18n("Default File Manager"),
                icon: "system-file-manager",
                url: "preferred://filemanager",
                keywords: "files folder"
            });
            installedAppsModel.append({
                name: Wrappers.i18n("Default Mail Client"),
                icon: "internet-mail",
                url: "preferred://mail",
                keywords: "email mail"
            });
        }

        // Start loading by connecting to "apps" list source
        isLoadingApps = true;
        // Connecting to "apps" source will trigger onNewData/onSourceConnected when ready
        // which will then call startBatchProcessing()
        appsSource.connectSource("apps");
    }

    function startBatchProcessing() {
        // Create a prioritized list of desktop files
        const desktopFiles = [];
        const commonPrefixes = ["firefox", "chromium", "chrome", "brave", "dolphin", "konsole", "kate", "gnome-terminal", "org.kde"];
        
        // Build set of pinned sources for O(1) lookup
        const pinnedSources = new Set();
        for (let i = 0; i < pinnedLaunchers.length; i++) {
            const src = launcherSource(cleanUrl(pinnedLaunchers[i]));
            if (src !== null) {
                pinnedSources.add(src);
                
                // Explicitly add pinned apps to the processing list, even if not in appsSource.sources
                // This ensures .local apps are requested
                desktopFiles.push({
                    source: src,
                    priority: -1 // Highest priority
                });
            }
        }

        // Add other available sources
        for (let i = 0; i < appsSource.sources.length; i++) {
            const source = appsSource.sources[i];
            // Skip if already added (pinned apps are handled above)
            // Or just check if source is valid desktop file
            if (source !== "apps" && source.endsWith(".desktop")) {
                if (pinnedSources.has(source)) continue; // Already added

                let priority = 1000;
                const sourceLower = source.toLowerCase();

                // Check if it's a commonly used app
                for (let j = 0; j < commonPrefixes.length; j++) {
                    if (sourceLower.includes(commonPrefixes[j])) {
                        priority = j;
                        break;
                    }
                }

                desktopFiles.push({
                    source: source,
                    priority: priority
                });
            }
        }

        // Sort by priority
        desktopFiles.sort((a, b) => a.priority - b.priority);

        // Process in batches
        let processedCount = 0;
        function processBatch() {
            const batchSize = 15;
            const end = Math.min(processedCount + batchSize, desktopFiles.length);

            for (let i = processedCount; i < end; i++) {
                const item = desktopFiles[i];
                const source = item.source;
                // Only connect if not already requested or pinned (pinned forces request sometimes)
                if (!appsSource.requestedSources[source]) {
                    appsSource.connectSource(source);
                    appsSource.requestedSources[source] = true;
                }
            }

            processedCount = end;
            if (processedCount < desktopFiles.length) {
                // Schedule next batch
                Qt.callLater(processBatch);
            } else {
                // All batches scheduled
                isLoadingApps = false;
                appsLoaded = true;
                // Once loaded, refresh pinned apps to ensure metadata is caught up
                refreshPinnedAppsModel();
            }
        }

        // Start processing
        processBatch();
    }

    function processAppSource(source, data) {
        if (source === "apps" || !source.endsWith(".desktop")) {
            return;
        }

        if (!data) {
             // Try to fetch from source if not provided
             data = appsSource.data[source];
        }
        if (!data) return;

        try {
            // Keys based on user logs: name, iconName, genericName, display, keywords
            
            const isPinned = pinnedLaunchers.indexOf("applications:" + source) !== -1;
            
            // Filter out hidden items unless they are already pinned
            if (data["display"] === false && !isPinned) {
                return;
            }

            const appName = data["name"] || source.replace(".desktop", "");
            const appIcon = data["iconName"] || "application-x-executable";
            const appGenericName = data["genericName"] || "";
            const appUrl = "applications:" + source;
            const appKeywords = data["keywords"] ? data["keywords"].join(" ") : "";
            
            // Cache metadata for fast lookup
            appMetadataCache[appUrl] = {
                name: appName,
                icon: appIcon,
                genericName: appGenericName,
                comment: data["comment"] || ""
            };

            // Check for duplicates in the model
            for (let j = 0; j < installedAppsModel.count; j++) {
                if (installedAppsModel.get(j).url === appUrl) {
                    return;
                }
            }

            const appItem = {
                name: appName,
                icon: appIcon,
                url: appUrl,
                keywords: appKeywords,
                genericName: appGenericName,
                comment: data["comment"] || ""
            };

            installedAppsModel.append(appItem);

            // Update filtered model if needed (initial populate or search match)
            if (cfg_page.currentSearchText.length === 0 && filteredAppsModel.count < 50) {
                 if (cfg_page.pinnedLaunchers.indexOf(appUrl) === -1) {
                     filteredAppsModel.append(appItem);
                 }
            } else if (cfg_page.currentSearchText.length > 0) {
                // update search results in real time if data comes in late
                const searchText = cfg_page.currentSearchText.toLowerCase();
                 if (appName.toLowerCase().includes(searchText) || 
                     appUrl.toLowerCase().includes(searchText) || 
                     (appItem.keywords && appItem.keywords.toLowerCase().includes(searchText)) ||
                     (appItem.genericName && appItem.genericName.toLowerCase().includes(searchText)) ||
                     (appItem.comment && appItem.comment.toLowerCase().includes(searchText))) {
                     if (cfg_page.pinnedLaunchers.indexOf(appUrl) === -1) {
                         filteredAppsModel.append(appItem);
                     }
                 }
            }

            // If this app is pinned, refresh the pinned list to show updated metadata
            // Only do this periodically or check if it's actually pinned to avoid spamming
            if (isPinned) {
                refreshPinnedAppsModel();
            }

        } catch (e) {
        }
    }

    function filterAppsModel(text, force) {
        const searchText = (text || "").toLowerCase();
        // Optimization for empty search with already filled model
        if (!force && searchText.length === 0 && filteredAppsModel.count > 0 && filteredAppsModel.count === Math.min(installedAppsModel.count, 50)) {
            return;
        }

        filteredAppsModel.clear();

        for (let i = 0; i < installedAppsModel.count; i++) {
            const app = installedAppsModel.get(i);
            
            // Skip if already pinned
            if (cfg_page.pinnedLaunchers.indexOf(app.url) !== -1) {
                continue;
            }

            // Apply search filter
            if (searchText && searchText.length > 0) {
                if (app.name.toLowerCase().includes(searchText) || 
                    app.url.toLowerCase().includes(searchText) || 
                    (app.keywords && app.keywords.toLowerCase().includes(searchText)) ||
                    (app.genericName && app.genericName.toLowerCase().includes(searchText)) ||
                    (app.comment && app.comment.toLowerCase().includes(searchText))) {
                    filteredAppsModel.append(app);
                }
            } else {
                filteredAppsModel.append(app);
                // Limit initial load for better performance
                if (filteredAppsModel.count >= 50) {
                    break;
                }
            }
        }
    }

    function loadMoreApps() {
        // Only lazy load if we are showing the full list (no search)
        if (cfg_page.currentSearchText.length > 0)
            return;

        if (filteredAppsModel.count < installedAppsModel.count) {
            const startIndex = filteredAppsModel.count;
            const endIndex = Math.min(startIndex + 50, installedAppsModel.count);

            for (let i = startIndex; i < endIndex; i++) {
                const app = installedAppsModel.get(i);
                // Skip if already pinned
                if (cfg_page.pinnedLaunchers.indexOf(app.url) !== -1) {
                    continue;
                }
                filteredAppsModel.append(app);
            }
        }
    }

    Component.onCompleted: {
        refreshPinnedAppsModel();
    }

    function getGenericNameForUrl(url) {
        if (appMetadataCache[url]) {
            return appMetadataCache[url].genericName || "";
        }
        return "";
    }

    function refreshPinnedAppsModel(sourceList) {
        pinnedAppsModel.clear();
        let list = sourceList || pinnedLaunchers;
        for (let i = 0; i < list.length; i++) {
            let launcher = list[i];
            let url = cleanUrl(launcher);
            pinnedAppsModel.append({
                "name": getNameForUrl(url),
                "genericName": getGenericNameForUrl(url),
                "comment": getCommentForUrl(url),
                "icon": getIconForUrl(url),
                "url": url
            });
        }
    }

    function getCommentForUrl(url) {
        if (url.startsWith("preferred://")) {
            return preferredApps[url] ? preferredApps[url].comment : "";
        }

        if (appMetadataCache[url]) {
            return appMetadataCache[url].comment || appMetadataCache[url].genericName || "";
        }
        return "";
    }

    function getNameForUrl(url) {
        if (url.startsWith("preferred://")) {
            return preferredApps[url] ? preferredApps[url].name : Wrappers.i18n("Default Application");
        }

        if (appMetadataCache[url]) {
            return appMetadataCache[url].name;
        }

        // Fallback for uncached items
        const source = launcherSource(url);
        if (source === null) {
            return url;
        }
        // Simple prettify fallback
        return source.replace(/\.desktop$/, "").split(/[-_.]/g).map(word => {
            return word.charAt(0).toUpperCase() + word.slice(1);
        }).join(" ");
    }

    function getIconForUrl(url) {
        if (url.startsWith("preferred://")) {
            return preferredApps[url] ? preferredApps[url].icon : "preferences-desktop-default-applications";
        }

        if (appMetadataCache[url]) {
            return appMetadataCache[url].icon;
        }

        // Fallback
        const source = launcherSource(url);
        if (source !== null) {
            return source.replace(/\.desktop$/, "").toLowerCase();
        }

        return "application-x-executable";
    }

    resources: [
        ListModel {
            id: pinnedAppsModel
        }
    ]

    // For better drag and drop reordering
    property int dragItemIndex: -1
    property int dropItemIndex: -1
    property bool isDragging: false

    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: mainPage
        
        // Ensure the stack view doesn't clip content during transitions if possible, 
        // though clipping is default.
        clip: true
    }

    Component {
        id: mainPage
        Item {
            // Main page container: FormCard sections. The pinned list card
            // grows with its rows and scrolls on its own once it runs out of
            // room, so drag-reorder and its autoscroll keep working inside it.

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                FormCard.FormHeader {
                    title: Wrappers.i18n("Pinned applications")
                }

                FormCard.FormCard {
                    id: pinnedCard
                    Layout.fillHeight: true
                    Layout.maximumHeight: implicitHeight
                    Layout.minimumHeight: Math.min(implicitHeight, cfg_page.gridUnit * 8)

                    FormCard.FormTextDelegate {
                        visible: pinnedAppsModel.count === 0
                        text: Wrappers.i18n("No pinned applications")
                        description: Wrappers.i18n("Add applications to pin to the taskbar.")
                    }

                    ListView {
                        id: pinnedAppsList
                        model: pinnedAppsModel
                        visible: pinnedAppsModel.count > 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        // Height of the list at rest. Frozen while a row is lifted
                        // out (its slot collapses to 0), so the card doesn't
                        // shrink under the cursor mid-drag.
                        property real restingHeight: 0
                        implicitHeight: restingHeight
                        Component.onCompleted: restingHeight = contentHeight
                        onContentHeightChanged: {
                            if (cfg_page.dragItemIndex === -1) {
                                restingHeight = contentHeight;
                            }
                        }

                        ScrollBar.vertical: ScrollBar {}

                        // Disable animations during drag
                        interactive: !cfg_page.isDragging

                    // Add drop area to handle autoscroll
                    DropArea {
                        id: dropArea
                        anchors.fill: parent

                        onEntered: (drag) => {
                            if (cfg_page.isDragging) {
                                updateDropIndex(drag.y);
                            }
                        }

                        onPositionChanged: (drag) => {
                            if (cfg_page.isDragging) {
                                let localY = drag.y;
                                if (localY < 50) {
                                    autoScrollTimer.direction = -1;
                                    autoScrollTimer.running = true;
                                } else if (localY > pinnedAppsList.height - 50) {
                                    autoScrollTimer.direction = 1;
                                    autoScrollTimer.running = true;
                                } else {
                                    autoScrollTimer.running = false;
                                }
                                updateDropIndex(localY);
                            }
                        }

                        onDropped: {
                            autoScrollTimer.running = false;
                        }

                        onExited: {
                            autoScrollTimer.running = false;
                        }

                        function updateDropIndex(localY) {
                            var absY = localY + pinnedAppsList.contentY;
                            var idx = pinnedAppsList.indexAt(0, absY);
                            if (idx === -1) {
                                cfg_page.dropItemIndex = pinnedAppsModel.count;
                                return;
                            }
                            var item = pinnedAppsList.itemAtIndex(idx);
                            if (item) {
                                let midY = item.y + item.height / 2;
                                cfg_page.dropItemIndex = absY < midY ? idx : idx + 1;
                            } else {
                                cfg_page.dropItemIndex = idx;
                            }
                        }
                    }

                    Timer {
                        id: autoScrollTimer
                        interval: 50
                        repeat: true
                        property int direction: 0
                        property int scrollStep: 10

                        onTriggered: {
                            pinnedAppsList.contentY = Math.max(0, Math.min(pinnedAppsList.contentY + direction * scrollStep, pinnedAppsList.contentHeight - pinnedAppsList.height));
                        }
                    }

                    delegate: PinnedAppCard {
                        pageRoot: cfg_page
                        cardStyle: appListStyle
                        pinnedModel: pinnedAppsModel
                    }
                    }

                    FormCard.FormDelegateSeparator {}

                    FormCard.FormButtonDelegate {
                        id: addAppButton
                        icon.name: "list-add"
                        text: Wrappers.i18n("Add Application...")
                        onClicked: {
                            // Force refresh to ensure unpinned apps appear
                            cfg_page.filterAppsModel(cfg_page.currentSearchText, true);

                            stackView.push(addAppsPage)
                            if (!cfg_page.initialLoadDone) {
                                cfg_page.initialLoadDone = true;
                                initialLoadTimer.start();
                            }
                        }
                    }

                    FormCard.FormDelegateSeparator {}

                    FormCard.FormButtonDelegate {
                        id: addSpecialButton
                        icon.name: "preferences-desktop-default-applications"
                        text: Wrappers.i18n("Add Special Launcher...")
                        description: Wrappers.i18n("Default web browser, file manager or mail client")
                        trailingLogo.direction: Qt.DownArrow
                        onClicked: specialLauncherMenu.popup(addSpecialButton, 0, addSpecialButton.height)

                        Menu {
                            id: specialLauncherMenu

                            MenuItem {
                                text: Wrappers.i18n("Default Web Browser")
                                icon.name: "internet-web-browser"
                                onTriggered: {
                                    cfg_page.addLauncher("preferred://browser");
                                }
                            }

                            MenuItem {
                                text: Wrappers.i18n("Default File Manager")
                                icon.name: "system-file-manager"
                                onTriggered: {
                                    cfg_page.addLauncher("preferred://filemanager");
                                }
                            }

                            MenuItem {
                                text: Wrappers.i18n("Default Mail Client")
                                icon.name: "internet-mail"
                                onTriggered: {
                                    cfg_page.addLauncher("preferred://mail");
                                }
                            }
                        }
                    }
                }

                FormCard.FormSectionText {
                    text: Wrappers.i18n("Drag items to reorder them.")
                }

                FormCard.FormHeader {
                    title: Wrappers.i18n("Unpinning")
                }

                FormCard.FormCard {
                    FormCard.FormSwitchDelegate {
                        id: cfg_unpinByDrag
                        text: Wrappers.i18n("Unpin app by dragging its icon off the panel")
                        checked: cfg_page.cfg_unpinByDrag
                        onToggled: cfg_page.cfg_unpinByDrag = checked
                    }

                    FormCard.FormDelegateSeparator {
                        visible: cfg_unpinByDragExplosion.visible
                    }

                    FormCard.FormSwitchDelegate {
                        id: cfg_unpinByDragExplosion
                        visible: cfg_unpinByDrag.checked && cfg_page.cfg_iconOnly === 1
                        text: Wrappers.i18n("Play removal animation")
                        checked: cfg_page.cfg_unpinByDragExplosion
                        onToggled: cfg_page.cfg_unpinByDragExplosion = checked
                    }
                }

                // Takes the slack when the pinned list is short, keeping the
                // sections packed at the top like a FormCard page
                Item {
                    Layout.fillHeight: true
                    Layout.minimumHeight: cfg_page.largeSpacing
                }
            }
        }
    }

    Component {
        id: addAppsPage
        Item {
            // Add apps page container
            focus: true // Ensure item can receive focus for keys

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: cfg_page.smallSpacing

                    Button {
                        icon.name: "go-previous"
                        text: Wrappers.i18n("Back")
                        onClicked: stackView.pop()
                    }

                    Kirigami.Heading {
                        text: Wrappers.i18n("Add Application")
                        level: 3
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }
                }

                // Search Field
                Kirigami.SearchField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.maximumWidth: cfg_page.gridUnit * 30
                    Layout.alignment: Qt.AlignHCenter
                    Layout.margins: cfg_page.smallSpacing
                    placeholderText: Wrappers.i18n("Search applications...")
                    text: cfg_page.currentSearchText
                    // Filtering is debounced by searchTimer below
                    autoAccept: false
                    onTextChanged: {
                        cfg_page.currentSearchText = text
                        searchTimer.restart()
                    }
                }

                Timer {
                    id: searchTimer
                    interval: 300
                    onTriggered: cfg_page.filterAppsModel(cfg_page.currentSearchText)
                }

                FormCard.FormHeader {
                    title: Wrappers.i18n("Applications")
                    visible: filteredAppsModel.count > 0
                }

                FormCard.FormCard {
                    visible: filteredAppsModel.count > 0
                    Layout.fillHeight: true

                    ListView {
                        id: appsListView
                        model: filteredAppsModel
                        clip: true
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {}

                        onContentYChanged: {
                            if (contentY + height >= contentHeight - 100) {
                                cfg_page.loadMoreApps();
                            }
                        }

                        delegate: ColumnLayout {
                            id: appsDelegate
                            required property var model
                            required property int index

                            width: ListView.view.width
                            spacing: 0

                            Kirigami.Separator {
                                visible: appsDelegate.index > 0
                                opacity: 0.5
                                Layout.fillWidth: true
                                Layout.leftMargin: Kirigami.Units.largeSpacing
                                Layout.rightMargin: Kirigami.Units.largeSpacing
                            }

                            FormCard.FormButtonDelegate {
                                id: appButton
                                icon.name: appsDelegate.model.icon || "application-x-executable"
                                icon.width: appListStyle.iconSize
                                icon.height: appListStyle.iconSize
                                text: appsDelegate.model.name || appsDelegate.model.url
                                description: appsDelegate.model.genericName || ""
                                trailingLogo.visible: false

                                onClicked: {
                                    cfg_page.addLauncher(appsDelegate.model.url);
                                    // Don't close the page, just remove from the list
                                    // stackView.pop();

                                    // Remove item from filtered model immediately
                                    filteredAppsModel.remove(appsDelegate.index);
                                }

                                ToolTip.text: appsDelegate.model.comment || appsDelegate.model.name || ""
                                ToolTip.visible: appButton.hovered && ToolTip.text !== ""
                                ToolTip.delay: 1000
                            }
                        }
                    }
                }

                // Loading indicator
                Item {
                    visible: cfg_page.isLoadingApps && filteredAppsModel.count === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    BusyIndicator {
                        anchors.centerIn: parent
                        running: cfg_page.isLoadingApps
                    }
                }

                // Keeps the header and search field at the top when the list
                // is empty and nothing is loading
                Item {
                    visible: !cfg_page.isLoadingApps && filteredAppsModel.count === 0
                    Layout.fillHeight: true
                }

                Item {
                    Layout.preferredHeight: cfg_page.largeSpacing
                }
            }
        }
    }
    function addLauncher(url) {
        // Create a copy to ensure change detection
        let currentLaunchers = Array.from(pinnedLaunchers);
        
        // Don't add if already in the list
        if (currentLaunchers.indexOf(url) !== -1) {
            return;
        }

        currentLaunchers.push(url);
        cfg_page.cfg_launchers = currentLaunchers;
        // pinnedLaunchers binding will update automatically
        refreshPinnedAppsModel();
    }

    // Move item in the model and update configuration
    function moveItem(fromIndex, toIndex) {
        if (fromIndex === toIndex) return;
        
        // Update visual model immediately
        pinnedAppsModel.move(fromIndex, toIndex, 1);
        
        // Rebuild list from model to update config
        let list = [];
        for (let i = 0; i < pinnedAppsModel.count; i++) {
            list.push(pinnedAppsModel.get(i).url);
        }
        
        cfg_page.cfg_launchers = list;
        // pinnedLaunchers binding should update automatically from cfg_launchers
    }


}
