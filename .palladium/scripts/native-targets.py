#!/usr/bin/env python3
import json
from pathlib import Path
import shlex
import sys

manifest = Path(__file__).resolve().parents[1] / "source-files.sha256"
names = {Path(line.split(None, 1)[1]).name for line in manifest.read_text().splitlines() if line.endswith(".cpp")}
targets = set()
for entry in json.loads(Path(sys.argv[1]).read_text()):
    source = Path(entry["file"])
    matches = source.name in names
    if not matches and "UnifiedSource" in source.name and source.exists():
        includes = source.read_text()
        matches = any(name in includes for name in names)
    if matches:
        arguments = entry.get("arguments") or shlex.split(entry["command"])
        targets.add(arguments[arguments.index("-o") + 1])
for target in sorted(targets):
    print(target)
