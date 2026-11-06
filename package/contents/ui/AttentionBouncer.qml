/*
    SPDX-FileCopyrightText: 2026 Jakub Lipinski

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Runs an attention bounce on the task's schedule (Task.attentionCalm / attentionRestMs):
// during the 30 s burst one bounce per second, afterwards one reminder bounce every
// 5 minutes; a new burst (new request or new message) bounces right away.
// The consumer owns the animation and what it moves; it resets that in onStopped.
Item {
    id: bouncer

    // The Task (main.qml delegate) whose attention clock drives the schedule
    required property var task
    // Whether the bounce should run now (e.g. the icon or peek is shown and wants attention)
    required property bool active
    required property Animation animation

    // Emitted when the bounce stops because active turned false
    signal stopped()

    visible: false

    // Becoming active bounces only during the burst; afterwards (e.g. the mouse left the
    // icon, the panel hid again) it just resumes the 5-minute reminder
    function resume(): void {
        if (!bouncer.task || !bouncer.task.attentionCalm)
            bouncer.animation.start();
        else if (!restTimer.running)
            bouncer.rest();
    }

    function rest(): void {
        restTimer.interval = bouncer.task ? bouncer.task.attentionRestMs() : 1000;
        restTimer.start();
    }

    onActiveChanged: {
        if (bouncer.active) {
            bouncer.resume();
        } else {
            restTimer.stop();
            bouncer.animation.stop();
            bouncer.stopped();
        }
    }
    Component.onCompleted: if (bouncer.active) bouncer.resume()

    Timer {
        id: restTimer
        onTriggered: if (bouncer.active) bouncer.animation.start()
    }
    Connections {
        target: bouncer.animation
        function onFinished() {
            if (bouncer.active)
                bouncer.rest();
        }
    }
    Connections {
        target: bouncer.task
        ignoreUnknownSignals: true
        function onAttentionCalmChanged() {
            if (bouncer.active && !bouncer.task.attentionCalm && !bouncer.animation.running) {
                restTimer.stop();
                bouncer.animation.start();
            }
        }
    }
}
