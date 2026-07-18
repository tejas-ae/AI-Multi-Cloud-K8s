#!/usr/bin/env python3
"""Request a structured, evidence-grounded incident diagnosis from Claude."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


API_URL = "https://api.anthropic.com/v1/messages"
MODELS_URL = "https://api.anthropic.com/v1/models?limit=100"
API_VERSION = "2023-06-01"


class ClaudeError(ValueError):
    """The live analyzer could not produce a usable structured response."""


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ClaudeError(f"cannot read JSON from {path}: {error}") from error
    if not isinstance(value, dict):
        raise ClaudeError(f"{path} must contain a JSON object")
    return value


def read_weights(path: Path) -> dict[str, int]:
    names = {"TRAFFIC_WEIGHT_GKE": "gke", "TRAFFIC_WEIGHT_AKS": "aks"}
    values: dict[str, int] = {}
    try:
        lines = path.read_text().splitlines()
    except OSError as error:
        raise ClaudeError(f"cannot read traffic weights from {path}: {error}") from error
    for line in lines:
        if "=" not in line:
            continue
        key, value = line.strip().split("=", 1)
        if key in names:
            try:
                values[names[key]] = int(value)
            except ValueError as error:
                raise ClaudeError(f"{key} must be an integer") from error
    if set(values) != {"gke", "aks"} or sum(values.values()) != 100:
        raise ClaudeError("traffic weights must define GKE and AKS values totaling 100")
    return values


def build_request(incident: dict[str, Any], weights: dict[str, int], model: str) -> bytes:
    schema = {
        "schema_version": "v1",
        "incident_id": incident.get("incident_id"),
        "confidence": "number from 0 to 1",
        "evidence_ids": ["every supplied evidence ID, exactly once"],
        "recommendation": {
            "action": "shift_traffic",
            "source_cluster": "gke or aks",
            "destination_cluster": "gke or aks",
            "weight_delta": "integer from 1 to 20",
            "approval_required": True,
            "rollback_weights": weights,
        },
    }
    prompt = {
        "task": "Analyze this incident. Return only a JSON object matching the required schema.",
        "constraints": [
            "Do not suggest shell commands, Kubernetes patches, or direct cloud changes.",
            "The only permitted action is shift_traffic.",
            "Human approval must remain true.",
            "Reference every supplied evidence ID exactly once.",
            "Use the supplied current weights as rollback_weights.",
            "A shift_traffic recommendation is policy-eligible only when confidence is at least 0.80.",
            "Do not inflate confidence; base it on agreement between metric, trace, and Kubernetes evidence.",
        ],
        "required_schema": schema,
        "current_traffic_weights": weights,
        "incident": incident,
    }
    body = {
        "model": model,
        "max_tokens": 1200,
        "system": "You are a cautious SRE assistant. Return JSON only; never include secrets.",
        "messages": [{"role": "user", "content": json.dumps(prompt, separators=(",", ":"))}],
    }
    return json.dumps(body, separators=(",", ":")).encode()


def extract_json(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("\n", 1)[1] if "\n" in cleaned else ""
        cleaned = cleaned.rsplit("```", 1)[0].strip()
    try:
        value = json.loads(cleaned)
    except json.JSONDecodeError as error:
        raise ClaudeError("Claude response was not valid JSON") from error
    if not isinstance(value, dict):
        raise ClaudeError("Claude response must be a JSON object")
    return value


def discover_model(api_key: str) -> str:
    request = urllib.request.Request(
        MODELS_URL,
        method="GET",
        headers={
            "anthropic-version": API_VERSION,
            "x-api-key": api_key,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read())
    except urllib.error.HTTPError as error:
        raise ClaudeError(f"cannot list enabled Claude models: HTTP {error.code}") from error
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise ClaudeError("cannot list enabled Claude models") from error
    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, list):
        raise ClaudeError("Claude model list was missing data")
    model_ids = [
        item.get("id")
        for item in data
        if isinstance(item, dict) and isinstance(item.get("id"), str) and item["id"]
    ]
    if not model_ids:
        raise ClaudeError("this Anthropic account has no enabled models")
    return next((model_id for model_id in model_ids if "sonnet" in model_id.lower()), model_ids[0])


def call_claude(request_body: bytes, api_key: str) -> dict[str, Any]:
    request = urllib.request.Request(
        API_URL,
        data=request_body,
        method="POST",
        headers={
            "content-type": "application/json",
            "anthropic-version": API_VERSION,
            "x-api-key": api_key,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            payload = json.loads(response.read())
    except urllib.error.HTTPError as error:
        error_type = "unknown_error"
        error_message = "request rejected"
        try:
            error_payload = json.loads(error.read())
            if isinstance(error_payload, dict) and isinstance(error_payload.get("error"), dict):
                error_type = str(error_payload["error"].get("type", error_type))
                error_message = str(error_payload["error"].get("message", error_message))
        except (OSError, json.JSONDecodeError):
            pass
        raise ClaudeError(
            f"Claude API request failed with HTTP {error.code} ({error_type}): {error_message}"
        ) from error
    except (urllib.error.URLError, TimeoutError) as error:
        raise ClaudeError("Claude API request failed") from error
    content = payload.get("content") if isinstance(payload, dict) else None
    if not isinstance(content, list):
        raise ClaudeError("Claude API response did not contain message content")
    text = "".join(item.get("text", "") for item in content if isinstance(item, dict) and item.get("type") == "text")
    if not text:
        raise ClaudeError("Claude API response did not contain text")
    return extract_json(text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("incident", type=Path)
    parser.add_argument("--weights", type=Path, default=Path("config/traffic-weights.env"))
    parser.add_argument("--offline-response", type=Path, help="parse a recorded model response without calling the API")
    args = parser.parse_args()
    try:
        incident = read_json(args.incident)
        weights = read_weights(args.weights)
        if args.offline_response:
            diagnosis = read_json(args.offline_response)
        else:
            api_key = os.environ.get("ANTHROPIC_API_KEY")
            if not api_key:
                raise ClaudeError("ANTHROPIC_API_KEY must be set locally")
            configured_model = os.environ.get("ANTHROPIC_MODEL", "auto")
            model = discover_model(api_key) if configured_model == "auto" else configured_model
            print(f"Claude model selected: {model}", file=sys.stderr)
            diagnosis = call_claude(build_request(incident, weights, model), api_key)
    except ClaudeError as error:
        print(f"Claude analysis failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(diagnosis, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
