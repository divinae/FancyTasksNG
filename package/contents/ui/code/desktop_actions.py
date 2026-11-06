#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Vitaliy Elin <daydve@smbit.pro>
# SPDX-License-Identifier: GPL-2.0-or-later

"""
Desktop Actions Helper — reads .desktop jump list actions and
KActivities recent documents for contextual menu population.

Protocol (line-based JSON over stdin/stdout):
  Request:  {"launcherUrl": "file:///usr/share/applications/org.kde.dolphin.desktop"}
  Response: {"jumpList": [...], "recentDocs": [...]}

Each jumpList item: {"name": str, "icon": str, "exec": str}
Each recentDocs item: {"name": str, "url": str, "icon": str}
"""

import configparser
import hashlib
import json
import os
import re
import shlex
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import signal

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
from pathlib import Path
from urllib.parse import quote, unquote, urlparse

from helper_common import export_service, set_pdeathsig

KACTIVITIES_DB = Path.home() / ".local/share/kactivitymanagerd/resources/database"
def _xdg_application_dirs():
    """applications/ dirs in XDG lookup order: the user's data home first, so user overrides
    win, then $XDG_DATA_DIRS, then Flatpak/Snap export dirs that may not be listed there."""
    data_home = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    data_dirs = (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    dirs = [os.path.join(data_home, "applications")]
    dirs += [os.path.join(d, "applications") for d in data_dirs if d]
    dirs += [
        str(Path.home() / ".local/share/flatpak/exports/share/applications"),
        "/var/lib/flatpak/exports/share/applications",
        "/var/lib/snapd/desktop/applications",
    ]
    unique = []
    for d in dirs:
        if d not in unique:
            unique.append(d)
    return unique


DESKTOP_DIRS = _xdg_application_dirs()
MAX_RECENT = 5

# KDE icon names for common mime type groups
MIME_ICON_MAP = {
    "inode/directory": "inode-directory",
    "application/pdf": "application-pdf",
    "text/plain": "text-x-generic",
    "text/html": "text-html",
    "image/": "image-x-generic",
    "video/": "video-x-generic",
    "audio/": "audio-x-generic",
    "application/vnd.oasis": "x-office-document",
    "application/vnd.openxml": "x-office-document",
    "application/zip": "application-zip",
}


def read_desktop_file(path):
    """Parse a desktop file, or None. Lenient like desktop-file readers: duplicate keys and
    sections are allowed (last wins), no interpolation, key case preserved."""
    cp = configparser.RawConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    try:
        with open(path, encoding="utf-8") as f:
            cp.read_file(f)
    except (configparser.Error, OSError, UnicodeDecodeError):
        return None
    return cp if cp.has_section("Desktop Entry") else None


def _find_in_desktop_dirs(name):
    """First DESKTOP_DIRS entry holding name (".desktop" appended if missing), or None."""
    if not name.endswith(".desktop"):
        name += ".desktop"
    for d in DESKTOP_DIRS:
        candidate = os.path.join(d, name)
        if os.path.isfile(candidate):
            return candidate
    return None


def resolve_launcher_url(url_str):
    """Convert a launcher URL to a local .desktop file path."""
    if not url_str:
        return None

    parsed = urlparse(url_str)

    if parsed.scheme == "file":
        path = unquote(parsed.path)
        if os.path.isfile(path):
            return path

    if parsed.scheme == "applications" or parsed.scheme == "":
        found = _find_in_desktop_dirs(parsed.path.lstrip("/"))
        if found:
            return found

    # Bare name (e.g. "org.kde.dolphin.desktop")
    if parsed.scheme == "" and os.path.sep not in url_str:
        return _find_in_desktop_dirs(url_str)

    return None


def get_jump_list_actions(desktop_path):
    """Parse [Desktop Action ...] sections from a .desktop file."""
    actions = []
    if not desktop_path or not os.path.isfile(desktop_path):
        return actions

    cp = read_desktop_file(desktop_path)
    if cp is None:
        return actions

    action_ids = cp.get("Desktop Entry", "Actions", fallback="").strip(";").split(";")
    action_ids = [a.strip() for a in action_ids if a.strip()]

    # Determine system languages (e.g. from LANGUAGE, LC_ALL, LC_MESSAGES, or LANG)
    lang_envs = [
        os.environ.get("LANGUAGE", ""),
        os.environ.get("LC_ALL", ""),
        os.environ.get("LC_MESSAGES", ""),
        os.environ.get("LANG", "")
    ]
    lang_env = ":".join(filter(None, lang_envs))
    langs = []
    for l in lang_env.split(":"):
        l = l.split(".")[0].strip() # e.g. ru_RU.UTF-8 -> ru_RU
        if l and l not in langs:
            langs.append(l)
            short = l.split("_")[0]
            if short not in langs:
                langs.append(short)

    for aid in action_ids:
        section = f"Desktop Action {aid}"
        if not cp.has_section(section):
            continue

        name = None
        # Try localized names
        for l in langs:
            name = cp.get(section, f"Name[{l}]", fallback=None)
            if name is not None:
                break
        
        if name is None:
            name = cp.get(section, "Name", fallback="")
            
        icon = cp.get(section, "Icon", fallback="")
        exec_cmd = cp.get(section, "Exec", fallback="")

        if not name:
            continue

        actions.append({"name": name, "icon": icon, "exec": exec_cmd, "actionId": aid})

    return actions


def get_storage_id(desktop_path):
    """Extract the storage ID (agent name) from a .desktop file path.
    KActivities uses the desktop file basename without .desktop as the agent."""
    if not desktop_path:
        return None
    basename = os.path.basename(desktop_path)
    if basename.endswith(".desktop"):
        return basename[:-8]
    return basename


_session_bus = None


def _get_session_bus():
    """Return a cached session bus connection shared by all D-Bus helper calls."""
    global _session_bus
    if _session_bus is None:
        _session_bus = dbus.SessionBus()
    return _session_bus


# Current activity as last read or announced by kactivitymanagerd; None = unknown, ask again.
# Only used once the change signals are subscribed, so it can't go stale.
_current_activity = None
_activity_signals_subscribed = False


def _on_current_activity_changed(activity):
    global _current_activity
    _current_activity = str(activity)


def _on_activity_manager_owner_changed(name, old_owner, new_owner):
    # kactivitymanagerd restarted or quit: forget the cached activity
    global _current_activity
    _current_activity = None


def _subscribe_activity_signals(bus):
    global _activity_signals_subscribed
    if _activity_signals_subscribed:
        return
    try:
        bus.add_signal_receiver(
            _on_current_activity_changed,
            signal_name="CurrentActivityChanged",
            dbus_interface="org.kde.ActivityManager.Activities",
            bus_name="org.kde.ActivityManager",
            path="/ActivityManager/Activities",
        )
        bus.add_signal_receiver(
            _on_activity_manager_owner_changed,
            signal_name="NameOwnerChanged",
            dbus_interface="org.freedesktop.DBus",
            bus_name="org.freedesktop.DBus",
            arg0="org.kde.ActivityManager",
        )
        _activity_signals_subscribed = True
    except Exception as e:
        print(f"desktop_actions: activity signal subscription failed: {e}", file=sys.stderr)


def get_current_activity():
    """Get current KDE activity ID via D-Bus (cached, kept current by CurrentActivityChanged)."""
    global _current_activity
    if _activity_signals_subscribed and _current_activity:
        return _current_activity
    try:
        bus = _get_session_bus()
        # Subscribe before reading, so a switch right after the read is not missed
        _subscribe_activity_signals(bus)
        # Bounded timeout: this runs on the service's single mainloop, so a hung
        # ActivityManager must not be able to freeze every tooltip/menu query.
        activity = bus.call_blocking(
            "org.kde.ActivityManager",
            "/ActivityManager/Activities",
            "org.kde.ActivityManager.Activities",
            "CurrentActivity", "", [],
            timeout=2.0,
        )
        _current_activity = str(activity) or None
        return str(activity)
    except Exception:
        return None


def guess_icon_for_mime(mime_type):
    """Map a MIME type to a freedesktop icon name."""
    if not mime_type:
        return "unknown"
    for prefix, icon in MIME_ICON_MAP.items():
        if mime_type.startswith(prefix):
            return icon
    # Generic: replace / with - for freedesktop naming
    return mime_type.replace("/", "-")


def get_recent_documents(desktop_path):
    """Query KActivities database for recent documents opened by this app."""
    docs = []
    if not KACTIVITIES_DB.is_file():
        return docs

    storage_id = get_storage_id(desktop_path)
    if not storage_id:
        return docs

    activity = get_current_activity()
    if not activity:
        return docs

    try:
        # Read-only with a timeout: kactivitymanagerd may be writing to it
        conn = sqlite3.connect(f"file:{quote(str(KACTIVITIES_DB))}?mode=ro", uri=True, timeout=2)
        cur = conn.cursor()
        cur.execute("""
            SELECT re.targettedResource, ri.mimetype, MAX(re.start) as lastUpdate
            FROM ResourceEvent re
            LEFT JOIN ResourceInfo ri ON re.targettedResource = ri.targettedResource
            WHERE re.initiatingAgent = ?
            AND re.usedActivity = ?
            GROUP BY re.targettedResource
            ORDER BY lastUpdate DESC
            LIMIT ?
        """, (storage_id, activity, MAX_RECENT * 2))

        seen = set()
        for row in cur.fetchall():
            resource = row[0]
            mimetype = row[1]

            if not resource:
                continue

            # Parse file path
            file_path = resource
            if file_path.startswith("file://"):
                file_path = unquote(file_path[7:])
            
            # Kickoff typically checks if local files exist, but we still allow valid KDE URLs
            if file_path.startswith("/"):
                if not os.path.exists(file_path):
                    continue
            elif file_path.startswith("zip://") or file_path.startswith("tar://") or file_path.startswith("krarc://"):
                # For virtual KDE KIO paths, we try to extract the base archive path and verify if the archive still exists
                protocol_end = file_path.find("://") + 3
                archive_path = file_path[protocol_end:]
                # Split at the first well-known archive extension 
                for ext in [".zip/", ".tar/", ".tar.gz/", ".xz/", ".bz2/", ".rar/"]:
                    if ext in archive_path:
                        real_archive = archive_path[:archive_path.find(ext) + len(ext) - 1]
                        if not os.path.exists(real_archive):
                            file_path = None # Mark as non-existent
                        break
                
                if file_path is None:
                    continue
            elif file_path.startswith("trash:/"):
                # Always allow opening the root Trash folder in Dolphin
                if file_path != "trash:/" and file_path != "trash://":
                    # Specific deleted files (trash:/file.txt) shouldn't be opened directly
                    continue
            elif file_path.startswith("mailto:"):
                # Filter out mailto protocols (e.g. recent emails composed, not actual documents)
                continue
            
            # Determine icon and name
            icon_name = guess_icon_for_mime(mimetype)
            name = os.path.basename(file_path) if file_path.startswith("/") else file_path

            if file_path not in seen:
                seen.add(file_path)
                url = f"file://{quote(file_path)}" if file_path.startswith("/") else file_path
                docs.append({
                    "name": name,
                    "url": url,
                    "icon": icon_name,
                    "mimeType": mimetype or ""
                })
            
            if len(docs) >= MAX_RECENT:
                break

        conn.close()
    except Exception as e:
        print(f"desktop_actions: DB error: {e}", file=sys.stderr)

    return docs


def find_active_db_from_proc(db_name, app_pid=0):
    """Find the active database path by inspecting open file descriptors of the given PID and its parent PPID."""
    if app_pid <= 0:
        return None
    try:
        pids = [app_pid]
        # Browser renderers may have child PIDs while the main process owns the DB handle.
        # Inspect parent PID as well to cover multi-process architectures.
        ppid = parent_pids(str(app_pid)).get(str(app_pid), 0)
        if ppid > 0:
            pids.append(ppid)

        for pid in set(pids):
            fd_dir = Path(f"/proc/{pid}/fd")
            if not fd_dir.exists():
                continue
            try:
                for fd in fd_dir.iterdir():
                    try:
                        target = os.readlink(fd)
                        if os.path.basename(target) == db_name and os.path.isfile(target):
                            return Path(target)
                    except (OSError, PermissionError):
                        continue
            except (OSError, PermissionError):
                continue
    except Exception as e:
        print(f"desktop_actions: proc scan error: {e}", file=sys.stderr)
    return None


def snapshot_sqlite(db_path, temp_db):
    """Copy a live SQLite DB plus its -wal sidecar so uncheckpointed rows are included."""
    shutil.copy2(db_path, temp_db)
    wal = Path(f"{db_path}-wal")
    if wal.is_file():
        shutil.copy2(wal, f"{temp_db}-wal")


def remove_sqlite_snapshot(temp_db):
    for path in (Path(temp_db), Path(f"{temp_db}-wal"), Path(f"{temp_db}-shm")):
        try:
            path.unlink()
        except OSError:
            pass


FIREFOX_HISTORY_SQL = """
    SELECT DISTINCT url, title FROM moz_places
    WHERE last_visit_date IS NOT NULL AND title IS NOT NULL AND url LIKE 'http%'
    ORDER BY last_visit_date DESC LIMIT ?
"""

CHROMIUM_HISTORY_SQL = """
    SELECT DISTINCT url, title FROM urls
    WHERE last_visit_time IS NOT NULL AND title IS NOT NULL AND url LIKE 'http%'
    ORDER BY last_visit_time DESC LIMIT ?
"""

FIREFOX_FAVICON_SQL = """
    SELECT i.data FROM moz_icons i
    JOIN moz_icons_to_pages itp ON itp.icon_id = i.id
    JOIN moz_pages_w_icons p ON p.id = itp.page_id
    WHERE p.page_url = ? AND i.data IS NOT NULL
    ORDER BY i.width DESC LIMIT 1
"""

CHROMIUM_FAVICON_SQL = """
    SELECT b.image_data FROM favicon_bitmaps b
    JOIN icon_mapping m ON m.icon_id = b.icon_id
    WHERE m.page_url = ? AND b.image_data IS NOT NULL
    ORDER BY b.width DESC LIMIT 1
"""

FIREFOX_PROFILE_ROOTS = [
    Path.home() / ".mozilla" / "firefox",
    Path.home() / ".config" / "mozilla" / "firefox",
    Path.home() / ".var" / "app" / "org.mozilla.firefox" / ".mozilla" / "firefox",
    Path.home() / ".var" / "app" / "org.mozilla.firefox-trunk" / ".mozilla" / "firefox",
    Path.home() / "snap" / "firefox" / "common" / ".mozilla" / "firefox",
]

# Chromium-family browser -> its config dirs. The order is the detection order of
# chromium_browser_for(): the first key found in the desktop file name wins.
CHROMIUM_PROFILE_ROOTS = {
    "chrome": [
        Path.home() / ".config" / "google-chrome",
        Path.home() / ".var" / "app" / "com.google.Chrome" / "config" / "google-chrome",
    ],
    "brave": [
        Path.home() / ".config" / "BraveSoftware" / "Brave-Browser",
        Path.home() / ".var" / "app" / "com.brave.Browser" / "config" / "BraveSoftware" / "Brave-Browser",
    ],
    "vivaldi": [
        Path.home() / ".config" / "vivaldi",
        Path.home() / ".var" / "app" / "com.vivaldi.Vivaldi" / "config" / "vivaldi",
    ],
    "chromium": [
        Path.home() / ".config" / "chromium",
        Path.home() / ".var" / "app" / "org.chromium.Chromium" / "config" / "chromium",
    ],
    "edge": [
        Path.home() / ".config" / "microsoft-edge",
        Path.home() / ".var" / "app" / "com.microsoft.Edge" / "config" / "microsoft-edge",
    ],
    "opera": [
        Path.home() / ".config" / "opera",
        Path.home() / ".var" / "app" / "com.opera.Opera" / "config" / "opera",
    ],
}


def is_firefox_desktop(desktop_path):
    """Firefox or a Firefox PWA (firefoxpwa "FFPWA-..." desktop files)."""
    name = os.path.basename(desktop_path).lower()
    return "firefox" in name or "ffpwa" in name


def chromium_browser_for(desktop_path):
    """CHROMIUM_PROFILE_ROOTS key matching a desktop file name, or None."""
    name = os.path.basename(desktop_path).lower()
    return next((browser for browser in CHROMIUM_PROFILE_ROOTS if browser in name), None)


def extract_favicons(history_items, favicons_db_path, browser_type):
    """Extract favicons for history items and save them to local cache."""
    if not history_items or not favicons_db_path or not os.path.exists(favicons_db_path):
        return history_items

    cache_dir = Path.home() / ".cache" / "taskline" / "favicons"
    cache_dir.mkdir(parents=True, exist_ok=True)

    urls_to_query = []
    for item in history_items:
        url = item.get("url")
        if not url:
            continue
        url_hash = hashlib.md5(url.encode('utf-8')).hexdigest()
        
        cached_png = cache_dir / f"{url_hash}.png"
        cached_failed = cache_dir / f"{url_hash}.failed"
        
        if cached_png.exists():
            item["icon"] = f"file://{cached_png}"
        elif cached_failed.exists():
            item["icon"] = "internet-services"
        else:
            urls_to_query.append((url, item, cached_png, cached_failed))

    if not urls_to_query:
        return history_items

    fd, temp_path = tempfile.mkstemp(prefix="favicons_temp.sqlite")
    os.close(fd)
    temp_db = Path(temp_path)

    try:
        snapshot_sqlite(favicons_db_path, temp_db)
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()

        query = FIREFOX_FAVICON_SQL if browser_type == "firefox" else CHROMIUM_FAVICON_SQL
        for url, item, cached_png, cached_failed in urls_to_query:
            cursor.execute(query, (url,))
            row = cursor.fetchone()
            blob = row[0] if row else None

            if blob:
                try:
                    with open(cached_png, "wb") as f:
                        f.write(blob)
                    item["icon"] = f"file://{cached_png}"
                except Exception as e:
                    print(f"desktop_actions: failed to write favicon cache: {e}", file=sys.stderr)
                    item["icon"] = "internet-services"
            else:
                try:
                    with open(cached_failed, "w") as f:
                        f.write("")
                except Exception:
                    pass
                item["icon"] = "internet-services"

        conn.close()
    except Exception as e:
        print(f"desktop_actions: extract_favicons error: {e}", file=sys.stderr)
    finally:
        remove_sqlite_snapshot(temp_db)

    return history_items


def get_firefox_recent(limit=10, app_pid=0):
    """Fetch recent Firefox history with active profile detection via process info and fallback."""
    # 1. Try to find active profile via /proc using app_pid
    active_db = find_active_db_from_proc("places.sqlite", app_pid=app_pid)
    # 2. Fallback to the most recently used profile
    db_path = active_db or _newest_firefox_places()
    if not db_path:
        return []
    temp_name = "places_ff_active.sqlite" if active_db else "places_ff_recent.sqlite"
    history = fetch_sqlite_history(db_path, FIREFOX_HISTORY_SQL, temp_name, limit)
    return extract_favicons(history, db_path.parent / "favicons.sqlite", "firefox")


def _newest_firefox_places():
    """places.sqlite of the most recently written Firefox profile, or None."""
    candidates = []
    for d in FIREFOX_PROFILE_ROOTS:
        if d.exists() and (d / "profiles.ini").exists():
            try:
                config = configparser.ConfigParser()
                config.read(d / "profiles.ini")
                for section in config.sections():
                    p_dir = config[section].get("Path") if section.startswith("Profile") else config[section].get("Default") if section.startswith("Install") else None
                    if p_dir:
                        full_path = d / p_dir if config[section].get("IsRelative", "1") == "1" else Path(p_dir)
                        if (full_path / "places.sqlite").exists():
                            candidates.append(full_path / "places.sqlite")
            except Exception: continue

    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def get_chromium_recent(browser_name, limit=10, app_pid=0):
    """Fetch recent history for Chromium-based browsers with active profile detection."""
    # 1. Try to find active profile via /proc using app_pid
    active_db = find_active_db_from_proc("History", app_pid=app_pid)
    # 2. Fallback to the most recently used profile
    db_path = active_db or _newest_chromium_history(browser_name)
    if not db_path:
        return []
    temp_name = f"history_{browser_name}_{'active' if active_db else 'recent'}.sqlite"
    history = fetch_sqlite_history(db_path, CHROMIUM_HISTORY_SQL, temp_name, limit)
    return extract_favicons(history, db_path.parent / "Favicons", "chromium")


def _newest_chromium_history(browser_name):
    """History DB of the most recently written profile of a Chromium-family browser, or None."""
    candidates = []
    for base in CHROMIUM_PROFILE_ROOTS.get(browser_name, []):
        if not base.exists(): continue
        # Common profile names
        for profile in ["Default", "Profile 1", "Profile 2", "."]:
            history_db = base / profile / "History"
            if history_db.exists():
                candidates.append(history_db)

    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


# (db path, query, limit) -> (file signature, rows); avoids re-copying an unchanged history DB
_history_cache = {}


def sqlite_signature(db_path):
    """mtime/size of a DB and its -wal file; changes whenever the browser writes history."""
    sig = []
    for path in (Path(db_path), Path(f"{db_path}-wal")):
        try:
            st = path.stat()
            sig.append((st.st_mtime_ns, st.st_size))
        except OSError:
            sig.append(None)
    return tuple(sig)


def fetch_sqlite_history(db_path, query, temp_name, limit=10):
    """Generic helper to fetch history from a SQLite DB using a temporary copy."""
    cache_key = (str(db_path), query, limit)
    signature = sqlite_signature(db_path)
    cached = _history_cache.get(cache_key)
    if cached and cached[0] == signature:
        return [dict(item) for item in cached[1]]

    docs = []
    # Use tempfile to avoid collisions and permission issues in /tmp
    fd, temp_path = tempfile.mkstemp(prefix=temp_name)
    os.close(fd)
    temp_db = Path(temp_path)
    
    try:
        snapshot_sqlite(db_path, temp_db)
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        cursor.execute(query, (limit * 3,))
        
        seen_urls = set()
        seen_titles = set()
        for url, title in cursor.fetchall():
            norm_url = url.split('#')[0].rstrip('/')
            if norm_url in seen_urls or title in seen_titles:
                continue
            seen_urls.add(norm_url)
            seen_titles.add(title)
            docs.append({"name": title, "url": url, "icon": "internet-services", "mimeType": "text/html"})
            if len(docs) >= limit: break
        conn.close()
        _history_cache[cache_key] = (signature, [dict(item) for item in docs])
    except Exception as e:
        print(f"desktop_actions: fetch_history error ({db_path}): {e}", file=sys.stderr)
    finally:
        remove_sqlite_snapshot(temp_db)
    return docs


def clear_recent_documents(desktop_path):
    """Clear recent documents for this application from both score cache and event history."""
    if not KACTIVITIES_DB.is_file():
        return False

    storage_id = get_storage_id(desktop_path)
    if not storage_id:
        return False

    activity = get_current_activity()
    if not activity:
        return False

    try:
        # Use a context manager to ensure the connection is closed properly.
        # We need to delete from BOTH tables to keep the daemon happy.
        with sqlite3.connect(str(KACTIVITIES_DB), timeout=5) as conn:
            cur = conn.cursor()
            # 1. Clear the score cache
            cur.execute("""
                DELETE FROM ResourceScoreCache 
                WHERE initiatingAgent = ? AND usedActivity = ?
            """, (storage_id, activity))
            
            # 2. Clear the event history
            cur.execute("""
                DELETE FROM ResourceEvent 
                WHERE initiatingAgent = ? AND usedActivity = ?
            """, (storage_id, activity))
            
            # 3. Clear the resource links (this is likely what was missing for full reset)
            cur.execute("""
                DELETE FROM ResourceLink 
                WHERE initiatingAgent = ? AND usedActivity = ?
            """, (storage_id, activity))
            
            conn.commit()
            # Ensure changes are written and visible to others
            cur.execute("PRAGMA wal_checkpoint(FULL)")
        
        # Notify the daemon that stats have changed via D-Bus
        try:
            bus = _get_session_bus()
            bus.call_blocking(
                "org.kde.ActivityManager",
                "/ActivityManager/Resources/Scoring",
                "org.freedesktop.DBus.Properties",
                "EmitChanged", "s", ["org.kde.ActivityManager.ResourcesScoring"],
                timeout=1.0,
            )
        except Exception:
            pass  # Non-critical: daemon will detect DB changes on next query
        
        return True
    except Exception as e:
        print(f"desktop_actions: DB clear error: {e}", file=sys.stderr)
        return False


def get_kde_places():
    """Parse ~/.local/share/user-places.xbel to get KDE Places."""
    places = []
    xbel_path = Path.home() / ".local/share/user-places.xbel"
    if not xbel_path.exists():
        return places

    try:
        # Standard XBEL doesn't use namespaces for title/bookmark, 
        # but KDE adds metadata in its own namespaces.
        tree = ET.parse(xbel_path)
        root = tree.getroot()
        
        for bookmark in root.findall('bookmark'):
            href = bookmark.get('href')
            title_node = bookmark.find('title')
            title = title_node.text if title_node is not None else href
            
            icon = "folder"
            is_hidden = False
            
            # Metadata for icon and hidden state
            # Metadata nodes can have owner="http://freedesktop.org" or "http://www.kde.org"
            for info in bookmark.findall('info'):
                for metadata in info.findall('metadata'):
                    owner = metadata.get('owner')
                    if owner == "http://freedesktop.org":
                        # Look for <bookmark:icon name="..."/>
                        # XBEL spec uses http://www.freedesktop.org/standards/desktop-bookmarks namespace
                        icon_node = metadata.find('{http://www.freedesktop.org/standards/desktop-bookmarks}icon')
                        if icon_node is not None:
                            icon = icon_node.get('name')
                    elif owner == "http://www.kde.org":
                        hidden_node = metadata.find('IsHidden')
                        if hidden_node is not None and hidden_node.text == "true":
                            is_hidden = True

            if not is_hidden:
                places.append({
                    "name": title,
                    "url": href,
                    "icon": icon
                })
    except Exception:
        pass

    return places


class DesktopActionsService(dbus.service.Object):
    def __init__(self):
        # If another task manager instance already runs the service, this one exits: it serves everyone.
        self.bus, self.bus_name = export_service(
            self, 'io.github.divinae.taskline.DesktopActions', '/DesktopActions',
            ready_msg="DesktopActionsService ready",
            running_msg="DesktopActionsService already running",
            error_prefix="DesktopActionsService error")

    @dbus.service.method('io.github.divinae.taskline.DesktopActions', in_signature='sbii', out_signature='s')
    def Query(self, launcher_url, show_history, limit, app_pid):
        desktop_path = resolve_launcher_url(launcher_url)
        jump_list = get_jump_list_actions(desktop_path) if desktop_path else []
        
        browser_history = []
        if desktop_path and show_history:
            if is_firefox_desktop(desktop_path):
                browser_history = get_firefox_recent(limit, app_pid)
            else:
                chromium = chromium_browser_for(desktop_path)
                if chromium:
                    browser_history = get_chromium_recent(chromium, limit, app_pid)
        
        raw_recent = get_recent_documents(desktop_path) if desktop_path else []
        
        # Filter/Split recent items
        recent_docs = []
        recent_folders = []
        browser_urls = {item['url'] for item in browser_history}
        
        for doc in raw_recent:
            if doc['url'] in browser_urls:
                continue
            
            if doc.get('mimeType') == 'inode/directory':
                recent_folders.append(doc)
            else:
                recent_docs.append(doc)
        
        places = []
        if desktop_path and "dolphin" in desktop_path.lower():
            places = get_kde_places()

        data = {
            "jumpList": jump_list,
            "recentDocs": recent_docs,
            "recentFolders": recent_folders,
            "browserHistory": browser_history,
            "places": places,
            "desktopPath": desktop_path or "",
        }
        return json.dumps(data)

    @dbus.service.method('io.github.divinae.taskline.DesktopActions', in_signature='s', out_signature='')
    def ClearRecent(self, launcher_url):
        desktop_path = resolve_launcher_url(launcher_url)
        if desktop_path:
            clear_recent_documents(desktop_path)

    @dbus.service.method('io.github.divinae.taskline.DesktopActions', in_signature='s', out_signature='')
    def Execute(self, exec_cmd):
        try:
            subprocess.Popen(expand_exec(exec_cmd), start_new_session=True)
        except Exception as e:
            print(f"Execute error: {e}", file=sys.stderr)

    @dbus.service.method('io.github.divinae.taskline.DesktopActions', in_signature='s', out_signature='s')
    def ParentPids(self, pids_csv):
        """JSON {pid: parentPid} for comma-separated PIDs (QML can't read /proc).

        Chromium-family browsers play audio from a utility child process, so its stream PID
        only matches a window through its parent. (Ported from upstream 968431f.)
        """
        return json.dumps(parent_pids(pids_csv))

    @dbus.service.method('io.github.divinae.taskline.DesktopActions', in_signature='as', out_signature='s')
    def WebAppLaunchers(self, launcher_urls):
        """JSON list of the given launcher URLs that are browser web apps (--app=URL)."""
        return json.dumps([str(u) for u in launcher_urls if web_app_host(resolve_launcher_url(str(u)))])

    @dbus.service.method('io.github.divinae.taskline.DesktopActions', in_signature='as', out_signature='s')
    def WebAppTracks(self, launcher_urls):
        """JSON {launcherUrl: {"track", "pid"}} for open browser web app windows (e.g. a
        Spotify app) whose site a playing browser MPRIS player is playing from."""
        try:
            players = mpris_url_tracks(self.bus)
        except dbus.exceptions.DBusException:
            players = []
        return json.dumps(web_app_tracks([str(u) for u in launcher_urls], players))

    @dbus.service.method('io.github.divinae.taskline.DesktopActions', in_signature='s', out_signature='i')
    def AutostartState(self, launcher_url):
        """1 = starts at login, 0 = doesn't, -1 = not manageable (no desktop file)."""
        return autostart_state(resolve_launcher_url(launcher_url))

    @dbus.service.method('io.github.divinae.taskline.DesktopActions', in_signature='sb', out_signature='b')
    def SetAutostart(self, launcher_url, enabled):
        return set_autostart(resolve_launcher_url(launcher_url), bool(enabled))

    @dbus.service.method('io.github.divinae.taskline.DesktopActions', in_signature='i', out_signature='s')
    def KillApp(self, pid):
        """Force quit an app: SIGTERM now, SIGKILL after 3 s if it is still running."""
        # Never this helper, its parent (plasmashell) or init
        error = kill_app_error(pid, protected_pids=(os.getpid(), os.getppid()))
        if error:
            return f"ERROR: {error}"
        pid = int(pid)
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError as e:
            return f"ERROR: {e}"

        def kill_if_alive():
            if kill_app_error(pid) is None:
                try:
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass
            return False  # one-shot GLib timeout

        GLib.timeout_add(3000, kill_if_alive)
        return "OK"

    @dbus.service.method('io.github.divinae.taskline.DesktopActions', in_signature='i', out_signature='i')
    def PanelVisibility(self, containment_id):
        """Visibility mode of a panel from plasmashellrc, or -1 if unknown.

        0 = always visible, 1 = auto-hide, 2 = windows can cover, 3 = windows go below,
        4 = dodge windows.
        """
        return panel_visibility(containment_id)

    @dbus.service.method('io.github.divinae.taskline.Config', in_signature='ss', out_signature='s')
    def ExportConfig(self, path, content):
        try:
            with open(path, 'w', encoding='utf-8') as f:
                f.write(content)
            return "OK"
        except Exception as e:
            return f"ERROR: {e}"

    @dbus.service.method('io.github.divinae.taskline.Config', in_signature='s', out_signature='s')
    def ImportConfig(self, path):
        # "OK:" prefix so file contents can't be mistaken for an error or a D-Bus failure
        try:
            with open(path, 'r', encoding='utf-8-sig') as f:
                return "OK:" + f.read()
        except Exception as e:
            return f"ERROR: {e}"

    @dbus.service.method('io.github.divinae.taskline.DesktopActions', in_signature='ss', out_signature='')
    def OpenUrl(self, url, preferred_app):
        try:
            desktop_path = resolve_launcher_url(preferred_app)
            if desktop_path:
                exec_cmd = get_desktop_exec(desktop_path)
                if exec_cmd:
                    # If the command expects a custom protocol but we are opening a standard HTTP/HTTPS web URL,
                    # dynamically switch --protocol to --url to ensure correct document loading.
                    if url.lower().startswith("http") and "--protocol" in exec_cmd:
                        exec_cmd = exec_cmd.replace("--protocol", "--url")
                    
                    subprocess.Popen(expand_exec(exec_cmd, url), start_new_session=True)
                    return
            
            # Fallback to default browser
            subprocess.Popen(['xdg-open', url])
        except Exception: pass


def expand_exec(exec_cmd, url=None):
    """Split a desktop entry Exec line into argv and expand its field codes.

    The URL is inserted as a single argument (never re-parsed), %f/%F get a local
    path for file:// URLs, and field codes we don't support (%i, %c, %k, ...) are dropped.
    """
    target = url
    if url and url.startswith("file://"):
        local_path = unquote(urlparse(url).path)
    else:
        local_path = url

    argv = []
    used_url = False
    for token in shlex.split(exec_cmd):
        if token in ("%u", "%U", "%f", "%F"):
            if url:
                argv.append(target if token in ("%u", "%U") else local_path)
                used_url = True
            continue

        def field(m):
            nonlocal used_url
            code = m.group(1)
            if code == "%":
                return "%"
            if url and code in "uUfF":
                used_url = True
                return target if code in "uU" else local_path
            return ""

        token = re.sub(r"%(.)", field, token)
        if token:
            argv.append(token)

    if url and not used_url:
        argv.append(url)
    return argv


def panel_visibility(containment_id, rc_path=None):
    """Read panelVisibility of [PlasmaViews][Panel <id>] from plasmashellrc (-1 if unknown)."""
    rc_path = rc_path or (Path.home() / ".config" / "plasmashellrc")
    header = f"[PlasmaViews][Panel {int(containment_id)}]"
    try:
        in_group = False
        for line in Path(rc_path).read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("["):
                in_group = line == header
            elif in_group and line.startswith("panelVisibility="):
                return int(line.split("=", 1)[1])
    except (OSError, ValueError):
        pass
    return -1


AUTOSTART_MARKER = "X-Taskline-Autostart"
# Marker written by Fancy Tasks NG builds of this code; entries carrying it are ours too
LEGACY_AUTOSTART_MARKERS = ("X-FancyTasksNG-Autostart",)


def user_autostart_dir():
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "autostart"


def system_autostart_dirs():
    config_dirs = (os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg").split(":")
    return [os.path.join(d, "autostart") for d in config_dirs if d]


def desktop_file_id(desktop_path, app_dirs=None):
    """Desktop file ID per the XDG spec: path relative to an applications dir, '/' -> '-'."""
    path = os.path.abspath(desktop_path)
    for app_dir in (app_dirs or DESKTOP_DIRS):
        app_dir = os.path.abspath(app_dir)
        if path.startswith(app_dir + os.sep):
            return os.path.relpath(path, app_dir).replace(os.sep, "-")
    return os.path.basename(path)


def parent_pids(pids_csv, proc_root="/proc"):
    """{pid: parentPid} for comma-separated PIDs; PIDs that no longer exist are omitted."""
    result = {}
    for token in str(pids_csv).split(","):
        token = token.strip()
        if not token.isdigit():
            continue
        try:
            with open(f"{proc_root}/{token}/status", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("PPid:"):
                        result[token] = int(line.split()[1])
                        break
        except (OSError, ValueError, IndexError):
            pass
    return result


def url_host(url):
    """Host of a URL without a leading "www.", lowercased ("" if none)."""
    host = (urlparse(str(url)).hostname or "").lower()
    return host[4:] if host.startswith("www.") else host


# desktop path -> ((st_mtime_ns, st_size), host); WebAppTracks asks for every task every few
# seconds while media plays, so a desktop file is only parsed again after it changed
_web_app_host_cache = {}


def web_app_host(desktop_path):
    """Host of a browser web app (Exec ... --app=URL / --app URL), or "" for normal apps."""
    if not desktop_path:
        return ""
    try:
        st = os.stat(desktop_path)
    except OSError:
        return ""
    signature = (st.st_mtime_ns, st.st_size)
    cached = _web_app_host_cache.get(desktop_path)
    if cached and cached[0] == signature:
        return cached[1]
    host = _parse_web_app_host(desktop_path)
    _web_app_host_cache[desktop_path] = (signature, host)
    return host


def _parse_web_app_host(desktop_path):
    exec_cmd = get_desktop_exec(desktop_path)
    if not exec_cmd:
        return ""
    try:
        args = shlex.split(exec_cmd)
    except ValueError:
        return ""
    for n, arg in enumerate(args):
        if arg.startswith("--app="):
            return url_host(arg[len("--app="):])
        if arg == "--app" and n + 1 < len(args):
            return url_host(args[n + 1])
    return ""


def mpris_url_tracks(bus):
    """Playing MPRIS players that report the URL they play from (browsers):
    list of {"host", "track", "pid"} where pid is the player's D-Bus connection process."""
    players = []
    bus_obj = bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus")
    for name in bus.list_names():
        if not str(name).startswith("org.mpris.MediaPlayer2."):
            continue
        try:
            player = bus.get_object(name, "/org/mpris/MediaPlayer2")
            props = player.GetAll("org.mpris.MediaPlayer2.Player",
                                  dbus_interface="org.freedesktop.DBus.Properties", timeout=1)
            pid = int(bus_obj.GetConnectionUnixProcessID(name, dbus_interface="org.freedesktop.DBus", timeout=1))
        except dbus.exceptions.DBusException:
            continue
        if str(props.get("PlaybackStatus", "")) != "Playing":
            continue
        metadata = props.get("Metadata", {})
        host = url_host(metadata.get("xesam:url", ""))
        track = str(metadata.get("xesam:title", ""))
        if host and track:
            players.append({"host": host, "track": track, "pid": pid})
    return players


def web_app_tracks(launcher_urls, players):
    """launcher URL -> {"track", "pid"} for web app windows whose site a playing player plays from."""
    result = {}
    for launcher_url in launcher_urls:
        host = web_app_host(resolve_launcher_url(launcher_url))
        if not host:
            continue
        for player in players:
            track_host = player["host"]
            if track_host == host or track_host.endswith("." + host) or host.endswith("." + track_host):
                result[launcher_url] = {"track": player["track"], "pid": player["pid"]}
                break
    return result


def autostart_path(desktop_path, autostart_dir=None, app_dirs=None):
    """Where the user autostart entry of a desktop file lives (<config home>/autostart/<id>)."""
    return Path(autostart_dir or user_autostart_dir()) / desktop_file_id(desktop_path, app_dirs)


def _entry_enabled(cp):
    entry = cp["Desktop Entry"]
    return (entry.get("Hidden", "false").strip().lower() != "true"
            and entry.get("X-GNOME-Autostart-enabled", "true").strip().lower() != "false")


def _set_entry_keys(text, changes):
    """Set (value) or remove (None) keys in the [Desktop Entry] group of desktop-file text,
    editing lines in place so comments, other groups and formatting are kept."""
    lines = text.splitlines()
    start = next((n for n, l in enumerate(lines) if l.strip() == "[Desktop Entry]"), None)
    if start is None:
        lines = ["[Desktop Entry]"] + lines
        start = 0
    end = next((n for n in range(start + 1, len(lines)) if lines[n].lstrip().startswith("[")), len(lines))
    group = lines[start + 1:end]
    for key, value in changes.items():
        group = [l for l in group if l.split("=", 1)[0].strip() != key]
        if value is not None:
            insert_at = len(group)
            while insert_at > 0 and not group[insert_at - 1].strip():
                insert_at -= 1
            group.insert(insert_at, f"{key}={value}")
    lines[start + 1:end] = group
    return "\n".join(lines) + "\n"


def _write_text(path, text):
    """Write a regular file, never through a symlink (replace the link instead)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        path.unlink()
    path.write_text(text, encoding="utf-8")


def autostart_state(desktop_path, autostart_dir=None, system_dirs=None, app_dirs=None):
    """1 = starts at login, 0 = doesn't, -1 = can't be managed (no .desktop file to start)."""
    if not desktop_path or not str(desktop_path).endswith(".desktop") or not os.path.isfile(desktop_path):
        return -1
    user = autostart_path(desktop_path, autostart_dir, app_dirs)
    if user.exists():
        cp = read_desktop_file(user)
        return 1 if cp and _entry_enabled(cp) else 0
    file_id = desktop_file_id(desktop_path, app_dirs)
    for system_dir in (system_autostart_dirs() if system_dirs is None else system_dirs):
        cp = read_desktop_file(Path(system_dir) / file_id)
        if cp:
            return 1 if _entry_enabled(cp) else 0
    return 0


def is_autostart(desktop_path, autostart_dir=None, system_dirs=None, app_dirs=None):
    return autostart_state(desktop_path, autostart_dir, system_dirs, app_dirs) == 1


def set_autostart(desktop_path, enabled, autostart_dir=None, system_dirs=None, app_dirs=None):
    """Turn autostart on/off without destroying entries the user wrote themselves.

    On: re-enable an existing user entry (drop Hidden / X-GNOME-Autostart-enabled=false), or copy
    the app's desktop file verbatim plus our marker. Off: delete the entry only if we created it;
    otherwise keep it and set Hidden=true. If a system-wide entry would still start the app,
    write a Hidden=true user override. A user entry we can't parse, or a symlinked one we can't
    edit safely, is replaced only when that cannot lose content. Returns the resulting state.
    """
    kw = dict(autostart_dir=autostart_dir, system_dirs=system_dirs, app_dirs=app_dirs)
    if autostart_state(desktop_path, **kw) == -1:
        return False
    user = autostart_path(desktop_path, autostart_dir, app_dirs)
    try:
        own_entry = False
        user_text = None
        if user.exists():
            cp = read_desktop_file(user)
            if cp is None:
                # Unreadable hand-made entry: leave it alone rather than overwrite it
                return is_autostart(desktop_path, **kw)
            own_entry = any(cp["Desktop Entry"].get(marker) == "true"
                            for marker in (AUTOSTART_MARKER,) + LEGACY_AUTOSTART_MARKERS)
            # A symlink's content lives elsewhere; edit a copy so the target is never touched
            user_text = user.read_text(encoding="utf-8")
        source_text = Path(desktop_path).read_text(encoding="utf-8")

        if enabled:
            if user_text is not None:
                _write_text(user, _set_entry_keys(user_text, {
                    "Hidden": None,
                    "X-GNOME-Autostart-enabled": None,
                }))
            if not is_autostart(desktop_path, **kw):
                _write_text(user, _set_entry_keys(source_text, {AUTOSTART_MARKER: "true", "Hidden": None}))
        else:
            if user_text is not None and own_entry:
                user.unlink()
            elif user_text is not None:
                _write_text(user, _set_entry_keys(user_text, {"Hidden": "true"}))
            if is_autostart(desktop_path, **kw):
                # Still started by a system-wide entry: override it
                _write_text(user, _set_entry_keys(source_text, {AUTOSTART_MARKER: "true", "Hidden": "true"}))
    except OSError as e:
        print(f"desktop_actions: autostart error: {e}", file=sys.stderr)
    return is_autostart(desktop_path, **kw)


def kill_app_error(pid, proc_root="/proc", own_uid=None, protected_pids=()):
    """Why a process must not be force-quit, or None if it may be."""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return "invalid pid"
    if pid <= 1 or pid in protected_pids:
        return "refusing to kill this process"
    try:
        uid = os.stat(f"{proc_root}/{pid}").st_uid
    except OSError:
        return "no such process"
    if uid != (os.getuid() if own_uid is None else own_uid):
        return "process belongs to another user"
    return None


def get_desktop_exec(desktop_path):
    """Helper to get the Exec line from a desktop file."""
    cp = read_desktop_file(desktop_path)
    return cp["Desktop Entry"].get("Exec") if cp else None

def main():
    set_pdeathsig()
    DBusGMainLoop(set_as_default=True)
    _service = DesktopActionsService()  # keep a reference for the lifetime of the loop
    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        sys.exit(0)

if __name__ == "__main__":
    main()
