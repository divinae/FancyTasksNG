/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import "code/media.js" as Media

Item {
    id: controller

    // Input Properties
    property var taskItem: null

    // Audio stream manager from tasksRoot
    readonly property var audioStreamManager: taskItem && taskItem.tasksRoot ? taskItem.tasksRoot.audioStreamManager : null

    // Exposed Audio State Properties
    property var audioStreams: []
    readonly property bool hasAudioStream: audioStreams.length > 0
    readonly property bool playingAudio: Media.streamsPlaying(audioStreams)
    readonly property bool muted: Media.streamsMuted(audioStreams)

    // Query and update PulseAudio streams matching the task
    function updateAudioStreams(): void {
        if (!taskItem) return;
        
        const tasksRoot = taskItem.tasksRoot;
        if (!tasksRoot) return;

        const pa = tasksRoot.audioStreamManager.item;
        if (!pa || !taskItem.model) {
            audioStreams = [];
            return;
        }

        const streams = tasksRoot.audioStreamsFor(pa, taskItem.model.AppId, taskItem.model.AppPid, taskItem.model.AppName,
            String(taskItem.model.LauncherUrlWithoutIcon || ""));
        // Keep the old array when nothing changed, so dependent bindings don't re-evaluate
        if (streams.length !== audioStreams.length || streams.some((stream, i) => stream !== audioStreams[i]))
            audioStreams = streams;
    }

    // Toggle mute state for all application streams
    function toggleMuted(): void {
        Media.toggleStreamsMuted(audioStreams);
    }

    // Adjust application volume or system global volume
    function adjustVolume(increment, isGlobal): void {
        if (!taskItem) return;

        const tasksRoot = taskItem.tasksRoot;
        if (!tasksRoot) return;

        if (isGlobal) {
            tasksRoot.adjustGlobalVolume(increment);
            return;
        }

        const audioManager = tasksRoot.audioStreamManager.item;
        if (!audioManager || audioStreams.length === 0) return;

        let lastResult = null;
        audioStreams.forEach(stream => {
            lastResult = audioManager.adjustObjectVolume(stream, increment);
        });

        if (lastResult && taskItem.volumeOverlay) {
            taskItem.volumeOverlay.volume = lastResult.volume;
            taskItem.volumeOverlay.muted = lastResult.muted;
            taskItem.volumeOverlay.show();
        }
    }

    // Watch for stream changes globally
    Connections {
        target: controller.audioStreamManager ? controller.audioStreamManager.item : null
        ignoreUnknownSignals: true
        function onStreamsChanged(): void {
            controller.updateAudioStreams();
        }
    }

    // Web app claims changed (see main.qml audioStreamsFor)
    Connections {
        target: controller.taskItem ? controller.taskItem.tasksRoot : null
        ignoreUnknownSignals: true
        // Both can change in one refresh; callLater runs a single update for them
        function onWebAppTracksChanged(): void {
            Qt.callLater(controller.updateAudioStreams);
        }
        function onWebAppLaunchersChanged(): void {
            Qt.callLater(controller.updateAudioStreams);
        }
    }

    // Listen to task metadata and state changes
    Connections {
        target: controller.taskItem
        ignoreUnknownSignals: true
        function onPidChanged(): void {
            if (controller.taskItem.model) controller.updateAudioStreams();
        }
        function onAppNameChanged(): void {
            if (controller.taskItem.model) controller.updateAudioStreams();
        }
        function onIsWindowChanged(): void {
            if (controller.taskItem.model && controller.taskItem.model.IsWindow) {
                controller.updateAudioStreams();
            }
        }
    }

    function initialUpdate(): void {
        if (taskItem && !taskItem.inPopup && taskItem.model && taskItem.model.IsWindow) {
            updateAudioStreams();
        }
    }

    // Task.qml's Loader assigns taskItem in onLoaded, i.e. after
    // Component.onCompleted, so the first update has to happen here too.
    onTaskItemChanged: initialUpdate()

    Component.onCompleted: initialUpdate()
}
