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


if __name__ == "__main__":
    unittest.main()
