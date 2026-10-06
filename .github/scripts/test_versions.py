import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from versions import proposed, render, validate


class VersionsTests(unittest.TestCase):
    def setUp(self):
        self.values = json.loads(Path("versions.json").read_text())
        self.dockerfile = Path("Dockerfile.alpine").read_text()
        m = self.values["modules"]
        self.environ = dict(NGINX=self.values["nginx"], ALPINE=self.values["alpine"],
                            HEADERS_MORE=m["headers-more"], FANCYINDEX=m["fancyindex"],
                            SUBSTITUTIONS=m["substitutions"], OTEL=m["otel-apk"])

    def test_unchanged_versions_round_trip(self):
        self.assertEqual(proposed(self.values, self.environ), self.values)
        self.assertEqual(render(self.values, self.dockerfile), self.dockerfile)

    def test_reject_module_downgrade(self):
        self.environ["HEADERS_MORE"] = "0.1"
        with self.assertRaisesRegex(ValueError, "downgrade"):
            proposed(self.values, self.environ)

    def test_reject_alpine_downgrade(self):
        self.environ["ALPINE"] = "3.1.0"
        with self.assertRaisesRegex(ValueError, "downgrade"):
            proposed(self.values, self.environ)

    def test_reject_mismatched_binary_module(self):
        self.environ["OTEL"] = "nginx-module-otel-1.30.5.0.1.2-r1.apk"
        with self.assertRaisesRegex(ValueError, "does not match"):
            proposed(self.values, self.environ)

    def test_reject_shell_metacharacters(self):
        for key in self.environ:
            bad = dict(self.environ, **{key: "bad; command"})
            with self.subTest(key=key), self.assertRaises(ValueError):
                proposed(self.values, bad)

    def test_reject_missing_or_duplicate_setting(self):
        for text in (self.dockerfile.replace("ENV FANCYINDEX=", "#ENV FANCYINDEX="),
                     self.dockerfile + "\nENV FANCYINDEX=0.6.0\n"):
            with self.assertRaisesRegex(ValueError, "exactly one"):
                render(self.values, text)

    def test_base_and_channel_follow_updated_versions(self):
        updated = copy.deepcopy(self.values)
        updated["alpine"] = "3.25.0"
        rendered = render(updated, self.dockerfile)
        self.assertIn("FROM alpine:3.25.0", rendered)
        self.assertIn("/mainline/alpine/v3.25/main/x86_64/", rendered)
        updated["nginx"] = "1.32.0"
        updated["modules"]["otel-apk"] = "nginx-module-otel-1.32.0.0.1.2-r1.apk"
        self.assertIn("/packages/alpine/v3.25/", render(updated, self.dockerfile))

    def test_cli_updates_both_files_and_check_detects_drift(self):
        script = Path(__file__).with_name("versions.py").resolve()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "versions.json").write_text(json.dumps(self.values))
            (root / "Dockerfile.alpine").write_text(self.dockerfile)
            env = dict(os.environ, **self.environ, GITHUB_OUTPUT=str(root / "output"))
            env["HEADERS_MORE"] = "9.99"
            result = subprocess.run([sys.executable, script], cwd=root, env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads((root / "versions.json").read_text())["modules"]["headers-more"], "9.99")
            self.assertIn("ENV MORE_SET_HEADER_VERSION=9.99", (root / "Dockerfile.alpine").read_text())
            self.assertIn("changed=1", (root / "output").read_text())
            self.assertEqual(subprocess.run([sys.executable, script, "--check"], cwd=root, capture_output=True).returncode, 0)
            (root / "Dockerfile.alpine").write_text(self.dockerfile)
            self.assertNotEqual(subprocess.run([sys.executable, script, "--check"], cwd=root, capture_output=True).returncode, 0)

    def test_cli_downgrade_leaves_both_files_untouched(self):
        script = Path(__file__).with_name("versions.py").resolve()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = json.dumps(self.values)
            (root / "versions.json").write_text(original)
            (root / "Dockerfile.alpine").write_text(self.dockerfile)
            env = dict(os.environ, **self.environ, GITHUB_OUTPUT=str(root / "output"))
            env["ALPINE"] = "1.0.0"
            result = subprocess.run([sys.executable, script], cwd=root, env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((root / "versions.json").read_text(), original)
            self.assertEqual((root / "Dockerfile.alpine").read_text(), self.dockerfile)


if __name__ == "__main__":
    unittest.main()
