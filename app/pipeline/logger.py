"""Run Logger: saves every pipeline run to app/runs/ as JSON (+ input image)."""

import base64
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from app.config import RUN_IMAGES_DIR, RUNS_DIR

MIME_TO_EXT = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
}


def save_input_image(run_id: str, image_b64: str, mime_type: str) -> str:
    """Save the uploaded/captured input image to app/runs/images/ and return relative path."""
    RUN_IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    ext = MIME_TO_EXT.get((mime_type or "").lower(), ".jpg")
    filename = f"{run_id}{ext}"
    out_path = RUN_IMAGES_DIR / filename
    raw = base64.b64decode(image_b64)
    out_path.write_bytes(raw)
    return f"images/{filename}"


def save_run_log(run_record: Dict[str, Any]) -> Path:
    """Write the complete run JSON to app/runs/<run_id>.json."""
    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    run_id = run_record["run_id"]
    out_path = RUNS_DIR / f"{run_id}.json"
    out_path.write_text(json.dumps(run_record, indent=2), encoding="utf-8")
    return out_path


def make_run_id() -> str:
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    return f"run_{ts}"


def list_recent_runs(limit: int = 20) -> List[Dict[str, Any]]:
    """Return lightweight summaries of recent saved runs (newest first)."""
    if not RUNS_DIR.exists():
        return []
    files = sorted(RUNS_DIR.glob("run_*.json"), reverse=True)[:limit]
    summaries: List[Dict[str, Any]] = []
    for path in files:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            synth = data.get("synthesis") or {}
            gen = data.get("generate") or {}
            final_test = data.get("final_test") or data.get("initial_test") or {}
            summaries.append(
                {
                    "run_id": data.get("run_id", path.stem),
                    "timestamp": data.get("timestamp"),
                    "mode": data.get("mode", "full"),
                    "circuit_name": gen.get("circuit_name", "—"),
                    "gate_passed": (data.get("gate") or {}).get("passed"),
                    "test_passed": final_test.get("passed"),
                    "improve_rounds": len(data.get("improve_rounds") or []),
                    "luts": synth.get("luts") if synth.get("ok") else None,
                    "ffs": synth.get("ffs") if synth.get("ok") else None,
                    "total_duration_ms": data.get("total_duration_ms"),
                }
            )
        except Exception:
            continue
    return summaries
