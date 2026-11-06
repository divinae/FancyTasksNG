# SPDX-License-Identifier: GPL-2.0-or-later
"""Unit tests for the pure helpers in package/contents/ui/code/desktop_actions.py.

Run with: python3 -m unittest discover -s tests
"""

import importlib.util
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parent.parent / "package/contents/ui/code/desktop_actions.py"
# The helper imports helper_common from its own directory (on sys.path when run as a script)
sys.path.insert(0, str(MODULE_PATH.parent))
spec = importlib.util.spec_from_file_location("desktop_actions", MODULE_PATH)
da = importlib.util.module_from_spec(spec)
spec.loader.exec_module(da)


class ExpandExecTest(unittest.TestCase):
    def test_url_is_one_argument(self):
        url = "file:///home/u/My%20Report%27s.pdf"
        self.assertEqual(da.expand_exec("okular %U", url), ["okular", url])

    def test_file_codes_get_local_path(self):
        self.assertEqual(da.expand_exec("gimp %f", "file:///home/u/a%20b.png"), ["gimp", "/home/u/a b.png"])

    def test_remote_url_with_file_code_is_passed_through(self):
        self.assertEqual(da.expand_exec("app %F", "https://example.com/x"), ["app", "https://example.com/x"])

    def test_unsupported_codes_dropped_and_percent_escaped(self):
        self.assertEqual(da.expand_exec("app %i %c %k --pct 100%%"), ["app", "--pct", "100%"])

    def test_codes_removed_without_url(self):
        self.assertEqual(da.expand_exec("firefox %u --new-window"), ["firefox", "--new-window"])

    def test_url_appended_when_no_field_code(self):
        self.assertEqual(da.expand_exec("dolphin", "file:///tmp/x"), ["dolphin", "file:///tmp/x"])

    def test_code_inside_argument(self):
        self.assertEqual(da.expand_exec("app --url=%u", "https://a/b\\c"), ["app", "--url=https://a/b\\c"])

    def test_quoted_arguments(self):
        self.assertEqual(da.expand_exec('sh -c "echo hi"'), ["sh", "-c", "echo hi"])


class DesktopStringEscapeTest(unittest.TestCase):
    def test_unescape(self):
        self.assertEqual(da.unescape_desktop_string(r"a\sb\tc\nd\re\\f"), "a b\tc\nd\re\\f")
        # Not string escapes: left for the Exec quoting rules
        self.assertEqual(da.unescape_desktop_string(r'\"x\$'), r'\"x\$')

    def test_plain_exec_unchanged(self):
        self.assertEqual(da.unescape_desktop_string("app --new-window %U"), "app --new-window %U")

    def _exec_from_file(self, exec_line):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "x.desktop"
            path.write_text("[Desktop Entry]\nName=X\nExec=" + exec_line + "\nActions=a;\n"
                            "[Desktop Action a]\nName=A\nExec=" + exec_line + "\n", encoding="utf-8")
            exec_cmd = da.get_desktop_exec(str(path))
            self.assertEqual(da.get_jump_list_actions(str(path))[0]["exec"], exec_cmd)
            return da.expand_exec(exec_cmd)

    def test_escaped_quote_in_quoted_argument(self):
        # Exec=sh -c "echo \\"a b\\"": string unescape first (\\ -> \), then the quoting rules
        self.assertEqual(self._exec_from_file('sh -c "echo \\\\"a b\\\\""'), ["sh", "-c", 'echo "a b"'])

    def test_escaped_space_and_plain_exec(self):
        # \s is a plain space after unescaping: it splits unless quoted
        self.assertEqual(self._exec_from_file(r'app "--title=a\sb"'), ["app", "--title=a b"])
        self.assertEqual(self._exec_from_file(r"app a\sb"), ["app", "a", "b"])
        self.assertEqual(self._exec_from_file("app --new-window"), ["app", "--new-window"])


class DesktopFileTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.desktop = self.dir / "org.example.App.desktop"
        self.desktop.write_text(
            "[Desktop Entry]\n"
            "Name=App\n"
            "Exec=app %U\n"
            "Actions=new-window;private;missing;\n"
            "\n"
            "[Desktop Action new-window]\n"
            "Name=New Window\n"
            "Name[pl]=Nowe okno\n"
            "Exec=app --new-window\n"
            "Icon=window-new\n"
            "\n"
            "[Desktop Action private]\n"
            "Name=Private Window\n"
            "Exec=app --private\n",
            encoding="utf-8",
        )
        patcher = mock.patch.object(da, "DESKTOP_DIRS", [str(self.dir)])
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.tmp.cleanup)

    def test_resolve_applications_scheme(self):
        self.assertEqual(da.resolve_launcher_url("applications:org.example.App.desktop"), str(self.desktop))

    def test_resolve_without_extension(self):
        self.assertEqual(da.resolve_launcher_url("applications:org.example.App"), str(self.desktop))

    def test_resolve_file_url(self):
        self.assertEqual(da.resolve_launcher_url(self.desktop.as_uri()), str(self.desktop))

    def test_resolve_bare_name(self):
        self.assertEqual(da.resolve_launcher_url("org.example.App"), str(self.desktop))
        self.assertEqual(da.resolve_launcher_url("org.example.App.desktop"), str(self.desktop))

    def test_resolve_first_dir_wins(self):
        user_dir = self.dir / "user"
        user_dir.mkdir()
        override = user_dir / "org.example.App.desktop"
        override.write_text("[Desktop Entry]\nName=Override\n", encoding="utf-8")
        with mock.patch.object(da, "DESKTOP_DIRS", [str(user_dir), str(self.dir)]):
            self.assertEqual(da.resolve_launcher_url("applications:org.example.App.desktop"), str(override))

    def test_resolve_subdirectory_id(self):
        sub = self.dir / "kde4"
        sub.mkdir()
        (sub / "foo.desktop").write_text("[Desktop Entry]\nName=Foo\n", encoding="utf-8")
        self.assertEqual(da.resolve_launcher_url("applications:kde4-foo.desktop"), str(sub / "foo.desktop"))
        self.assertEqual(da.resolve_launcher_url("kde4-foo"), str(sub / "foo.desktop"))
        # A direct file wins over the subdirectory reading
        direct = self.dir / "kde4-foo.desktop"
        direct.write_text("[Desktop Entry]\nName=Direct\n", encoding="utf-8")
        self.assertEqual(da.resolve_launcher_url("applications:kde4-foo.desktop"), str(direct))
        self.assertIsNone(da.resolve_launcher_url("applications:kde4-bar.desktop"))

    def test_resolve_unknown(self):
        self.assertIsNone(da.resolve_launcher_url("applications:nope.desktop"))
        self.assertIsNone(da.resolve_launcher_url(""))

    def test_jump_list_actions(self):
        with mock.patch.dict(os.environ, {"LANGUAGE": "", "LC_ALL": "", "LC_MESSAGES": "", "LANG": "C"}):
            actions = da.get_jump_list_actions(str(self.desktop))
        self.assertEqual([a["actionId"] for a in actions], ["new-window", "private"])
        self.assertEqual(actions[0]["name"], "New Window")
        self.assertEqual(actions[0]["icon"], "window-new")
        self.assertEqual(actions[0]["exec"], "app --new-window")

    def test_jump_list_localized_name(self):
        with mock.patch.dict(os.environ, {"LANGUAGE": "pl", "LC_ALL": "", "LC_MESSAGES": "", "LANG": ""}):
            actions = da.get_jump_list_actions(str(self.desktop))
        self.assertEqual(actions[0]["name"], "Nowe okno")

    def test_desktop_exec(self):
        self.assertEqual(da.get_desktop_exec(str(self.desktop)), "app %U")


class HistoryTest(unittest.TestCase):
    QUERY = "SELECT url, title FROM urls ORDER BY visit DESC LIMIT ?"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.db = Path(self.tmp.name) / "History"
        da._history_cache.clear()
        self._write([
            ("https://a.example/", "A", 5),
            ("https://a.example/#section", "A again", 4),
            ("https://b.example/page", "B", 3),
            ("https://c.example/", "B", 2),
            ("https://d.example/", "D", 1),
        ])

    def _write(self, rows):
        with sqlite3.connect(self.db) as conn:
            conn.execute("DROP TABLE IF EXISTS urls")
            conn.execute("CREATE TABLE urls (url TEXT, title TEXT, visit INTEGER)")
            conn.executemany("INSERT INTO urls VALUES (?, ?, ?)", rows)
        conn.close()

    def test_dedups_by_url_fragment_and_title(self):
        docs = da.fetch_sqlite_history(self.db, self.QUERY, "test", limit=10)
        self.assertEqual([d["url"] for d in docs], ["https://a.example/", "https://b.example/page", "https://d.example/"])

    def test_limit(self):
        docs = da.fetch_sqlite_history(self.db, self.QUERY, "test", limit=2)
        self.assertEqual(len(docs), 2)

    def test_unchanged_db_is_not_copied_again(self):
        da.fetch_sqlite_history(self.db, self.QUERY, "test", limit=10)
        with mock.patch.object(da, "snapshot_sqlite") as snapshot:
            docs = da.fetch_sqlite_history(self.db, self.QUERY, "test", limit=10)
        snapshot.assert_not_called()
        self.assertEqual(len(docs), 3)

    def test_changed_db_is_read_again(self):
        da.fetch_sqlite_history(self.db, self.QUERY, "test", limit=10)
        self._write([("https://new.example/", "New", 9)])
        os.utime(self.db, ns=(1, 1))  # make sure the signature changes even within one mtime tick
        docs = da.fetch_sqlite_history(self.db, self.QUERY, "test", limit=10)
        self.assertEqual([d["url"] for d in docs], ["https://new.example/"])

    def test_cached_rows_are_copies(self):
        first = da.fetch_sqlite_history(self.db, self.QUERY, "test", limit=10)
        first[0]["icon"] = "changed"
        second = da.fetch_sqlite_history(self.db, self.QUERY, "test", limit=10)
        self.assertEqual(second[0]["icon"], "internet-services")

    def test_snapshot_private_and_cleaned_up(self):
        os.chmod(self.db, 0o644)
        with da.sqlite_snapshot(self.db, "taskline-test-") as temp:
            self.assertTrue(temp.exists())
            # The dir holding the copy (and its -wal/-shm) is private to this user
            self.assertEqual(os.stat(temp.parent).st_mode & 0o777, 0o700)
            temp_dir = temp.parent
        self.assertFalse(temp_dir.exists())

    def test_snapshot_cleaned_up_on_error(self):
        with self.assertRaises(RuntimeError):
            with da.sqlite_snapshot(self.db, "taskline-test-") as temp:
                temp_dir = temp.parent
                raise RuntimeError
        self.assertFalse(temp_dir.exists())


class FaviconNegativeCacheTest(unittest.TestCase):
    def test_expiry(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "x.failed"
            self.assertFalse(da._fresh_negative_cache(marker, 1000.0))
            marker.write_text("")
            now = marker.stat().st_mtime
            self.assertTrue(da._fresh_negative_cache(marker, now + 60))
            self.assertFalse(da._fresh_negative_cache(marker, now + da.FAVICON_RETRY_SECONDS + 1))


class FirefoxProfilesTest(unittest.TestCase):
    def test_newest_places(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, mtime in (("old.default", 1000), ("new%20profile", 2000)):
                (root / name).mkdir()
                (root / name / "places.sqlite").write_bytes(b"")
                os.utime(root / name / "places.sqlite", (mtime, mtime))
            (root / "profiles.ini").write_text(
                "[Install4F96D1932A9F858E]\nDefault=old.default\n\n"
                "[Profile0]\nName=old\nIsRelative=1\nPath=old.default\n\n"
                "[Profile1]\nName=new %(x)s\nIsRelative=1\nPath=new%20profile\n\n"
                "[Profile2]\nName=gone\nIsRelative=1\nPath=deleted.profile\n",
                encoding="utf-8")
            with mock.patch.object(da, "FIREFOX_PROFILE_ROOTS", [root, root / "missing"]):
                self.assertEqual(da._newest_firefox_places(), root / "new%20profile" / "places.sqlite")

    def test_no_profiles(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "profiles.ini").write_text("garbage without section\n", encoding="utf-8")
            with mock.patch.object(da, "FIREFOX_PROFILE_ROOTS", [Path(tmp)]):
                self.assertIsNone(da._newest_firefox_places())


class PanelVisibilityTest(unittest.TestCase):
    def test_reads_group(self):
        with tempfile.NamedTemporaryFile("w", suffix="rc", delete=False) as f:
            f.write("[PlasmaViews][Panel 275]\npanelVisibility=0\n\n"
                    "[PlasmaViews][Panel 416]\nfloating=1\npanelVisibility=1\n\n"
                    "[PlasmaViews][Panel 416][Defaults]\npanelVisibility=3\n")
        self.addCleanup(os.unlink, f.name)
        self.assertEqual(da.panel_visibility(416, f.name), 1)
        self.assertEqual(da.panel_visibility(275, f.name), 0)
        self.assertEqual(da.panel_visibility(999, f.name), -1)

    def test_missing_file(self):
        self.assertEqual(da.panel_visibility(1, "/nonexistent/plasmashellrc"), -1)


class KillAppGuardTest(unittest.TestCase):
    def test_refuses_init_and_invalid(self):
        self.assertIsNotNone(da.kill_app_error(1))
        self.assertIsNotNone(da.kill_app_error(0))
        self.assertIsNotNone(da.kill_app_error("abc"))

    def test_refuses_protected(self):
        self.assertIsNotNone(da.kill_app_error(os.getpid(), protected_pids=(os.getpid(),)))

    def test_own_process_allowed(self):
        self.assertIsNone(da.kill_app_error(os.getpid()))

    def test_other_user_refused(self):
        self.assertEqual(da.kill_app_error(os.getpid(), own_uid=os.getuid() + 1), "process belongs to another user")

    def test_missing_process(self):
        self.assertEqual(da.kill_app_error(2**22 + 12345), "no such process")


class AutostartTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.apps = root / "applications"
        (self.apps / "kde4").mkdir(parents=True)
        self.desktop = self.apps / "org.example.App.desktop"
        self.desktop.write_text("[Desktop Entry]\nName=App\nExec=app\n", encoding="utf-8")
        self.autostart = root / "autostart"
        self.system = root / "xdg-autostart"
        self.system.mkdir()
        self.kw = dict(autostart_dir=self.autostart, system_dirs=[str(self.system)], app_dirs=[str(self.apps)])

    def entry(self):
        return (self.autostart / "org.example.App.desktop").read_text(encoding="utf-8")

    def test_enable_disable_own_entry(self):
        self.assertFalse(da.is_autostart(str(self.desktop), **self.kw))
        self.assertTrue(da.set_autostart(str(self.desktop), True, **self.kw))
        self.assertIn(da.AUTOSTART_MARKER, self.entry())
        self.assertFalse(da.set_autostart(str(self.desktop), False, **self.kw))
        self.assertFalse((self.autostart / "org.example.App.desktop").exists())

    def test_hand_made_entry_is_hidden_not_deleted(self):
        self.autostart.mkdir()
        (self.autostart / "org.example.App.desktop").write_text(
            "[Desktop Entry]\nName=App\nExec=app --custom\n", encoding="utf-8")
        self.assertTrue(da.is_autostart(str(self.desktop), **self.kw))
        self.assertFalse(da.set_autostart(str(self.desktop), False, **self.kw))
        self.assertIn("Hidden=true", self.entry())
        self.assertIn("--custom", self.entry())
        self.assertTrue(da.set_autostart(str(self.desktop), True, **self.kw))
        self.assertNotIn("Hidden", self.entry())
        self.assertIn("--custom", self.entry())

    def test_system_entry_disabled_with_override(self):
        (self.system / "org.example.App.desktop").write_text("[Desktop Entry]\nName=App\nExec=app\n", encoding="utf-8")
        self.assertTrue(da.is_autostart(str(self.desktop), **self.kw))
        self.assertFalse(da.set_autostart(str(self.desktop), False, **self.kw))
        self.assertIn("Hidden=true", self.entry())
        self.assertTrue(da.set_autostart(str(self.desktop), True, **self.kw))

    def test_gnome_disabled_flag(self):
        self.autostart.mkdir()
        (self.autostart / "org.example.App.desktop").write_text(
            "[Desktop Entry]\nName=App\nExec=app\nX-GNOME-Autostart-enabled=false\n", encoding="utf-8")
        self.assertFalse(da.is_autostart(str(self.desktop), **self.kw))

    def test_only_desktop_files(self):
        script = Path(self.tmp.name) / "script.sh"
        script.write_text("#!/bin/sh\n", encoding="utf-8")
        self.assertFalse(da.set_autostart(str(script), True, **self.kw))
        self.assertFalse(self.autostart.exists())
        self.assertFalse(da.set_autostart(None, True, **self.kw))

    def test_unreadable_user_entry_is_left_alone(self):
        self.autostart.mkdir()
        bad = self.autostart / "org.example.App.desktop"
        bad.write_bytes(b"\xff\xfe not utf-8")
        da.set_autostart(str(self.desktop), True, **self.kw)
        self.assertEqual(bad.read_bytes(), b"\xff\xfe not utf-8")

    def test_symlink_target_never_written(self):
        self.autostart.mkdir()
        target = Path(self.tmp.name) / "launcher.desktop"
        target.write_text("[Desktop Entry]\nName=App\nExec=app\n", encoding="utf-8")
        (self.autostart / "org.example.App.desktop").symlink_to(target)
        self.assertFalse(da.set_autostart(str(self.desktop), False, **self.kw))
        self.assertNotIn("Hidden", target.read_text(encoding="utf-8"))
        self.assertFalse((self.autostart / "org.example.App.desktop").is_symlink())

    def test_comments_and_duplicate_keys_kept(self):
        self.autostart.mkdir()
        text = "# my note\n[Desktop Entry]\nName=App\nKeywords=a\nKeywords=b\nExec=app --x\n"
        (self.autostart / "org.example.App.desktop").write_text(text, encoding="utf-8")
        self.assertTrue(da.is_autostart(str(self.desktop), **self.kw))
        da.set_autostart(str(self.desktop), False, **self.kw)
        da.set_autostart(str(self.desktop), True, **self.kw)
        self.assertEqual(self.entry(), text)

    def test_system_entry_appearing_after_own_entry(self):
        da.set_autostart(str(self.desktop), True, **self.kw)
        (self.system / "org.example.App.desktop").write_text("[Desktop Entry]\nName=App\nExec=app\n", encoding="utf-8")
        self.assertFalse(da.set_autostart(str(self.desktop), False, **self.kw))
        self.assertIn("Hidden=true", self.entry())

    def test_state_unmanageable(self):
        self.assertEqual(da.autostart_state(None, **self.kw), -1)
        self.assertEqual(da.autostart_state(str(self.desktop) + ".nope", **self.kw), -1)
        self.assertEqual(da.autostart_state(str(self.desktop), **self.kw), 0)

    def test_xdg_dirs(self):
        with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": "/cfg", "XDG_CONFIG_DIRS": "/a:/b"}):
            self.assertEqual(da.user_autostart_dir(), Path("/cfg/autostart"))
            self.assertEqual(da.system_autostart_dirs(), ["/a/autostart", "/b/autostart"])
        with mock.patch.dict(os.environ, {"XDG_DATA_HOME": "/home/x/data", "XDG_DATA_DIRS": "/usr/share"}):
            dirs = da._xdg_application_dirs()
            self.assertEqual(dirs[0], "/home/x/data/applications")
            self.assertIn("/var/lib/snapd/desktop/applications", dirs)

    def test_non_utf8_source_fails_cleanly(self):
        self.desktop.write_bytes(b"[Desktop Entry]\nName=App\xff\nExec=app\n")
        self.assertFalse(da.set_autostart(str(self.desktop), True, **self.kw))

    def test_only_show_in_and_not_show_in(self):
        self.autostart.mkdir()
        entry = self.autostart / "org.example.App.desktop"
        cases = [
            ("OnlyShowIn=GNOME;\n", "KDE", False),
            ("OnlyShowIn=GNOME;KDE;\n", "KDE", True),
            ("OnlyShowIn=GNOME;\n", "ubuntu:GNOME", True),
            ("NotShowIn=KDE;\n", "KDE", False),
            ("NotShowIn=GNOME;\n", "KDE", True),
            ("OnlyShowIn=GNOME;\n", "", True),  # unknown desktop: don't guess
        ]
        for line, desktop, expected in cases:
            entry.write_text("[Desktop Entry]\nName=App\nExec=app\n" + line, encoding="utf-8")
            with mock.patch.dict(os.environ, {"XDG_CURRENT_DESKTOP": desktop}):
                self.assertEqual(da.is_autostart(str(self.desktop), **self.kw), expected, (line, desktop))

    def test_desktop_file_id_from_subdirectory(self):
        sub = self.apps / "kde4" / "foo.desktop"
        self.assertEqual(da.desktop_file_id(str(sub), [str(self.apps)]), "kde4-foo.desktop")


class WebAppTracksTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        apps = Path(self.tmp.name)
        (apps / "WebApp-Spotify.desktop").write_text(
            '[Desktop Entry]\nName=Spotify\nExec=vivaldi-stable --app="https://open.spotify.com" --class=WebApp-Spotify\n',
            encoding="utf-8")
        (apps / "browser.desktop").write_text("[Desktop Entry]\nName=Browser\nExec=vivaldi-stable %U\n", encoding="utf-8")
        patcher = mock.patch.object(da, "DESKTOP_DIRS", [str(apps)])
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_web_app_host(self):
        self.assertEqual(da.web_app_host(da.resolve_launcher_url("applications:WebApp-Spotify.desktop")), "open.spotify.com")
        self.assertEqual(da.web_app_host(da.resolve_launcher_url("applications:browser.desktop")), "")

    def test_matches_player_by_host(self):
        players = [{"host": "music.youtube.com", "track": "Other", "pid": 1},
                   {"host": "open.spotify.com", "track": "Gives & Takes", "pid": 42}]
        result = da.web_app_tracks(["applications:WebApp-Spotify.desktop", "applications:browser.desktop"], players)
        self.assertEqual(result, {"applications:WebApp-Spotify.desktop": {"track": "Gives & Takes", "pid": 42}})

    def test_web_app_host_reread_after_change(self):
        path = da.resolve_launcher_url("applications:WebApp-Spotify.desktop")
        self.assertEqual(da.web_app_host(path), "open.spotify.com")
        Path(path).write_text("[Desktop Entry]\nName=Spotify\nExec=vivaldi-stable --app https://music.example.org/x\n",
                              encoding="utf-8")
        st = os.stat(path)
        os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns + 1_000_000_000))
        self.assertEqual(da.web_app_host(path), "music.example.org")
        self.assertEqual(da.web_app_host(None), "")
        self.assertEqual(da.web_app_host(str(Path(path).with_name("missing.desktop"))), "")

    def test_url_host(self):
        self.assertEqual(da.url_host("https://www.Example.com/x"), "example.com")
        self.assertEqual(da.url_host(""), "")


class BrowserDetectionTest(unittest.TestCase):
    def test_firefox(self):
        self.assertTrue(da.is_firefox_desktop("/usr/share/applications/firefox.desktop"))
        self.assertTrue(da.is_firefox_desktop("/home/u/.local/share/applications/FFPWA-01ABC.desktop"))
        self.assertFalse(da.is_firefox_desktop("/usr/share/applications/chromium.desktop"))
        self.assertTrue(da.is_firefox_desktop("/usr/share/applications/org.mozilla.firefox.desktop"))
        self.assertTrue(da.is_firefox_desktop("/usr/share/applications/firefox-esr.desktop"))
        self.assertFalse(da.is_firefox_desktop("/usr/share/applications/firefoxish-tool.desktop"))

    def test_chromium_family(self):
        cases = {
            "google-chrome.desktop": "chrome",
            "com.google.Chrome.desktop": "chrome",
            "brave-browser.desktop": "brave",
            "vivaldi-stable.desktop": "vivaldi",
            "org.chromium.Chromium.desktop": "chromium",
            "microsoft-edge.desktop": "edge",
            "opera.desktop": "opera",
            "com.opera.Opera.desktop": "opera",
            "com.microsoft.Edge.desktop": "edge",
            "microsoft-edge-beta.desktop": "edge",
            "chromium-browser.desktop": "chromium",
            "com.brave.Browser.desktop": "brave",
            "org.kde.dolphin.desktop": None,
            # Substrings of other words are not browsers
            "hedgewars.desktop": None,
            "org.kde.knowledge.desktop": None,
            "cooperate.desktop": None,
            "chromeless.desktop": None,
        }
        for name, browser in cases.items():
            self.assertEqual(da.chromium_browser_for(f"/usr/share/applications/{name}"), browser, name)

    def test_match_order(self):
        # Same precedence as the original if/elif chain: chrome, brave, vivaldi, chromium, edge, opera
        self.assertEqual(list(da.CHROMIUM_PROFILE_ROOTS), ["chrome", "brave", "vivaldi", "chromium", "edge", "opera"])
        self.assertEqual(da.chromium_browser_for("/x/brave-chromium.desktop"), "brave")


class ForceQuitTest(unittest.TestCase):
    """Signals are mocked: no real process is ever signalled."""

    def setUp(self):
        self.scheduled = []
        patches = [
            mock.patch.object(da, "kill_app_error", return_value=None),
            mock.patch.object(da.os, "pidfd_open", create=True, return_value=99),
            mock.patch.object(da.signal, "pidfd_send_signal", create=True),
            mock.patch.object(da.os, "close"),
            mock.patch.object(da.os, "kill"),
        ]
        self.error, self.pidfd_open, self.send, self.close, self.kill = [p.start() for p in patches]
        for p in patches:
            self.addCleanup(p.stop)

    def schedule(self, delay, fn):
        self.scheduled.append(fn)

    def test_pidfd_used_for_both_signals(self):
        self.assertEqual(da.force_quit(1234, schedule=self.schedule), "OK")
        self.pidfd_open.assert_called_once_with(1234)
        self.send.assert_called_once_with(99, da.signal.SIGTERM)
        self.scheduled[0]()
        self.send.assert_called_with(99, da.signal.SIGKILL)
        self.close.assert_called_once_with(99)
        self.kill.assert_not_called()

    def test_exited_process_is_fine(self):
        da.force_quit(1234, schedule=self.schedule)
        self.send.side_effect = ProcessLookupError
        self.assertFalse(self.scheduled[0]())
        self.close.assert_called_once_with(99)

    def test_refused_pid_never_signalled(self):
        self.error.return_value = "refusing to kill this process"
        self.assertTrue(da.force_quit(1234, schedule=self.schedule).startswith("ERROR"))
        self.pidfd_open.assert_not_called()
        self.send.assert_not_called()
        self.kill.assert_not_called()

    def test_fallback_without_pidfd(self):
        self.pidfd_open.side_effect = OSError(38, "ENOSYS")
        self.assertEqual(da.force_quit(1234, schedule=self.schedule), "OK")
        self.kill.assert_called_once_with(1234, da.signal.SIGTERM)
        self.scheduled[0]()
        self.kill.assert_called_with(1234, da.signal.SIGKILL)
        self.send.assert_not_called()


class ParentPidsTest(unittest.TestCase):
    def test_own_process(self):
        result = da.parent_pids(f"{os.getpid()}, abc, 999999999")
        self.assertEqual(result, {str(os.getpid()): os.getppid()})


if __name__ == "__main__":
    unittest.main()
