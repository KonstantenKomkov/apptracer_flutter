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
        if parts.get("type") != b"NON_FATAL":
            raise ValueError(f"Unexpected report type in capture {index}")
        result.append(parts)
    return result


def validate(directory: Path, scenario: str = "event-context") -> dict:
    receipt = json.loads((directory / f"{scenario}.json").read_text())
    if (receipt.get("stage"), receipt.get("state")) != ("complete", "disabled"):
        raise ValueError("The scenario did not complete with collection disabled")
    reports = uploads(directory, scenario, receipt["requests"])
    if len(reports) != 2:
        raise ValueError(f"Expected two reports, received {len(reports)}")

    # The uploader can deliver the reports in either order.
    properties = {}
    for report in reports:
        title = report["stackTrace"].splitlines()[0]
        if title in properties:
            raise ValueError("Received two reports for the same event")
        properties[title] = json.loads(report["uploadBean"])["properties"]
    first = properties[b"DartError: StateError: Bad state: event-context-a"]
    second = properties[b"DartError: StateError: Bad state: event-context-b"]

    def check_fields(actual, expected, absent):
        for key, value in expected.items():
            if actual.get(key) != value:
                raise ValueError(f"Unexpected or missing value for {key}")
        for key in absent:
            if key in actual:
                raise ValueError(f"Unexpected property {key}")

    check_fields(first, {
        "endpoint": "/orders", "collision": "filtered-value",
        "dart.needs_symbolication": "true", "dart.build_id": "abcdef0123456789",
    }, ("tenant", "transientRemove"))
    if {"event-value", "must-not-upload"}.intersection(first.values()):
        raise ValueError("Filtered value reached the first report")
    check_fields(second, {"tenant": "global-tenant", "collision": "global-value"},
                 ("endpoint", "transientRemove", "dart.needs_symbolication", "dart.build_id"))
    return {"scenario": scenario, "acceptedUploads": 2,
            "beforeSendFiltering": True, "persistentScopeRestored": True,
            "diagnosticsIsolated": True}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--scenario", default="event-context")
    args = parser.parse_args()
    print(json.dumps(validate(args.directory, args.scenario), indent=2))
