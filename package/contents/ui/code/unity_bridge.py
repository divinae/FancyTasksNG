#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
# SPDX-License-Identifier: GPL-2.0-or-later

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
import sys
import ctypes
import signal

def set_pdeathsig():
    """Ensure the process dies when its parent (plasmashell) dies."""
    try:
        libc = ctypes.CDLL("libc.so.6")
        libc.prctl(1, signal.SIGTERM) # 1 is PR_SET_PDEATHSIG
    except Exception:
        pass

"""
Unity Bridge Sniffer - DBus Re-emitter
Listens for Unity signals and re-emits them on a private interface
that QML can easily consume.
"""

class BridgeEmitter(dbus.service.Object):
    def __init__(self):
        # We use a unique name for our bridge to avoid conflicts
        try:
            self.bus = dbus.SessionBus()
            self.bus_name = dbus.service.BusName('io.github.daydve.fancytasksng.Bridge', bus=self.bus, do_not_queue=True)
            dbus.service.Object.__init__(self, self.bus_name, '/Bridge')
            print("Bridge: Re-emitter is ready on io.github.daydve.fancytasksng.Bridge")
        except dbus.exceptions.NameExistsException:
            # Another task manager instance already runs the bridge; its signals reach everyone.
            print("Bridge: already running")
            sys.exit(0)
        except Exception as e:
            print(f"Bridge error: {e}", file=sys.stderr)
            sys.exit(1)

    @dbus.service.signal('io.github.daydve.fancytasksng.BadgeUpdate', signature='sidb')
    def UpdateSignal(self, appId, count, progress, urgent):
        # This signal will be sent to the bus
        pass

# appId -> last known LauncherEntry properties. Update signals only carry the
# properties that changed, so they are merged into this state before re-emitting.
app_state = {}
# D-Bus unique name of the sender -> appIds it published, to reset them when it exits
sender_apps = {}


def emit_state(appId):
    props = app_state.get(appId, {})
    final_count = int(props.get("count", 0)) if props.get("count-visible", True) else 0
    final_progress = float(props.get("progress", 0.0)) if props.get("progress-visible", False) else -1.0
    urgent = bool(props.get("urgent", False))

    # Re-emit on our private channel
    emitter.UpdateSignal(str(appId), final_count, final_progress, urgent)


def handle_unity_update(appId, properties, sender=None, **kwargs):
    appId = str(appId)
    app_state.setdefault(appId, {}).update(properties)
    if sender:
        sender_apps.setdefault(str(sender), set()).add(appId)
    emit_state(appId)


def handle_name_owner_changed(name, old_owner, new_owner):
    # An app that set a badge, progress or urgent flag exited: clear what it published
    if new_owner or name not in sender_apps:
        return
    for appId in sender_apps.pop(name):
        app_state.pop(appId, None)
        emit_state(appId)

if __name__ == '__main__':
    set_pdeathsig()
    DBusGMainLoop(set_as_default=True)
    
    emitter = BridgeEmitter()
    
    bus = dbus.SessionBus()

    # Register as Unity service so KDE apps (KMail, Kontact) know we're listening.
    # These apps check for "com.canonical.Unity" before sending badge updates.
    # DBUS_NAME_FLAG_DO_NOT_QUEUE: if the name is already taken (e.g. by the
    # standard Plasma Task Manager), just skip — signals will still be received
    # via the wildcard signal_receiver below.
    try:
        reply = bus.request_name(
            'com.canonical.Unity',
            dbus.bus.NAME_FLAG_DO_NOT_QUEUE
        )
        if reply == dbus.bus.REQUEST_NAME_REPLY_PRIMARY_OWNER:
            print("Bridge: Registered as com.canonical.Unity (primary owner)")
        else:
            print("Bridge: com.canonical.Unity already owned, listening passively")
    except Exception as e:
        print(f"Bridge: Could not request com.canonical.Unity: {e}")

    bus.add_signal_receiver(
        handle_unity_update,
        signal_name="Update",
        dbus_interface="com.canonical.Unity.LauncherEntry",
        sender_keyword="sender"
    )
    bus.add_signal_receiver(
        handle_name_owner_changed,
        signal_name="NameOwnerChanged",
        dbus_interface="org.freedesktop.DBus",
        bus_name="org.freedesktop.DBus"
    )
    
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        sys.exit(0)
