"""Keep full scan evidence, but block findings with an available high/critical fix."""
import json
import os
from pathlib import Path
import sys


def findings(report):
    if report.get("SchemaVersion") != 2 or not isinstance(report.get("Results"), list) or not report["Results"]:
        raise ValueError("Missing or unsupported Trivy scan results")
    operating_system = report.get("Metadata", {}).get("OS", {})
    if operating_system.get("Family") != "alpine" or operating_system.get("EOSL"):
        raise ValueError("Scan did not identify a supported Alpine image")
    all_findings = [item for result in report["Results"] for item in result.get("Vulnerabilities", []) or []]
    blocking = [item for item in all_findings if item["Severity"] in ("HIGH", "CRITICAL") and item.get("FixedVersion")]
    return all_findings, blocking


def main():
    report = json.loads(Path(sys.argv[1]).read_text())
    all_findings, blocking = findings(report)
    summary = f"Detected vulnerabilities: {len(all_findings)}; fixable HIGH/CRITICAL: {len(blocking)}"
    print(summary)
    for item in blocking:
        print(f"{item['VulnerabilityID']}: {item['PkgName']} {item['InstalledVersion']} -> {item['FixedVersion']}")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
            output.write(f"### Image vulnerability scan\n\n{summary}\n\nFull findings, including unfixed vulnerabilities, are in the vulnerability-report artifact.\n")
    if blocking:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
