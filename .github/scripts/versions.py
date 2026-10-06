"""Validate or update the versions manifest and matching Dockerfile in lockstep."""
import copy
import json
import os
from pathlib import Path
import re
import sys


def validate(values):
    modules = values["modules"]
    for value in (values["nginx"], modules["fancyindex"]):
        if not isinstance(value, str) or not re.fullmatch(r"\d+\.\d+\.\d+", value):
            raise ValueError(f"Invalid release version: {value!r}")
    for value in (values["alpine"], modules["headers-more"]):
        if not isinstance(value, str) or not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", value):
            raise ValueError(f"Invalid version: {value!r}")
    if not re.fullmatch(r"[a-f0-9]{40}", modules["substitutions"]):
        raise ValueError("Invalid substitutions commit")
    expected = re.escape(values["nginx"])
    if not re.fullmatch(rf"nginx-module-otel-{expected}\.\d+\.\d+\.\d+-r\d+\.apk", modules["otel-apk"]):
        raise ValueError("OpenTelemetry APK does not match nginx")


def render(values, dockerfile):
    validate(values)
    modules = values["modules"]
    channel = "mainline/" if int(values["nginx"].split(".")[1]) % 2 else ""
    alpine_mm = ".".join(values["alpine"].split(".")[:2])
    replacements = {
        r"^FROM alpine:.*$": f"FROM alpine:{values['alpine']}",
        r"^ENV NGINX_VERSION=.*$": f"ENV NGINX_VERSION={values['nginx']}",
        r"^ENV MORE_SET_HEADER_VERSION=.*$": f"ENV MORE_SET_HEADER_VERSION={modules['headers-more']}",
        r"^ENV FANCYINDEX=.*$": f"ENV FANCYINDEX={modules['fancyindex']}",
        r"^ENV SUBSTITUTIONS_COMMIT=.*$": f"ENV SUBSTITUTIONS_COMMIT={modules['substitutions']}",
        r"^ENV OTEL_APK=.*$": f"ENV OTEL_APK={modules['otel-apk']}",
        r"^ENV MODULE_URL_BASE=.*$": f"ENV MODULE_URL_BASE=https://nginx.org/packages/{channel}alpine/v{alpine_mm}/main/x86_64/",
    }
    for pattern, replacement in replacements.items():
        dockerfile, count = re.subn(pattern, replacement, dockerfile, flags=re.MULTILINE)
        if count != 1:
            raise ValueError(f"Expected exactly one Dockerfile setting for {pattern}")
    return dockerfile


def proposed(current, environ):
    updated = copy.deepcopy(current)
    for key, variable in (("nginx", "NGINX"), ("alpine", "ALPINE")):
        updated[key] = environ[variable]
    for key, variable in (("headers-more", "HEADERS_MORE"), ("fancyindex", "FANCYINDEX"),
                          ("substitutions", "SUBSTITUTIONS"), ("otel-apk", "OTEL")):
        updated["modules"][key] = environ[variable]
    validate(updated)
    pairs = [(current["nginx"], updated["nginx"]), (current["alpine"], updated["alpine"])]
    pairs += [(current["modules"][key], updated["modules"][key]) for key in ("headers-more", "fancyindex")]
    for old, new in pairs:
        numbers = lambda value: tuple(int(n) for n in value.split(".")) + (0,) * (3 - len(value.split(".")))
        if numbers(new) < numbers(old):
            raise ValueError(f"Refusing dependency downgrade: {old} -> {new}")
    return updated


def main():
    manifest_path = Path("versions.json")
    dockerfile_path = Path("Dockerfile.alpine")
    current = json.loads(manifest_path.read_text())
    dockerfile = dockerfile_path.read_text()
    if sys.argv[1:] == ["--check"]:
        if render(current, dockerfile) != dockerfile:
            raise ValueError("Dockerfile settings differ from versions.json")
        print("All dependency versions match the Dockerfile")
        return
    updated = proposed(current, os.environ)
    rendered = render(updated, dockerfile)
    changed = updated != current
    # Validate all substitutions before writing either file.
    if changed:
        manifest_path.write_text(json.dumps(updated, indent=2) + "\n")
        dockerfile_path.write_text(rendered)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"changed={int(changed)}\n")
    print(f"Dependency versions {'updated' if changed else 'unchanged; daily OS refresh still runs'}")


if __name__ == "__main__":
    main()
