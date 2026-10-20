from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PARAMETERS = Path(__file__).with_name("parameters.json")
DEFAULT_OUT = ROOT / "build/qa/formal-fire-20261018"


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write(path, data):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load(parameters=DEFAULT_PARAMETERS):
    params = read(parameters)
    return params, read(ROOT / params["baseline_source"]), read(ROOT / params["artifact_source"]), read(ROOT / params["generic_source"])


def hashes(paths):
    return {str(path).replace("\\", "/"): hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in paths}
