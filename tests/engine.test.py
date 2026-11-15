#!/usr/bin/env python3
"""Unit tests for the parts of bin/omafolder-state that do not need the network.

Run with: python3 tests/engine.test.py
"""

from __future__ import annotations

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENGINE = ROOT / "bin" / "omafolder-state"


def load_engine(home: Path):
    """Import the engine with HOME pointed at a throwaway directory."""
    os.environ["HOME"] = str(home)
    os.environ["OMAFOLDER_OFFLINE"] = "1"
    os.environ.pop("OMAFOLDER_STATE", None)
    os.environ.pop("OMAFOLDER_SHELL", None)
    loader = importlib.machinery.SourceFileLoader("omafolder_state", str(ENGINE))
    spec = importlib.util.spec_from_loader("omafolder_state", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class MarketplaceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.engine = load_engine(self.home)

    def tearDown(self):
        self.tmp.cleanup()

    def test_market_entry_resolves_a_listed_plugin(self):
        registry = {
            "sources": [
                {"repo": "https://github.com/acme/other", "plugins": {"acme.other": {}}},
                {
                    "repo": "https://github.com/acme/titlebars",
                    "listingValidatedBranch": "main",
                    "listingValidatedCommit": "abc123",
                    "plugins": {"acme.titlebars": {}},
                },
            ]
        }
        entry = self.engine.market_entry(registry, "acme.titlebars")
        self.assertEqual(entry["repo"], "https://github.com/acme/titlebars")
        self.assertEqual(entry["branch"], "main")
        self.assertEqual(entry["commit"], "abc123")

    def test_market_entry_ignores_unknown_and_malformed_input(self):
        self.assertIsNone(self.engine.market_entry({"sources": []}, "acme.titlebars"))
        self.assertIsNone(self.engine.market_entry(None, "acme.titlebars"))
        self.assertIsNone(self.engine.market_entry({"sources": [None, "x"]}, "acme.titlebars"))

    def test_has_panel_reads_the_widget_entry_point(self):
        entry = self.home / "widget.qml"
        entry.write_text("BarWidget {\n  function open() {}\n}\n", encoding="utf-8")
        plain = self.home / "plain.qml"
        plain.write_text("BarWidget {\n  text: 'x'\n}\n", encoding="utf-8")

        self.assertTrue(self.engine.has_panel({"kinds": ["bar-widget"], "barWidgetPath": str(entry)}))
        self.assertFalse(self.engine.has_panel({"kinds": ["bar-widget"], "barWidgetPath": str(plain)}))
        # Loader-owned kinds always have a panel.
        self.assertTrue(self.engine.has_panel({"kinds": ["bar-widget", "menu"], "barWidgetPath": str(plain)}))
        # A plugin we cannot inspect stays enabled rather than hiding the action.
        self.assertTrue(self.engine.has_panel({"kinds": ["bar-widget"], "barWidgetPath": ""}))
        self.assertTrue(self.engine.has_panel({"kinds": ["bar-widget"], "barWidgetPath": str(self.home / "gone.qml")}))


class UpdateCheckTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.engine = load_engine(self.home)

    def tearDown(self):
        self.tmp.cleanup()

    def install(self, plugin_id, version, git=False):
        directory = self.home / ".config" / "omarchy" / "plugins" / plugin_id
        directory.mkdir(parents=True)
        (directory / "manifest.json").write_text(
            json.dumps({"id": plugin_id, "name": "Title Bars", "version": version}),
            encoding="utf-8",
        )
        if git:
            for command in (
                ["git", "init", "-q"],
                ["git", "add", "manifest.json"],
                ["git", "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-qm", "init"],
            ):
                subprocess.run(command, cwd=directory, check=True)
        return directory

    def run_command(self, command, *args):
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            status = command(list(args))
        return status, json.loads(buffer.getvalue().strip())

    def test_a_bundled_plugin_reports_no_upstream(self):
        status, payload = self.run_command(self.engine.command_update_check, "omarchy.audio")
        self.assertEqual(status, 0)
        self.assertEqual(payload["source"], "bundled")
        self.assertFalse(payload["updateAvailable"])

    def test_a_manual_install_has_nothing_to_pull(self):
        self.install("acme.titlebars", "1.0.0")
        status, payload = self.run_command(self.engine.command_update_check, "acme.titlebars")
        self.assertEqual(status, 0)
        self.assertEqual(payload["source"], "manual")
        self.assertEqual(payload["installed"], "1.0.0")
        self.assertFalse(payload["updateAvailable"])

    def test_a_git_checkout_offline_still_reports_the_installed_version(self):
        self.install("acme.titlebars", "1.4.2", git=True)
        status, payload = self.run_command(self.engine.command_update_check, "acme.titlebars")
        self.assertEqual(status, 0)
        self.assertEqual(payload["installed"], "1.4.2")
        self.assertEqual(payload["name"], "Title Bars")
        self.assertFalse(payload["updateAvailable"])
        self.assertIn("Offline", payload["note"])

    def test_updating_something_that_is_not_a_checkout_fails_cleanly(self):
        self.install("acme.titlebars", "1.0.0")
        status, payload = self.run_command(self.engine.command_update, "acme.titlebars")
        self.assertEqual(status, 1)
        self.assertFalse(payload["ok"])
        self.assertIn("not a git checkout", payload["error"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
