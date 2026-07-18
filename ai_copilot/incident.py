#!/usr/bin/env python3
"""Validate evidence-grounded incident recommendations without cluster write access."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ALLOWED_ACTION = "shift_traffic"
ALLOWED_ALERTS = {
    "PlatformApiAvailabilityBudgetFastBurn",
    "PlatformApiAvailabilityBudgetSlowBurn",
    "PlatformApiLatencyObjectiveAtRisk",
    "PlatformApiAvailabilityDemo",
}
ALLOWED_CLUSTERS = {"gke", "aks"}
MAX_WEIGHT_DELTA = 20
MIN_CONFIDENCE = 0.80
MAX_EVIDENCE_AGE_SECONDS = 900
REQUIRED_EVIDENCE_TYPES = {"metric", "trace", "kubernetes"}


class PolicyError(ValueError):
    """A recommendation violates an explicit remediation guardrail."""


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise PolicyError(f"cannot read JSON from {path}: {error}") from error
    if not isinstance(value, dict):
        raise PolicyError(f"{path} must contain a JSON object")
    return value


def read_weights(path: Path) -> dict[str, int]:
    values: dict[str, int] = {}
    names = {"TRAFFIC_WEIGHT_GKE": "gke", "TRAFFIC_WEIGHT_AKS": "aks"}
    try:
        lines = path.read_text().splitlines()
    except OSError as error:
        raise PolicyError(f"cannot read traffic weights from {path}: {error}") from error
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in names:
            try:
                values[names[key]] = int(value)
            except ValueError as error:
                raise PolicyError(f"{key} must be an integer") from error
    if set(values) != ALLOWED_CLUSTERS or any(weight < 1 or weight > 99 for weight in values.values()):
        raise PolicyError("traffic weights must define GKE and AKS values from 1 to 99")
    if sum(values.values()) != 100:
        raise PolicyError("traffic weights must total 100")
    return values


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PolicyError(message)


def validate(incident: dict[str, Any], diagnosis: dict[str, Any], weights: dict[str, int]) -> dict[str, Any]:
    require(incident.get("schema_version") == "v1", "incident schema_version must be v1")
    require(diagnosis.get("schema_version") == "v1", "diagnosis schema_version must be v1")
    require(diagnosis.get("incident_id") == incident.get("incident_id"), "incident IDs must match")
    require(incident.get("alert") in ALLOWED_ALERTS, "incident alert is not eligible for remediation")

    evidence = incident.get("evidence")
    require(isinstance(evidence, list) and evidence, "incident must include evidence")
    evidence_by_id = {item.get("id"): item for item in evidence if isinstance(item, dict)}
    require(len(evidence_by_id) == len(evidence), "evidence IDs must be unique")
    for item in evidence:
        require(isinstance(item.get("id"), str) and item["id"], "evidence ID is required")
        require(item.get("type") in REQUIRED_EVIDENCE_TYPES, "evidence type is not allowed")
        require(isinstance(item.get("age_seconds"), int) and 0 <= item["age_seconds"] <= MAX_EVIDENCE_AGE_SECONDS,
                "evidence is missing or too old")
    require({item["type"] for item in evidence} >= REQUIRED_EVIDENCE_TYPES,
            "incident needs metric, trace, and Kubernetes evidence")

    confidence = diagnosis.get("confidence")
    require(isinstance(confidence, (int, float)) and confidence >= MIN_CONFIDENCE,
            "confidence is below the approved threshold")
    evidence_ids = diagnosis.get("evidence_ids")
    require(isinstance(evidence_ids, list) and set(evidence_ids) == set(evidence_by_id),
            "diagnosis must reference every supplied evidence ID exactly")

    recommendation = diagnosis.get("recommendation")
    require(isinstance(recommendation, dict), "diagnosis must include a recommendation")
    source = recommendation.get("source_cluster")
    destination = recommendation.get("destination_cluster")
    delta = recommendation.get("weight_delta")
    require(recommendation.get("action") == ALLOWED_ACTION, "only shift_traffic is allowed")
    require(source == incident.get("source_cluster") and source in ALLOWED_CLUSTERS,
            "recommendation source cluster is invalid")
    require(destination == incident.get("destination_cluster") and destination in ALLOWED_CLUSTERS and destination != source,
            "recommendation destination cluster is invalid")
    require(isinstance(delta, int) and 1 <= delta <= MAX_WEIGHT_DELTA,
            f"traffic shift must be between 1 and {MAX_WEIGHT_DELTA}")
    require(recommendation.get("approval_required") is True, "human approval is required")
    destination_state = incident.get("destination")
    require(isinstance(destination_state, dict) and destination_state.get("healthy") is True,
            "destination cluster is not healthy")
    require(destination_state.get("available_replicas", 0) >= destination_state.get("minimum_available_replicas", 1),
            "destination does not meet its minimum capacity")
    require(recommendation.get("rollback_weights") == weights, "rollback weights must match the current Git state")

    proposed = dict(weights)
    proposed[source] -= delta
    proposed[destination] += delta
    require(all(1 <= weight <= 99 for weight in proposed.values()), "proposed weights are outside 1..99")
    return {
        "approved": True,
        "incident_id": incident["incident_id"],
        "approval_required": True,
        "confidence": confidence,
        "evidence_ids": evidence_ids,
        "current_weights": weights,
        "proposed_weights": proposed,
        "rollback_weights": weights,
        "action": ALLOWED_ACTION,
    }


def render_diff(current: dict[str, int], proposed: dict[str, int], path: str) -> str:
    lines = [f"--- {path}", f"+++ {path}"]
    for cluster in ("gke", "aks"):
        key = f"TRAFFIC_WEIGHT_{cluster.upper()}"
        if current[cluster] != proposed[cluster]:
            lines.extend([f"-{key}={current[cluster]}", f"+{key}={proposed[cluster]}"])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("incident", type=Path)
    parser.add_argument("diagnosis", type=Path)
    parser.add_argument("--weights", type=Path, default=Path("config/traffic-weights.env"))
    parser.add_argument("--format", choices=("json", "diff"), default="json")
    args = parser.parse_args()
    try:
        result = validate(read_json(args.incident), read_json(args.diagnosis), read_weights(args.weights))
    except PolicyError as error:
        print(f"policy rejected: {error}", file=sys.stderr)
        return 1
    if args.format == "diff":
        print(render_diff(result["current_weights"], result["proposed_weights"], str(args.weights)))
    else:
        print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
