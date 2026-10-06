import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from check_vulnerabilities import findings, main


class VulnerabilityTests(unittest.TestCase):
    def report(self, items):
        return {"SchemaVersion": 2, "Metadata": {"OS": {"Family": "alpine"}},
                "Results": [{"Vulnerabilities": items}]}

    def test_block_fixable_high_and_critical(self):
        items = [{"Severity": severity, "FixedVersion": "2.0"} for severity in ("HIGH", "CRITICAL")]
        self.assertEqual(findings(self.report(items)), (items, items))

    def test_retain_unfixed_and_lower_severity_without_blocking(self):
        items = [{"Severity": "HIGH"}, {"Severity": "CRITICAL", "FixedVersion": ""},
                 {"Severity": "MEDIUM", "FixedVersion": "2.0"}]
        self.assertEqual(findings(self.report(items)), (items, []))

    def test_no_findings_is_valid(self):
        self.assertEqual(findings(self.report(None)), ([], []))

    def test_empty_or_missing_scan_is_invalid(self):
        for report in ({}, {"SchemaVersion": 1, "Results": []}, {"SchemaVersion": 2, "Results": []}):
            with self.subTest(report=report), self.assertRaises(ValueError):
                findings(report)

    def test_unsupported_os_is_invalid(self):
        for os in ({"Family": "alpine", "EOSL": True}, {"Family": "unknown"}):
            report = self.report([])
            report["Metadata"]["OS"] = os
            with self.assertRaises(ValueError):
                findings(report)

    def test_cli_writes_summary_and_blocks_available_fix(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.json"
            summary = Path(directory) / "summary.md"
            item = {"Severity": "HIGH", "FixedVersion": "2.0", "InstalledVersion": "1.0",
                    "VulnerabilityID": "CVE-TEST", "PkgName": "fixture"}
            report.write_text(json.dumps(self.report([item])))
            with patch('sys.argv', ['scan', str(report)]), patch.dict('os.environ', GITHUB_STEP_SUMMARY=str(summary)), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as result:
                    main()
            self.assertEqual(result.exception.code, 1)
            self.assertIn('fixable HIGH/CRITICAL: 1', summary.read_text())

    def test_cli_accepts_scan_without_findings(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.json"
            report.write_text(json.dumps(self.report([])))
            with patch('sys.argv', ['scan', str(report)]), patch.dict('os.environ', GITHUB_STEP_SUMMARY=''), contextlib.redirect_stdout(io.StringIO()):
                main()


if __name__ == "__main__":
    unittest.main()
