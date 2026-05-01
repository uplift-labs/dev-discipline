#!/usr/bin/env python3
"""Enable a boolean feature in a small TOML config file.

This intentionally preserves the rest of the file as text. It only ensures a
single `[features]` entry exists with `<feature> = true`.
"""
import re
import sys
from pathlib import Path


def enable_feature(text: str, feature: str) -> str:
    lines = text.splitlines()
    section_re = re.compile(r"^\s*\[(.+)]\s*$")
    feature_re = re.compile(rf"^(\s*{re.escape(feature)}\s*=\s*).*$")

    features_start = None
    features_end = len(lines)

    for i, line in enumerate(lines):
        match = section_re.match(line)
        if not match:
            continue
        if match.group(1).strip() == "features":
            features_start = i
            features_end = len(lines)
            for j in range(i + 1, len(lines)):
                if section_re.match(lines[j]):
                    features_end = j
                    break
            break

    if features_start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend(["[features]", f"{feature} = true"])
        return "\n".join(lines) + "\n"

    for i in range(features_start + 1, features_end):
        if feature_re.match(lines[i]):
            lines[i] = feature_re.sub(r"\1true", lines[i])
            return "\n".join(lines) + "\n"

    lines.insert(features_start + 1, f"{feature} = true")
    return "\n".join(lines) + "\n"


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <config.toml> <feature>", file=sys.stderr)
        return 1

    path = Path(sys.argv[1])
    feature = sys.argv[2]
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    result = enable_feature(text, feature)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(result, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
