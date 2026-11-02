/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.private.mpris as Mpris

Item {
    id: controller

    // Input Properties
    required property var toolTipDelegate
    required property int appPid
    property string appId: ""
    property string title: ""
    property var audioStreamManager
    property var mpris2Model
    property int index
    property var thumbnailWinId
    property bool isPlayingAudio: false

    readonly property var config: Plasmoid.configuration
    readonly property bool audioIndicatorsEnabled: config ? config.indicateAudioStreams : false

    // Media Player Data
    readonly property var tasksRoot: toolTipDelegate && toolTipDelegate.parentTask ? toolTipDelegate.parentTask.tasksRoot : null
    readonly property string launcherUrlString: toolTipDelegate ? String(toolTipDelegate.launcherUrl || "") : ""

    // Which player belongs to this window. Browsers register their media under the browser's
    // own desktop entry, so web app windows run by the same browser (e.g. a Spotify app) need
    // extra matching, and the main browser window must not take their player.
    readonly property var playerData: {
        if (!mpris2Model || !toolTipDelegate)
            return null;
        const claims = tasksRoot ? tasksRoot.webAppTracks : {};
        // 1. A web app window playing from its own site (matched by the helper via xesam:url)
        if (claims[launcherUrlString]) {
            const claimed = tasksRoot.playerForClaim(claims[launcherUrlString]);
            if (claimed)
                return claimed;
        }
        // 2. A player whose track this window's title shows
        const shown = tasksRoot ? tasksRoot.playerShownInTitle(title) : null;
        if (shown)
            return shown;
        if (!mpris2Model.playerForLauncherUrl)
            return null;
        // 3. The app's own player, unless another window claims its track (a web app playing
        //    it, or a window whose title shows it)
        const own = mpris2Model.playerForLauncherUrl(toolTipDelegate.launcherUrl, appPid);
        if (own && tasksRoot) {
            const claimedElsewhere = Object.keys(claims).some(url => {
                if (url === launcherUrlString)
                    return false;
                const claimed = tasksRoot.playerForClaim(claims[url]);
                return claimed === own || (!!claimed && claimed.instancePid === own.instancePid);
            });
            if (claimedElsewhere || tasksRoot.trackShownInOtherWindow(own.track, thumbnailWinId))
                return null;
        }
        return own;
    }
    readonly property bool titleIncludesTrack: playerData && playerData.track && title.includes(playerData.track)

    // A window tile inside a grouped tooltip (as opposed to a single-window tooltip)
    readonly property bool isGroupMember: !!toolTipDelegate && toolTipDelegate.isGroup && !!thumbnailWinId

    // Which window of a group the media belongs to, most reliable signal first:
    // 1. audio streams tagged with a window id, 2. the window title showing the track
    //    (see ToolTipDelegate.trackWindowIds), 3. otherwise every window of the playing app.
    readonly property bool belongsToThisWindow: {
        const streamWindowIds = audioStreams.map(stream => stream.windowId).filter(id => !!id);
        if (streamWindowIds.length > 0)
            return streamWindowIds.indexOf(thumbnailWinId) !== -1;
        const trackIds = toolTipDelegate ? toolTipDelegate.trackWindowIds : [];
        if (trackIds.length > 0)
            return trackIds.indexOf(thumbnailWinId) !== -1;
        return isPlayingAudio || hasAudioStream;
    }

    // Audio Streams
    property var audioStreams: []
    property bool delayAudioStreamIndicator: false
    readonly property bool hasAudioStream: audioStreams.length > 0
    readonly property bool muted: hasAudioStream && audioStreams.every(item => item.muted)
    readonly property bool playingAudio: hasAudioStream && audioStreams.some(item => !item.corked)

    // While userVolumeChangeTimer is running, expose cachedVolume instead of live PA
    // to prevent the slider from showing intermediate PA values during rapid scrolling.
    property int cachedVolume: 0
    readonly property int appVolume: {
        if (hasAudioStream && audioStreams.length > 0 && !userVolumeChangeTimer.running) {
            let validStreams = audioStreams.filter(s => s && typeof s.volume !== 'undefined');
            if (validStreams.length > 0) {
                return validStreams.reduce((max, s) => Math.max(max, s.volume), 0);
            }
        }
        return cachedVolume;
    }

    function hasWindowSpecificStream(winId) {
        if (!winId || !hasAudioStream)
            return false;
        return audioStreams.some(stream => stream.windowId === winId);
    }

    Timer {
        id: streamClearTimer
        interval: 1000
        repeat: false
        onTriggered: controller.audioStreams = []
    }

    Timer {
        id: userVolumeChangeTimer
        // Cooldown after a user volume change. During this window appVolume returns
        // cachedVolume instead of reading live PA streams, which may still carry
        // intermediate values from earlier commands in a rapid scroll sequence.
        interval: 500
        repeat: false
        onTriggered: {
            var validStreams = controller.audioStreams.filter(s => s && typeof s.volume !== 'undefined');
            if (validStreams.length > 0)
                controller.cachedVolume = validStreams.reduce((max, s) => Math.max(max, s.volume), 0);
        }
    }

    function updateAudioStreams(args) {
        if (args && args.delay) {
            delayAudioStreamIndicator = true;
        }
        var currentForce = (args && args.force);

        if (!controller.audioStreamManager) {
            streamClearTimer.stop();
            audioStreams = [];
            return;
        }
        var pa = controller.audioStreamManager.item;
        if (!pa) {
            streamClearTimer.stop();
            audioStreams = [];
            return;
        }

        var streams = tasksRoot ? tasksRoot.audioStreamsFor(pa, appId, appPid, toolTipDelegate.appName, launcherUrlString)
                                : pa.streamsForApp(appId, appPid, toolTipDelegate.appName);

        if (streams.length > 0) {
            // Only update cachedVolume from PA when not actively changing volume.
            // While userVolumeChangeTimer is running we keep cachedVolume as-is so
            // the slider stays at the intended position until PA fully converges.
            if (!userVolumeChangeTimer.running) {
                let validStreams = streams.filter(s => s && typeof s.volume !== 'undefined');
                if (validStreams.length > 0)
                    cachedVolume = validStreams.reduce((max, s) => Math.max(max, s.volume), 0);
            }
            streamClearTimer.stop();
            audioStreams = streams;
        } else {
            if (audioStreams.length > 0) {
                streamClearTimer.restart();
            } else {
                streamClearTimer.stop();
                audioStreams = [];
            }
        }
    }

    function toggleMuted() {
        if (muted) {
            audioStreams.forEach(item => item.unmute());
        } else {
            audioStreams.forEach(item => item.mute());
        }
    }

    function adjustAppVolume(increment) {
        if (!hasAudioStream || !audioStreamManager || !audioStreamManager.item)
            return;
        let pa = audioStreamManager.item;
        // Compute an absolute target and delegate to setVolume — same path as the slider.
        // appVolume returns the live PA value when idle, or cachedVolume during rapid
        // scrolling, so accumulation is always correct without any separate caching logic.
        setVolume(Math.max(pa.minimalVolume, Math.min(pa.normalVolume, appVolume + increment)));
    }

    function setVolume(value) {
        if (!hasAudioStream)
            return;
        cachedVolume = value;
        userVolumeChangeTimer.restart();
        audioStreams.forEach(item => {
            if (item && typeof item.setVolume === 'function') {
                item.setVolume(value);
                if (value > 0 && item.muted)
                    item.unmute();
            }
        });
    }

    Connections {
        target: controller.audioStreamManager ? controller.audioStreamManager.item : null
        ignoreUnknownSignals: true
        function onStreamsChanged() {
            controller.updateAudioStreams({
                delay: true
            });
        }
    }

    onAppPidChanged: updateAudioStreams({
        delay: false,
        force: true
    })
    onAppIdChanged: updateAudioStreams({
        delay: false,
        force: true
    })
    Connections {
        target: controller.tasksRoot
        ignoreUnknownSignals: true
        function onWebAppTracksChanged() {
            controller.updateAudioStreams({ delay: false, force: true });
        }
    }
    Component.onCompleted: {
        updateAudioStreams({
            delay: false,
            force: true
        });
        if (tasksRoot)
            tasksRoot.refreshWebAppTracks();
    }

    // Effective control state calculation
    readonly property bool showPlayerControls: {
        if (index === -1 || !playerData || !playerData.canControl)
            return false;
        
        var hasStatus = playerData.playbackStatus === Mpris.PlaybackStatus.Playing || 
                        playerData.playbackStatus === Mpris.PlaybackStatus.Paused || 
                        (playerData.track && playerData.track.length > 0);
        if (!hasStatus)
            return false;

        // Single-window tooltip or group-level controller: always allow controls;
        // a window tile in a group: only the window the media belongs to
        return !isGroupMember || belongsToThisWindow;
    }
    // Volume needs an actual stream to act on
    readonly property bool showVolumeControls: index !== -1 && audioStreamManager && audioStreamManager.item !== null && audioIndicatorsEnabled
        && hasAudioStream && (!isGroupMember || belongsToThisWindow)
    readonly property bool controlsAreEffective: config && config.showMediaControls && (showPlayerControls || showVolumeControls)
}

