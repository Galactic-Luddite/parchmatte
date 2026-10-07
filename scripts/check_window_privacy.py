#!/usr/bin/env python3
"""Reject CoreGraphics window metadata keys absent from the privacy policy."""

import re
import sys
from pathlib import Path


DOCUMENTED_METADATA_KEYS = {
    "kCGWindowBounds",
    "kCGWindowIsOnscreen",
    "kCGWindowLayer",
    "kCGWindowNumber",
    "kCGWindowOwnerName",
    "kCGWindowOwnerPID",
}

PUBLIC_QUERY_OPTIONS = {
    "kCGWindowListOptionAll",
    "kCGWindowListOptionExcludeDesktopElements",
    "kCGWindowListOptionIncludingWindow",
    "kCGWindowListOptionOnScreenAboveWindow",
    "kCGWindowListOptionOnScreenBelowWindow",
    "kCGWindowListOptionOnScreenOnly",
}

TOKEN = re.compile(r"\bkCGWindow[A-Za-z]+\b")
SOURCE_SUFFIXES = {".c", ".h", ".m", ".mm", ".swift"}


def source_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_file():
            files.append(path)
        elif path.is_dir():
            files.extend(
                candidate
                for candidate in path.rglob("*")
                if candidate.is_file() and candidate.suffix in SOURCE_SUFFIXES
            )
    return sorted(set(files))


def main() -> int:
    paths = [Path(argument) for argument in sys.argv[1:]] or [Path("Sources")]
    files = source_files(paths)
    if not files:
        print("error: no source files scanned", file=sys.stderr)
        return 2

    tokens = set()
    for path in files:
        tokens.update(TOKEN.findall(path.read_text(encoding="utf-8")))

    unexpected = sorted(tokens - DOCUMENTED_METADATA_KEYS - PUBLIC_QUERY_OPTIONS)
    if unexpected:
        print("undocumented window metadata key(s): " + ", ".join(unexpected))
        return 1

    print(
        f"window privacy check passed: {len(files)} source files, "
        f"{len(tokens & DOCUMENTED_METADATA_KEYS)} documented metadata keys"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
