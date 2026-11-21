#!/usr/bin/env python3
"""Validate the synthetic Android event-context loopback capture."""
import argparse
import gzip
import json
from email import policy
from email.parser import BytesParser
from pathlib import Path


def uploads(directory: Path, scenario: str, requests: list[str]) -> list[dict]:
    result = []
    for index, request in enumerate(requests, 1):
        if request != "/api/crash/upload":
            continue
        stem = directory / f"{scenario}-{index}"
        message = BytesParser(policy=policy.default).parsebytes(
            stem.with_suffix(".headers").read_bytes() + b"\r\n"
            + stem.with_suffix(".body").read_bytes()
        )
        parts = {}
        for part in message.iter_parts():
            body = part.get_payload(decode=True)
            if body.startswith(b"\x1f\x8b"):
                body = gzip.decompress(body)
            parts[part.get_param("name", header="content-disposition")] = body
        assert parts["type"] == b"NON_FATAL"
        result.append(parts)
    return result


def validate(directory: Path, scenario: str = "event-context") -> dict:
    receipt = json.loads((directory / f"{scenario}.json").read_text())
    assert receipt["stage"] == "complete", receipt.get("stage")
    reports = uploads(directory, scenario, receipt["requests"])
    assert len(reports) == 2, len(reports)
    first, second = (json.loads(report["uploadBean"])["properties"] for report in reports)

    assert first["endpoint"] == "/orders"
    assert first["collision"] == "filtered-value"
    assert first["dart.needs_symbolication"] == "true"
    assert first["dart.build_id"] == "abcdef0123456789"
    assert "tenant" not in first
    assert "transientRemove" not in first
    assert "event-value" not in first.values()
    assert "must-not-upload" not in first.values()

    assert second["tenant"] == "global-tenant"
    assert second["collision"] == "global-value"
    assert "endpoint" not in second
    assert "transientRemove" not in second
    assert "dart.needs_symbolication" not in second
    assert "dart.build_id" not in second
    return {"scenario": scenario, "acceptedUploads": 2,
            "beforeSendFiltering": True, "persistentScopeRestored": True,
            "diagnosticsIsolated": True}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--scenario", default="event-context")
    args = parser.parse_args()
    print(json.dumps(validate(args.directory, args.scenario), indent=2))
