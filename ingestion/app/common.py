from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def json_serializer(value: Any) -> bytes:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def json_deserializer(value: bytes) -> Any:
    return json.loads(value.decode("utf-8"))


def blank_to_none(value: str | None) -> str | None:
    if value is None:
        return None
    stripped = value.strip()
    return stripped if stripped else None


def as_int(value: str | None) -> int | None:
    value = blank_to_none(value)
    return int(value) if value is not None else None


def as_bool(value: str | None) -> bool | None:
    value = blank_to_none(value)
    if value is None:
        return None
    normalized = value.lower()
    if normalized not in {"true", "false"}:
        raise ValueError(f"expected true or false, got {value!r}")
    return normalized == "true"
