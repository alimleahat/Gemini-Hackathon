"""Replay & Score Hand-Drawn Live Sessions against Reference Answer Keys.

Usage:
  1. Scan app/runs/ for new live sessions and add untagged entries to labels.json:
       .venv/bin/python eval_drawings/score_drawings.py --scan

  2. Edit eval_drawings/labels.json to tag each session with one of:
       half_adder, full_adder, adder_4bit, adder_4bit_7seg, counter_4bit

  3. Run baseline replay + full-system scoring and print report:
       .venv/bin/python eval_drawings/score_drawings.py
"""

import argparse
import base64
import datetime
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from dotenv import load_dotenv
from google import genai

ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parent
APP_RUNS_DIR = REPO_ROOT / "app" / "runs"
LABELS_FILE = ROOT / "labels.json"
RESULTS_FILE = ROOT / "results.json"
BASELINE_MODEL = "gemini-4-neon"

if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from answer_keys import CIRCUIT_ORDER, evaluate_against_answer_key


def scan_live_sessions() -> int:
    """Discover any live_* session folders in app/runs/ and add untagged ones to labels.json."""
    if LABELS_FILE.exists():
        data = json.loads(LABELS_FILE.read_text(encoding="utf-8"))
    else:
        data = {"valid_circuits": CIRCUIT_ORDER, "sessions": {}}

    sessions = data.setdefault("sessions", {})
    added = 0
    if APP_RUNS_DIR.exists():
        for d in sorted(APP_RUNS_DIR.glob("live_*")):
            if not d.is_dir():
                continue
            sid = d.name
            if sid not in sessions:
                sessions[sid] = {
                    "circuit": "TODO",
                    "notes": "",
                }
                added += 1

    LABELS_FILE.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"Scanned {APP_RUNS_DIR}: added {added} new live session(s). Total in labels.json: {len(sessions)}")
    return added


def find_best_frame_for_session(session_dir: Path) -> Tuple[Optional[Path], Optional[Dict[str, Any]]]:
    """Return the best frame image path from a live session (chosen_frame or highest Decision 1 score)."""
    scores_path = session_dir / "decision1_scores.json"
    sess_path = session_dir / "session.json"

    chosen = None
    frames = []
    if scores_path.exists():
        sd = json.loads(scores_path.read_text(encoding="utf-8"))
        chosen = sd.get("chosen_frame")
        frames = sd.get("frames") or []
    elif sess_path.exists():
        sd = json.loads(sess_path.read_text(encoding="utf-8"))
        chosen = sd.get("chosen_frame")
        frames = sd.get("frames") or []

    if chosen and chosen.get("frame_file"):
        p = session_dir / chosen["frame_file"]
        if p.exists():
            return p, chosen

    # Fallback: highest usable_prob frame in session
    valid = [f for f in frames if f.get("frame_file") and (session_dir / f["frame_file"]).exists()]
    if valid:
        best = max(
            valid,
            key=lambda f: (
                float(f.get("usable_prob") or (f.get("gate") or {}).get("usable_prob") or 0.0),
                int(f.get("frame_index") or 0),
            ),
        )
        return session_dir / best["frame_file"], best

    # Last fallback: last jpg in frames/
    jpgs = sorted((session_dir / "frames").glob("*.jpg")) if (session_dir / "frames").exists() else []
    if jpgs:
        return jpgs[-1], None
    return None, None


def find_pipeline_run_for_session(session_id: str, explicit_run_file: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """Find the app/runs/run_*.json produced when the user pressed Done in this live session."""
    if explicit_run_file:
        p = APP_RUNS_DIR / explicit_run_file
        if p.exists():
            return json.loads(p.read_text(encoding="utf-8"))

    if not APP_RUNS_DIR.exists():
        return None
    for p in sorted(APP_RUNS_DIR.glob("run_*.json"), reverse=True):
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
            if (d.get("input") or {}).get("live_session_id") == session_id:
                return d
        except Exception:
            continue
    return None


def run_baseline_single_call(client: genai.Client, image_path: Path) -> Tuple[str, float]:
    """Baseline: single gemini-4-neon call on the best frame, no loop, no modules, no tests."""
    b64 = base64.b64encode(image_path.read_bytes()).decode("ascii")
    mime = "image/png" if image_path.suffix.lower() == ".png" else "image/jpeg"
    t0 = time.perf_counter()
    inter = client.interactions.create(
        model=BASELINE_MODEL,
        input=[
            {"type": "image", "data": b64, "mime_type": mime},
            {
                "type": "text",
                "text": (
                    "Write synthesizable Verilog for this circuit. "
                    "Use clear port names matching the labels drawn in the diagram. "
                    "Return ONLY the Verilog code inside a single ```verilog ... ``` block."
                ),
            },
        ],
        timeout=180.0,
    )
    elapsed = round(time.perf_counter() - t0, 2)
    return inter.output_text or "", elapsed


def classify_failure_reason(eval_res: Dict[str, Any], gate_passed: Optional[bool] = True) -> str:
    if gate_passed is False:
        return "misread_drawing (rejected by gate)"
    st = eval_res.get("status", "")
    if st == "pass":
        return "pass"
    if st == "ambiguous_ports":
        return f"misread_drawing / wrong_module ({eval_res.get('reason', '')})"
    if st == "compile_error":
        return f"compile_error ({eval_res.get('reason', '')[:120]})"
    if st == "logic_error":
        return f"logic_error ({eval_res.get('reason', '')[:120]})"
    return f"{st}: {eval_res.get('reason', '')[:120]}"


def score_all() -> None:
    load_dotenv(REPO_ROOT / ".env")
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY not found in .env")
    client = genai.Client(api_key=api_key)

    labels_data = json.loads(LABELS_FILE.read_text(encoding="utf-8"))
    sessions_map: Dict[str, Any] = labels_data.get("sessions") or {}

    tagged = [
        (sid, info if isinstance(info, dict) else {"circuit": str(info)})
        for sid, info in sessions_map.items()
        if (info.get("circuit") if isinstance(info, dict) else info) in CIRCUIT_ORDER
    ]

    if not tagged:
        print("No tagged sessions found in eval_drawings/labels.json.")
        print("Run `--scan` after recording live sessions, then set each session's `circuit` field.")
        return

    session_results: List[Dict[str, Any]] = []
    failures: List[Dict[str, Any]] = []

    for sid, meta in tagged:
        circuit = meta["circuit"]
        sdir = APP_RUNS_DIR / sid
        if not sdir.exists():
            print(f"[WARN] Session folder not found: {sdir}")
            continue

        frame_path, frame_meta = find_best_frame_for_session(sdir)
        if not frame_path:
            print(f"[WARN] No frame image found in {sdir}")
            continue

        print(f"Scoring {sid} ({circuit}) using {frame_path.name}...", flush=True)

        # 1. Baseline: single Neon call on best frame
        base_code, base_sec = run_baseline_single_call(client, frame_path)
        base_eval = evaluate_against_answer_key(circuit, base_code, pin_mapping=None)

        # 2. Our System: final design produced in that session
        run_rec = find_pipeline_run_for_session(sid, meta.get("run_file"))
        if not run_rec:
            sys_eval = {"passed": False, "status": "missing_run", "reason": "No matching app/runs/run_*.json for this session."}
            sys_sec = 0.0
            gate_ok = None
        else:
            gate_ok = (run_rec.get("gate") or {}).get("passed")
            sys_sec = round((run_rec.get("total_duration_ms") or 0) / 1000.0, 2)
            if gate_ok is False:
                sys_eval = {"passed": False, "status": "gate_rejected", "reason": (run_rec.get("gate") or {}).get("reason", "Rejected by Decision 1 gate")}
            else:
                gen = run_rec.get("generate") or {}
                rounds = run_rec.get("improve_rounds") or []
                final_v = rounds[-1]["verilog_code"] if rounds else (gen.get("verilog_code") or "")
                pin_map = gen.get("pin_mapping") or []
                sys_eval = evaluate_against_answer_key(circuit, final_v, pin_mapping=pin_map)

        rec = {
            "session_id": sid,
            "circuit": circuit,
            "best_frame": str(frame_path.name),
            "baseline": {
                "passed": base_eval["passed"],
                "status": base_eval["status"],
                "elapsed_seconds": base_sec,
                "reason": classify_failure_reason(base_eval),
                "details": base_eval,
            },
            "our_system": {
                "passed": sys_eval["passed"],
                "status": sys_eval["status"],
                "elapsed_seconds": sys_sec,
                "reason": classify_failure_reason(sys_eval, gate_passed=gate_ok),
                "details": sys_eval,
            },
        }
        session_results.append(rec)

        if not base_eval["passed"]:
            failures.append({"session_id": sid, "circuit": circuit, "system": "baseline", "reason": rec["baseline"]["reason"]})
        if not sys_eval["passed"]:
            failures.append({"session_id": sid, "circuit": circuit, "system": "our_system", "reason": rec["our_system"]["reason"]})

    # Per-circuit summary table
    per_circuit = []
    first_failing_level = None
    for lvl, circuit in enumerate(CIRCUIT_ORDER, start=1):
        rows = [r for r in session_results if r["circuit"] == circuit]
        n = len(rows)
        if not n:
            continue
        b_pass = sum(1 for r in rows if r["baseline"]["passed"])
        s_pass = sum(1 for r in rows if r["our_system"]["passed"])
        avg_b_sec = round(sum(r["baseline"]["elapsed_seconds"] for r in rows) / n, 1)
        avg_s_sec = round(sum(r["our_system"]["elapsed_seconds"] for r in rows) / n, 1)
        if s_pass < n and first_failing_level is None:
            first_failing_level = f"Level {lvl}: {circuit}"
        per_circuit.append({
            "level": lvl,
            "circuit": circuit,
            "sessions": n,
            "baseline_passed": b_pass,
            "baseline_pass_rate_pct": round(100.0 * b_pass / n, 1),
            "system_passed": s_pass,
            "system_pass_rate_pct": round(100.0 * s_pass / n, 1),
            "avg_baseline_seconds": avg_b_sec,
            "avg_system_seconds": avg_s_sec,
        })

    payload = {
        "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "per_circuit": per_circuit,
        "first_failing_level": first_failing_level or "None (100% pass across all tested levels)",
        "failures": failures,
        "sessions": session_results,
    }
    RESULTS_FILE.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    # Print clean report
    print("\n=== DRAWING EVALUATION REPORT ===")
    print(f"{'Lvl':<4} | {'Circuit':<18} | {'Sessions':<8} | {'Baseline Pass':<15} | {'Our System Pass':<15} | {'Avg Time (Base / Sys)'}")
    print("-" * 92)
    for row in per_circuit:
        bp = f"{row['baseline_passed']}/{row['sessions']} ({row['baseline_pass_rate_pct']:.0f}%)"
        sp = f"{row['system_passed']}/{row['sessions']} ({row['system_pass_rate_pct']:.0f}%)"
        print(f"{row['level']:<4} | {row['circuit']:<18} | {row['sessions']:<8} | {bp:<15} | {sp:<15} | {row['avg_baseline_seconds']}s / {row['avg_system_seconds']}s")
    print(f"\nLevel where our system starts failing: {payload['first_failing_level']}")
    if failures:
        print("\nFailures:")
        for f in failures:
            print(f"  - [{f['system']}] {f['session_id']} ({f['circuit']}): {f['reason']}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Score hand-drawn circuit live sessions.")
    parser.add_argument("--scan", action="store_true", help="Scan app/runs/ for new live_* sessions and add to labels.json")
    args = parser.parse_args()
    if args.scan:
        scan_live_sessions()
    else:
        score_all()


if __name__ == "__main__":
    main()
