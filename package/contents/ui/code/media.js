/*
    SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

// Shared helpers for the task and tooltip media controllers and their volume controls.

// Stand-in for PlayerController.playerData while no player is known
const emptyPlayer = Object.freeze({
    canControl: false,
    playbackStatus: 0,
    track: "",
    artist: "",
    canGoPrevious: false,
    canPlay: false,
    canPause: false,
    canGoNext: false
});

// Speaker icon for a volume, given as a fraction of the normal (100%) volume
function volumeIconName(muted, fraction) {
    if (muted)
        return "audio-volume-muted";
    const percent = Math.round(fraction * 100);
    if (percent <= 25)
        return "audio-volume-low";
    if (percent <= 75)
        return "audio-volume-medium";
    return "audio-volume-high";
}

// Streams whose delegate still exists. ToolTipMediaController keeps its last streams for a
// moment after they vanish (streamClearTimer); by then the Instantiator may have destroyed
// the delegates, which leaves wrappers whose methods and properties are gone.
function liveStreams(streams) {
    return streams.filter(stream => !!stream && typeof stream.mute === "function");
}

// Whether there are streams and all of them are muted
function streamsMuted(streams) {
    const live = liveStreams(streams);
    return live.length > 0 && live.every(stream => stream.muted);
}

// Whether any stream is actually playing (not corked)
function streamsPlaying(streams) {
    return liveStreams(streams).some(stream => !stream.corked);
}

// Unmute all streams if all are muted, otherwise mute them all
function toggleStreamsMuted(streams) {
    const live = liveStreams(streams);
    if (streamsMuted(live))
        live.forEach(stream => stream.unmute());
    else
        live.forEach(stream => stream.mute());
}

// Highest volume among the streams that report one, or -1 if none does
function maxStreamVolume(streams) {
    const valid = liveStreams(streams).filter(stream => typeof stream.volume === "number");
    if (valid.length === 0)
        return -1;
    return valid.reduce((max, stream) => Math.max(max, stream.volume), 0);
}
