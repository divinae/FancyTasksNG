/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-FileCopyrightText: 2024 ivan tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2022-2023 Alexandra <alexankitty@gmail.com>
    SPDX-FileCopyrightText: 2017 Kai Uwe Broulik <kde@privat.broulik.de>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick

import "code/singletones"
import org.kde.plasma.private.volume as PlasmaPa

QtObject {
    id: audioStreamManager

    signal streamsChanged()

    // Emits streamsChanged once per event loop pass, however often it is requested: streams
    // come and go in bursts, and registerPidMatch runs while controllers query their streams
    function _emitStreamsChanged(): void {
        Qt.callLater(audioStreamManager._doEmitStreamsChanged);
    }
    function _doEmitStreamsChanged(): void {
        audioStreamManager.streamsChanged();
    }

    // Parent PID of each stream PID (from the helper; QML can't read /proc). Chromium-family
    // browsers play audio from a utility child process whose parent owns the windows.
    property var parentPidMap: ({})
    function refreshParentPids(): void {
        const missing = [];
        for (let i = 0; i < instantiator.count; ++i) {
            const stream = instantiator.objectAt(i);
            if (stream && stream.pid > 0 && !(String(stream.pid) in parentPidMap) && missing.indexOf(stream.pid) === -1)
                missing.push(stream.pid);
        }
        if (missing.length === 0)
            return;
        DesktopActionsManager.parentPids(missing, map => {
            const next = Object.assign({}, audioStreamManager.parentPidMap);
            for (const pid of missing)
                next[String(pid)] = map[String(pid)] || 0;
            audioStreamManager.parentPidMap = next;
            audioStreamManager._emitStreamsChanged();
        });
    }

    // PIDs (or parent PIDs) of streams some task already owns through a direct PID match. The
    // app-name fallback must not hand those streams to another task: separate installs of the
    // same app (e.g. two Firefox builds) report the same application.name. (Upstream 1585d98.)
    property var pidMatches: ({})
    function registerPidMatch(pid: int): void {
        if (pid > 0 && !(pid in pidMatches)) {
            const next = Object.assign({}, pidMatches);
            next[pid] = true;
            pidMatches = next;
            // Lets a task that already grabbed this stream by name drop it
            _emitStreamsChanged();
        }
    }
    
    readonly property QtObject globalConfig: PlasmaPa.GlobalConfig { }
    
    readonly property PlasmaPa.SinkModel sinksModel: PlasmaPa.SinkModel { }
    readonly property var preferredSink: sinksModel.preferredObject || sinksModel.preferredSink || (sinksModel.count > 0 ? sinksModel.data(sinksModel.index(0, 0), 257 /*ItemRole*/) : null)
    
    // QtObject has no default property, hence adding the Instantiator to one explicitly.
    readonly property Instantiator instantiator: Instantiator {
        model: PlasmaPa.PulseObjectFilterModel {
            filters: [ { role: "VirtualStream", value: false } ]
            sourceModel: PlasmaPa.SinkInputModel {}
        }

        delegate: QtObject {
            id: delegate
            required property var model
            
            readonly property int pid: model.Client?.properties["application.process.id"] ?? 0
            readonly property int parentPid: audioStreamManager.parentPidMap[String(pid)] || 0
            // Notification sounds Plasma plays on an app's behalf are not the app's audio
            readonly property bool isPlasmaSound: (model.Client?.properties["application.process.binary"] ?? "") === "plasmashell"
            readonly property string appName: model.Client?.properties["application.name"] ?? ""
            readonly property string portalAppId: model.Client?.properties["pipewire.access.portal.app_id"] ?? ""
            
            // Expose Window IDs for matching
            readonly property int x11Xid: parseInt(model.Client?.properties["window.x11.xid"] ?? "0")
            readonly property int windowId: x11Xid > 0 ? x11Xid : 0
            readonly property bool muted: model.Muted
            // whether there is actually nothing going on on that stream
            readonly property bool corked: model.Corked
            readonly property int volume: model.Volume
            
            // Allow setting volume/mute
            function mute(): void {
                model.Muted = true;
            }
            function unmute(): void {
                model.Muted = false;
            }
            function setVolume(vol): void {
                model.Volume = vol;
            }

            onPidChanged: {
                if (pid > 0) restoreVolume();
            }
            
            function restoreVolume() {
                var cached = audioStreamManager.getCachedVolume(pid);
                if (cached > 0) { 
                    setVolume(cached);
                }
            }
            
            onVolumeChanged: {
                if (pid > 0) {
                     audioStreamManager.saveVolume(pid, volume);
                }
            }
        }

        onObjectAdded: (index, object) => {
            audioStreamManager._emitStreamsChanged();
            Qt.callLater(audioStreamManager.refreshParentPids);
        }
        onObjectRemoved: (index, object) => audioStreamManager._emitStreamsChanged()
    }

    // Streams of an app: by portal app id (sandboxed apps), then process id, then app name
    function streamsForApp(appId: string, pid: int, appName: string): var {
        let streams = streamsForAppId(String(appId || "").replace(/\.desktop$/, ""));
        if (!streams.length) {
            streams = streamsForPid(pid);
            if (streams.length)
                registerPidMatch(pid);
        }
        if (!streams.length)
            streams = streamsForAppName(appName);
        return streams;
    }

    function streamsForAppId(appId: string): var {
        if (!appId) return [];
        return findStreams(stream => stream.portalAppId === appId);
    }

    function streamsForAppName(appName: string): var {
        if (!appName) return [];
        return findStreams(stream => stream.appName === appName
            && !(stream.pid in pidMatches) && !(stream.parentPid in pidMatches));
    }

    function streamsForPid(pid: int): var {
        if (pid <= 0) return [];
        
        // 1. Try direct PID match
        // The window's process, or its child for Chromium-family audio helpers
        let streams = findStreams(stream => (stream.pid === pid || stream.parentPid === pid) && !stream.portalAppId);
        
        
        return streams;
    }

    function findStreams(predicate): var {
        const results = [];
        for (let i = 0, count = instantiator.count; i < count; ++i) {
            const stream = instantiator.objectAt(i);
            if (stream && !stream.isPlasmaSound && predicate(stream)) {
                results.push(stream);
            }
        }

        return results;
    }

    // Expose volume constants if valid, otherwise fallback
    readonly property int minimalVolume: PlasmaPa.PulseAudio.MinimalVolume ?? 0
    readonly property int normalVolume: PlasmaPa.PulseAudio.NormalVolume ?? 65536

    // Persistent Volume Cache (Key: WinID or PID)
    property var volumeCache: ({})

    function saveVolume(key, vol: int) {
        if (key) {
            volumeCache[key] = vol;
        }
    }

    function getCachedVolume(key): int {
        if (key && volumeCache[key] !== undefined) {
            return volumeCache[key];
        }
        return -1;
    }

    function adjustObjectVolume(obj, increment) {
        if (!obj) return;
        
        const step = (normalVolume - minimalVolume) * (globalConfig["volumeStep"] || 5) / 100;
        const currentVolume = obj.Volume !== undefined ? obj.Volume : (obj.volume !== undefined ? obj.volume : 0);
        const newVolume = Math.round(Math.max(minimalVolume, Math.min(currentVolume + (step * increment), normalVolume)));
        
        if (obj.setVolume !== undefined) {
            obj.setVolume(newVolume);
        } else if (obj.volume !== undefined) {
            obj.volume = newVolume;
        } else if (obj.Volume !== undefined) {
            obj.Volume = newVolume;
        }

        const isCurrentlyMuted = obj.Muted !== undefined ? obj.Muted : (obj.muted !== undefined ? obj.muted : false);
        
        if (newVolume > minimalVolume && isCurrentlyMuted) {
            if (obj.unmute !== undefined) obj.unmute(); 
            else if (obj.Muted !== undefined) obj.Muted = false;
            else if (obj.muted !== undefined) obj.muted = false;
        } else if (newVolume <= minimalVolume && !isCurrentlyMuted) {
            if (obj.mute !== undefined) obj.mute(); 
            else if (obj.Muted !== undefined) obj.Muted = true;
            else if (obj.muted !== undefined) obj.muted = true;
        }
        return {
            volume: (newVolume - minimalVolume) / (normalVolume - minimalVolume),
            muted: obj.Muted !== undefined ? obj.Muted : (obj.muted !== undefined ? obj.muted : false)
        };
    }
}
