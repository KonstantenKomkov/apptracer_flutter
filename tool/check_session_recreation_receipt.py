#!/usr/bin/env python3
"""Validate synthetic session-restart[-offline] loopback captures, without printing payloads."""
import argparse
import gzip
import json
from email import policy
from email.parser import BytesParser
from pathlib import Path


def validate(directory: Path, scenario: str) -> dict:
    receipt = json.loads((directory / f"{scenario}.json").read_text())
    assert receipt["stage"] == "complete", receipt.get("stage")
    assert receipt["cycles"] == 4 and not receipt["enabled"] and receipt["files"] == {}
    assert receipt["starts"] == ["enabled/null"] * 3
    collectors = receipt["collectors"]
    assert len({c["pid"] for c in collectors}) == 1
    assert all(c["nativeInstalled"] and c["watchdogs"] == 1 for c in collectors)
    offline = scenario.endswith("-offline")
    uploads = []
    for index, request in enumerate(receipt["requests"], 1):
        if request != "/api/crash/upload":
            continue
        stem = directory / f"{scenario}-{index}"
        message = BytesParser(policy=policy.default).parsebytes(
            stem.with_suffix(".headers").read_bytes() + b"\r\n" + stem.with_suffix(".body").read_bytes()
        )
        parts = {}
        for part in message.iter_parts():
            body = part.get_payload(decode=True)
            if body.startswith(b"\x1f\x8b"):
                body = gzip.decompress(body)
            parts[part.get_param("name", header="content-disposition")] = body
        assert parts["type"] == b"NON_FATAL"
        uploads.append(parts)
    assert len(uploads) == (8 if offline else 4)
    sessions, devices = set(), set()
    for cycle in range(4):
        report = uploads[cycle * (2 if offline else 1)]
        text = b"\n".join(report.values()).decode()
        assert f"account-{cycle // 2}" in text
        assert f"private-value-{cycle}" in text
        assert f"private-breadcrumb-{cycle}" in text
        assert f"session-{cycle}" in text
        for previous in range(cycle):
            assert f"private-value-{previous}" not in text
            assert f"private-breadcrumb-{previous}" not in text
            assert f"offline-private-{previous}" not in text
        if cycle >= 2:
            assert "account-0" not in text
        bean = json.loads(report["uploadBean"])
        sessions.add(bean["sessionUuid"])
        devices.add(bean["deviceId"])
        if offline:
            assert f"offline-private-{cycle}" in b"\n".join(uploads[cycle * 2 + 1].values()).decode()
    assert len(sessions) == 4 and len(devices) == 4
    return {"scenario": scenario, "cycles": 4, "sameProcess": True,
            "uploads": len(uploads), "distinctSessionIds": 4, "distinctDeviceIds": 4,
            "accountIsolation": True, "nativeWriterAndWatchdog": True,
            "offlineQueuePurged": offline, "emptyAfterStop": True}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--scenario", default="session-restart")
    args = parser.parse_args()
    print(json.dumps(validate(args.directory, args.scenario), indent=2))
