# SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
# SPDX-License-Identifier: GPL-2.0-or-later

"""Startup plumbing shared by the D-Bus helper scripts (desktop_actions.py, unity_bridge.py).

The helpers are started as `python3 <path>/<script>.py`, so this directory is on sys.path.
"""

import ctypes
import signal
import sys

import dbus
import dbus.service

PR_SET_PDEATHSIG = 1


def set_pdeathsig():
    """Ensure the process dies when its parent (plasmashell) dies."""
    try:
        libc = ctypes.CDLL("libc.so.6")
        libc.prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
    except Exception:
        pass


def export_service(obj, bus_name, object_path, ready_msg, running_msg, error_prefix):
    """Claim bus_name and export obj at object_path; returns (bus, BusName).

    Exits with 0 if another instance already owns the name (it serves every task manager)
    and with 1 on any other failure.
    """
    try:
        bus = dbus.SessionBus()
        name = dbus.service.BusName(bus_name, bus=bus, do_not_queue=True)
        dbus.service.Object.__init__(obj, name, object_path)
    except dbus.exceptions.NameExistsException:
        print(running_msg, flush=True)
        sys.exit(0)
    except Exception as e:
        print(f"{error_prefix}: {e}", file=sys.stderr)
        sys.exit(1)
    print(ready_msg, flush=True)
    return bus, name
