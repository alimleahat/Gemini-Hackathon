"""Live Camera Mirroring & Session Recording.

Every ~1.5s, the browser sends a video frame:
1. `gemini-decision-1` (Decisions API, v1beta) checks if the frame is clear
   and unobstructed (not blurry, not mostly blocked by a hand). Bad frames are
   skipped immediately.
2. `gemini-4-hydrogen` (Interactions API, structured JSON) extracts the
   circuit's gates, inputs, outputs, wires, boxes, labels, and rough normalized
   positions (0..100), marking uncertain parts explicitly.
3. Every frame, decision, schematic JSON, and the recorded video are stored in
   `app/runs/live_<timestamp>/` for evaluation replay.
"""

import base64
import json
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, Field

from app.config import LIVE_CONFIG, MODELS, RUNS_DIR
from app.pipeline.client import get_beta_client, get_client


class SchematicElement(BaseModel):
    id: str = Field(description="Unique short ID like 'in_a', 'g1', 'out_y', 'm1'.")
    type: Literal[
        "input",
        "output",
        "and",
        "or",
        "not",
        "nand",
        "nor",
        "xor",
        "xnor",
        "dff",
        "mux",
        "clock",
        "module_instance",
        "box",
        "label",
    ] = Field(description="Component type.")
    label: str = Field(description="Visible name/label on paper, e.g. 'A', 'B', 'Y', 'AND1', 'CLK', or module name.")
    x: float = Field(description="Normalized horizontal center position on paper from 0 (left) to 100 (right).")
    y: float = Field(description="Normalized vertical center position on paper from 0 (top) to 100 (bottom).")
    confidence: float = Field(description="Estimated confidence from 0.0 to 1.0.")
    uncertain: bool = Field(
        description="True if the symbol, label, or connection is partially obscured, messy, or ambiguous."
    )
    module_name: Optional[str] = Field(
        default=None,
        description="If type is 'module_instance', the exact name of the saved module written inside the box.",
    )


class SchematicBox(BaseModel):
    id: str = Field(description="Unique box ID like 'box1'.")
    name: str = Field(description="Name written in a corner of the box (inside or outside edge) or inside the box.")
    x: float = Field(description="Left edge X (0..100).")
    y: float = Field(description="Top edge Y (0..100).")
    width: float = Field(description="Box width (0..100).")
    height: float = Field(description="Box height (0..100).")
    is_definition: bool = Field(
        description="True if the box surrounds drawn gates with a module name written in one of its corners (defining a new module). False if it is an instance of an existing saved module."
    )
    contains_ids: List[str] = Field(
        default_factory=list,
        description="IDs of schematic elements drawn inside this box.",
    )
    uncertain: bool = Field(default=False, description="True if box boundaries or name are unclear.")


class SchematicWire(BaseModel):
    from_id: str = Field(description="Source element ID.")
    to_id: str = Field(description="Destination element ID.")
    from_pin: Optional[str] = Field(default=None, description="Optional source pin name (e.g. 'Q', 'S', 'Y').")
    to_pin: Optional[str] = Field(default=None, description="Optional destination pin name (e.g. 'A', 'B', 'D', 'CLK').")
    label: Optional[str] = Field(default=None, description="Optional wire/net label written on paper.")
    uncertain: bool = Field(default=False, description="True if the wire path or endpoint is unclear.")


class LiveSchematic(BaseModel):
    circuit_title: str = Field(description="Short name for the drawn circuit (e.g. 'Half Adder', 'SR Latch', '2-Bit Counter').")
    elements: List[SchematicElement] = Field(
        default_factory=list,
        description="All confident (and flagged uncertain) gates, inputs, outputs, flip-flops, and module instances.",
    )
    boxes: List[SchematicBox] = Field(
        default_factory=list,
        description="Any boxes drawn around groups of gates (e.g. module definitions with a corner name).",
    )
    wires: List[SchematicWire] = Field(
        default_factory=list,
        description="Connections between elements.",
    )
    notes: str = Field(description="1-sentence observation about what is currently visible or uncertain.")


LIVE_READER_SYSTEM = """You are a real-time digital circuit schematic reader watching a hand-drawn paper diagram from a live camera.
Extract the visible circuit into clean structured JSON so a digital schematic can be drawn live in the exact same spatial layout as the paper.

RULES:
1. Positions `x` and `y` must be in 0..100 (x=0 is left edge of the drawing area, x=100 is right; y=0 is top, y=100 is bottom), roughly matching the paper's layout so the digital schematic mirrors the paper.
2. Only include components you actually see. Do NOT invent extra gates that are not drawn.
3. If a gate, label, or wire is messy, half-drawn, or ambiguous, STILL include it if likely present, but set `uncertain: true` and lower `confidence`.
4. Use standard types: `input`, `output`, `and`, `or`, `not`, `nand`, `nor`, `xor`, `xnor`, `dff`, `mux`, `clock`, `module_instance`, `box`, `label`.
5. Hierarchy / Modules:
   - If the user drew gates INSIDE a rectangle/box and wrote a name in one of the box's corners (inside or just outside the edge), record it in `boxes` with `is_definition: true` and list the enclosed element IDs in `contains_ids`.
   - If the user drew a box with the name of an ALREADY SAVED module written INSIDE it (with no internal gates drawn), create an element with `type: "module_instance"` and `module_name: "<saved name>"`!
6. Wire every visible connection between element IDs in `wires`. Ensure `from_id` and `to_id` match IDs in `elements`.
"""


def check_frame_usable(image_b64: str, mime_type: str = "image/jpeg") -> Dict[str, Any]:
    """Fast `gemini-decision-1` check: is the live camera frame clear and unobstructed?"""
    t0 = time.perf_counter()
    client = get_beta_client()
    result = client.decisions.create(
        model=MODELS["gate"],
        input=[
            {
                "type": "image",
                "data": image_b64,
                "mime_type": mime_type or "image/jpeg",
            }
        ],
        questions={
            "is_usable_frame": {
                "type": "noul",
                "instructions": (
                    "Is this camera frame clear enough to read a hand-drawn circuit diagram on paper? "
                    "Answer YES if the drawing surface is reasonably in focus and mostly visible (even if partially drawn or a small corner of a hand/pen is at the edge). "
                    "Answer NO if the frame is very blurry, motion-smeared, pitch dark, blank/off-paper, or mostly blocked by a hand or arm."
                ),
            }
        },
    )
    ans = result.answers["is_usable_frame"]
    prob = float(ans.noul)
    conf = float(ans.confidence)
    usable = prob >= LIVE_CONFIG["min_usable_prob"]
    return {
        "model": MODELS["gate"],
        "usable": usable,
        "usable_prob": round(prob, 4),
        "confidence": round(conf, 4),
        "reason": (
            f"Clear frame ({prob * 100:.0f}%)"
            if usable
            else f"Skipped frame: blurry or blocked ({prob * 100:.0f}% usable)"
        ),
        "duration_ms": round((time.perf_counter() - t0) * 1000),
    }


def extract_live_schematic(
    image_b64: str,
    mime_type: str = "image/jpeg",
    saved_modules: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """Use `gemini-4-hydrogen` to extract structured schematic JSON from a usable frame."""
    t0 = time.perf_counter()
    client = get_client()

    prompt_parts = [
        "Read this hand-drawn digital circuit frame and return the structured schematic JSON."
    ]
    if saved_modules:
        mod_lines = ["Saved module library (recognize boxes with these names written INSIDE them as `module_instance`):"]
        for m in saved_modules:
            ins = ", ".join(p["name"] for p in m.get("inputs", []))
            outs = ", ".join(p["name"] for p in m.get("outputs", []))
            mod_lines.append(f"- {m['name']} (inputs: [{ins}] -> outputs: [{outs}])")
        prompt_parts.append("\n".join(mod_lines))

    interaction = client.interactions.create(
        model=MODELS["live_reader"],
        system_instruction=LIVE_READER_SYSTEM,
        input=[
            {"type": "image", "data": image_b64, "mime_type": mime_type or "image/jpeg"},
            {"type": "text", "text": "\n\n".join(prompt_parts)},
        ],
        response_format={
            "type": "text",
            "mime_type": "application/json",
            "schema": LiveSchematic.model_json_schema(),
        },
    )

    schematic = LiveSchematic.model_validate_json(interaction.output_text)
    return {
        "model": MODELS["live_reader"],
        "schematic": schematic.model_dump(),
        "duration_ms": round((time.perf_counter() - t0) * 1000),
    }


class LiveSessionManager:
    """Tracks and records live camera sessions into app/runs/live_<timestamp>/."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._sessions: Dict[str, Dict[str, Any]] = {}

    def start_session(self, camera_label: str = "") -> Dict[str, Any]:
        ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        session_id = f"live_{ts}_{uuid.uuid4().hex[:6]}"
        session_dir = RUNS_DIR / session_id
        frames_dir = session_dir / "frames"
        frames_dir.mkdir(parents=True, exist_ok=True)

        record = {
            "session_id": session_id,
            "started_at": datetime.now(timezone.utc).isoformat(),
            "finished_at": None,
            "camera_label": camera_label,
            "models": {
                "frame_gate": MODELS["gate"],
                "live_reader": MODELS["live_reader"],
            },
            "video_file": None,
            "frames": [],
            "latest_schematic": None,
            "latest_usable_frame": None,
        }

        with self._lock:
            self._sessions[session_id] = record
            self._write_session(session_dir, record)

        return {"session_id": session_id, "dir": str(session_dir.name)}

    def process_frame(
        self,
        session_id: str,
        image_b64: str,
        mime_type: str = "image/jpeg",
        saved_modules: Optional[List[Dict[str, Any]]] = None,
    ) -> Dict[str, Any]:
        session_dir = RUNS_DIR / session_id
        frames_dir = session_dir / "frames"
        frames_dir.mkdir(parents=True, exist_ok=True)

        with self._lock:
            record = self._sessions.get(session_id)
            if record is None:
                # Rehydrate if server restarted or session_id ad-hoc
                record = {
                    "session_id": session_id,
                    "started_at": datetime.now(timezone.utc).isoformat(),
                    "finished_at": None,
                    "camera_label": "",
                    "models": {
                        "frame_gate": MODELS["gate"],
                        "live_reader": MODELS["live_reader"],
                    },
                    "video_file": None,
                    "frames": [],
                    "latest_schematic": None,
                    "latest_usable_frame": None,
                }
                self._sessions[session_id] = record
            frame_idx = len(record["frames"]) + 1

        # Save raw frame to disk for replay/evaluation
        frame_rel = f"frames/frame_{frame_idx:04d}.jpg"
        try:
            (session_dir / frame_rel).write_bytes(base64.b64decode(image_b64))
        except Exception:
            frame_rel = None

        # 1. Fast Decision 1 usability gate
        gate = check_frame_usable(image_b64, mime_type)

        frame_entry: Dict[str, Any] = {
            "frame_index": frame_idx,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "epoch_ms": round(time.time() * 1000),
            "frame_file": frame_rel,
            "gate": gate,
            "usable": gate["usable"],
            "reader": None,
        }

        if not gate["usable"]:
            with self._lock:
                record["frames"].append(frame_entry)
                self._write_session(session_dir, record)
            return {
                "session_id": session_id,
                "frame_index": frame_idx,
                "usable": False,
                "gate": gate,
                "schematic": None,
            }

        # 2. Extract structured schematic JSON with gemini-4-hydrogen
        reader = extract_live_schematic(image_b64, mime_type, saved_modules=saved_modules)
        frame_entry["reader"] = reader

        with self._lock:
            record["frames"].append(frame_entry)
            record["latest_schematic"] = reader["schematic"]
            record["latest_usable_frame"] = frame_rel
            self._write_session(session_dir, record)

        return {
            "session_id": session_id,
            "frame_index": frame_idx,
            "usable": True,
            "gate": gate,
            "reader_ms": reader["duration_ms"],
            "schematic": reader["schematic"],
        }

    def save_video(self, session_id: str, video_bytes: bytes, content_type: str = "video/webm") -> Dict[str, Any]:
        session_dir = RUNS_DIR / session_id
        session_dir.mkdir(parents=True, exist_ok=True)
        ext = ".mp4" if "mp4" in (content_type or "").lower() else ".webm"
        filename = f"recording{ext}"
        (session_dir / filename).write_bytes(video_bytes)

        with self._lock:
            record = self._sessions.get(session_id)
            if record is not None:
                record["video_file"] = filename
                self._write_session(session_dir, record)

        return {"session_id": session_id, "video_file": filename, "bytes": len(video_bytes)}

    def select_best_recent_frame(
        self,
        session_id: str,
        window_sec: Optional[float] = None,
    ) -> Dict[str, Any]:
        """Pick the highest-scoring frame from the last ~5 seconds by gemini-decision-1."""
        win_sec = float(window_sec if window_sec is not None else LIVE_CONFIG.get("best_frame_window_sec", 5.0))
        session_dir = RUNS_DIR / session_id
        with self._lock:
            record = self._sessions.get(session_id)
            if record is None:
                sess_path = session_dir / "session.json"
                if sess_path.exists():
                    record = json.loads(sess_path.read_text(encoding="utf-8"))
                    self._sessions[session_id] = record
                else:
                    return {"found": False, "reason": "No recorded live frames in session."}
            frames = list(record.get("frames") or [])

        if not frames:
            return {"found": False, "reason": "No frames captured yet."}

        # Reference time = most recent frame's epoch_ms (or now)
        ref_ms = max((f.get("epoch_ms") or 0) for f in frames) or round(time.time() * 1000)
        cutoff_ms = ref_ms - int(win_sec * 1000)

        recent = [f for f in frames if (f.get("epoch_ms") or ref_ms) >= cutoff_ms and f.get("frame_file")]
        pool = recent if recent else [f for f in frames if f.get("frame_file")]
        if not pool:
            return {"found": False, "reason": "No saved frame image files found."}

        # Prefer highest gemini-decision-1 usable_prob, breaking ties by confidence then most recent
        best = max(
            pool,
            key=lambda f: (
                float((f.get("gate") or {}).get("usable_prob", 0.0)),
                float((f.get("gate") or {}).get("confidence", 0.0)),
                int(f.get("frame_index", 0)),
            ),
        )

        img_path = session_dir / best["frame_file"]
        if not img_path.exists():
            return {"found": False, "reason": f"Frame file missing: {best['frame_file']}"}

        image_b64 = base64.b64encode(img_path.read_bytes()).decode("ascii")
        best_gate = best.get("gate") or {}
        best_schematic = (best.get("reader") or {}).get("schematic")

        # If the sharpest frame happened to be below threshold or had no reader run,
        # fall back to the latest extracted schematic for layout context
        with self._lock:
            if not best_schematic and record:
                best_schematic = record.get("latest_schematic")
            chosen_meta = {
                "frame_index": best["frame_index"],
                "frame_file": best["frame_file"],
                "usable_prob": best_gate.get("usable_prob", 0.0),
                "confidence": best_gate.get("confidence", 0.0),
                "window_sec": win_sec,
                "window_candidates": len(recent),
                "total_frames": len(frames),
            }
            if record is not None:
                record["chosen_frame"] = chosen_meta
                self._write_session(session_dir, record)

        return {
            "found": True,
            **chosen_meta,
            "image_b64": image_b64,
            "mime_type": "image/jpeg",
            "schematic": best_schematic,
        }

    def finish_session(self, session_id: str) -> Dict[str, Any]:
        session_dir = RUNS_DIR / session_id
        with self._lock:
            record = self._sessions.get(session_id)
            if record is not None:
                record["finished_at"] = datetime.now(timezone.utc).isoformat()
                self._write_session(session_dir, record)
                total = len(record["frames"])
                usable = sum(1 for f in record["frames"] if f.get("usable"))
                return {
                    "session_id": session_id,
                    "total_frames": total,
                    "usable_frames": usable,
                    "video_file": record.get("video_file"),
                }
        return {"session_id": session_id, "total_frames": 0, "usable_frames": 0}

    @staticmethod
    def _write_session(session_dir: Path, record: Dict[str, Any]) -> None:
        (session_dir / "session.json").write_text(
            json.dumps(record, indent=2),
            encoding="utf-8",
        )
        # Also write a clean per-frame Decision 1 scores log for evaluation
        scores_payload = {
            "session_id": record.get("session_id"),
            "model": MODELS["gate"],
            "chosen_frame": record.get("chosen_frame"),
            "frames": [
                {
                    "frame_index": f.get("frame_index"),
                    "timestamp": f.get("timestamp"),
                    "epoch_ms": f.get("epoch_ms"),
                    "frame_file": f.get("frame_file"),
                    "usable": f.get("usable"),
                    "usable_prob": (f.get("gate") or {}).get("usable_prob"),
                    "confidence": (f.get("gate") or {}).get("confidence"),
                    "duration_ms": (f.get("gate") or {}).get("duration_ms"),
                    "reason": (f.get("gate") or {}).get("reason"),
                }
                for f in (record.get("frames") or [])
            ],
        }
        (session_dir / "decision1_scores.json").write_text(
            json.dumps(scores_payload, indent=2),
            encoding="utf-8",
        )


live_session_manager = LiveSessionManager()
