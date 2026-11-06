# SPDX-License-Identifier: GPL-2.0-or-later
"""Unit tests for the pure helpers in package/contents/ui/code/desktop_actions.py.

Run with: python3 -m unittest discover -s tests
"""

import importlib.util
import os
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parent.parent / "package/contents/ui/code/desktop_actions.py"
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

    def test_snapshot_cleanup(self):
        temp = Path(self.tmp.name) / "snap"
        da.snapshot_sqlite(self.db, temp)
        self.assertTrue(temp.exists())
        da.remove_sqlite_snapshot(temp)
        self.assertFalse(temp.exists())


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

    def test_url_host(self):
        self.assertEqual(da.url_host("https://www.Example.com/x"), "example.com")
        self.assertEqual(da.url_host(""), "")


class ParentPidsTest(unittest.TestCase):
    def test_own_process(self):
        result = da.parent_pids(f"{os.getpid()}, abc, 999999999")
        self.assertEqual(result, {str(os.getpid()): os.getppid()})


if __name__ == "__main__":
    unittest.main()
