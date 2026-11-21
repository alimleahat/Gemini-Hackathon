"""Stronger Baseline: 'Neon with retries, no tools' on the 20 CVDP cid003 problems.

For each problem:
  - Round 1: gemini-4-neon writes an initial RTL design from the spec.
  - Rounds 2-4 (3 review rounds): gemini-4-neon reviews and improves its own code
    with prompt: "Review your design against the spec and fix any bugs."
  - NO simulator, NO testbench, NO tool feedback at any point.
  - Final design (after Round 4) is graded with CVDP's hidden tests + Yosys synth_xilinx.

Writes incremental results to engineer/neon_retries_results.json.
Does NOT touch engineer/results.json, engineer/generated/, app/, or pilot folders.
"""

import concurrent.futures
import datetime
import json
import os
import re
import subprocess
import tempfile
import threading
import time
from pathlib import Path

from dotenv import load_dotenv
from google import genai
from google.genai import types

ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parent
PILOT_DIR = REPO_ROOT / "pilot_cvdp"
DATASET_PATH = PILOT_DIR / "cvdp_benchmark" / "cvdp_v1.1.0_nonagentic_code_generation_no_commercial.jsonl"
GENERATED_DIR = ROOT / "neon_retries_generated"
RESULTS_FILE = ROOT / "neon_retries_results.json"
PYTEST_BIN = str((REPO_ROOT / ".venv" / "bin" / "pytest").resolve())

MODEL = "gemini-4-neon"
NUM_REVIEW_ROUNDS = 3  # 1 initial + 3 review rounds = 4 total rounds
MAX_WORKERS = 8

SELECTED_PROBLEMS = [
    # Arithmetic (5)
    ("cvdp_copilot_complex_multiplier_0001", "arithmetic"),
    ("cvdp_copilot_matrix_multiplier_0001", "arithmetic"),
    ("cvdp_copilot_restoring_division_0001", "arithmetic"),
    ("cvdp_copilot_16qam_mapper_0001", "arithmetic"),
    ("cvdp_copilot_hill_cipher_0001", "arithmetic"),
    # FSMs / Control (5)
    ("cvdp_copilot_bcd_counter_0001", "fsm"),
    ("cvdp_copilot_vending_machine_0001", "fsm"),
    ("cvdp_copilot_thermostat_0001", "fsm"),
    ("cvdp_copilot_car_parking_management_0001", "fsm"),
    ("cvdp_copilot_microcode_sequencer_0001", "fsm"),
    # Memory / Buffers / Data Structures (5)
    ("cvdp_copilot_sorter_0001", "memory"),
    ("cvdp_copilot_moving_average_0001", "memory"),
    ("cvdp_copilot_sync_lifo_0001", "memory"),
    ("cvdp_copilot_secure_read_write_register_bank_0001", "memory"),
    ("cvdp_copilot_load_store_unit_0001", "memory"),
    # Protocols / Interfaces (5)
    ("cvdp_copilot_64b66b_encoder_0001", "protocol"),
    ("cvdp_copilot_apb_gpio_0001", "protocol"),
    ("cvdp_copilot_axi_register_0001", "protocol"),
    ("cvdp_copilot_wb2ahb_0001", "protocol"),
    ("cvdp_copilot_vga_controller_0001", "protocol"),
]

DESIGN_SYSTEM = (
    "You are an expert Verilog/SystemVerilog hardware design engineer. "
    "Implement the requested RTL module cleanly so that it compiles with Icarus Verilog (`iverilog -g2012`) "
    "and synthesizes cleanly with Yosys (`read_verilog -sv`). "
    "Return ONLY the complete Verilog/SystemVerilog source code inside a single ```systemverilog ... ``` code block. "
    "Do not include a testbench, do not include `timescale, and do not include explanations."
)

REVIEW_SYSTEM = (
    "You are an expert Verilog/SystemVerilog hardware design engineer reviewing your own RTL implementation. "
    "Carefully check every requirement in the specification (ports, widths, reset polarity/behavior, edge cases, "
    "timing/latency, handshakes, and Icarus Verilog `-g2012` / Yosys `read_verilog -sv` compatibility) and fix any bugs. "
    "Return ONLY the complete improved Verilog/SystemVerilog source code inside a single ```systemverilog ... ``` code block. "
    "Do not include a testbench, do not include `timescale, and do not include explanations."
)

print_lock = threading.Lock()
file_lock = threading.Lock()
thread_local = threading.local()


def get_client(api_key: str) -> genai.Client:
    if not hasattr(thread_local, "client"):
        thread_local.client = genai.Client(api_key=api_key)
    return thread_local.client


def extract_verilog(text: str) -> str:
    if not text:
        return ""
    blocks = re.findall(
        r"```(?:systemverilog|verilog|sv)?\s*\n(.*?)```",
        text,
        flags=re.DOTALL | re.IGNORECASE,
    )
    if blocks:
        for b in blocks:
            if re.search(r"\bmodule\s+\w+", b):
                return b.strip()
        return blocks[-1].strip()
    m = re.search(r"((?:package\b.*?endpackage\s*)?module\s+\w+.*?endmodule)", text, flags=re.DOTALL)
    if m:
        return m.group(1).strip()
    return text.strip()


def parse_env_file(env_text: str, code_dir: Path, src_dir: Path) -> dict:
    env_vars = {}
    for line in env_text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = [x.strip() for x in line.split("=", 1)]
        v = v.replace("/code", str(code_dir)).replace("/src", str(src_dir))
        env_vars[k] = v
    return env_vars


def classify_failure(output: str) -> str:
    compile_markers = [
        "error(s) during elaboration",
        "syntax error",
        "Unable to bind",
        "Unknown module type",
        "requires an explicit cast",
        "is not a valid l-value",
        "iverilog",
        "Command '['iverilog'",
        "Compile failed",
        "Compilation failed",
        "Sorry: ",
        "error: ",
    ]
    sim_started = ("TESTS=" in output and "PASS=" in output) or "running " in output.lower()
    if not sim_started:
        for marker in compile_markers:
            if marker in output:
                return "compile_error"
        if "CalledProcessError" in output and "vvp" not in output:
            return "compile_error"
    return "test_failure"


def run_cvdp_harness(item: dict, sv_code: str, save_root: Path) -> tuple[dict, list[Path], str]:
    out_files = list(item["output"]["context"].keys())
    target_rel = out_files[0]

    out_path = save_root / target_rel
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(sv_code + "\n", encoding="utf-8")
    saved_paths = [out_path]

    with tempfile.TemporaryDirectory() as tmpdir:
        d = Path(tmpdir)
        code_dir = d / "code"
        src_dir = d / "src"
        code_dir.mkdir()
        src_dir.mkdir()

        for rel, content in item["input"].get("context", {}).items():
            p = code_dir / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding="utf-8")

        p = code_dir / target_rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(sv_code + "\n", encoding="utf-8")

        for rel, content in item["harness"]["files"].items():
            hp = d / rel
            hp.parent.mkdir(parents=True, exist_ok=True)
            hp.write_text(content, encoding="utf-8")

        env_vars = parse_env_file((src_dir / ".env").read_text(encoding="utf-8"), code_dir, src_dir)
        toplevel = env_vars.get("TOPLEVEL", "")

        env = os.environ.copy()
        env.update(env_vars)
        env["PYTHONPATH"] = str(src_dir)

        try:
            proc = subprocess.run(
                [PYTEST_BIN, "-s", str(src_dir / "test_runner.py"), "-v"],
                cwd=str(d),
                env=env,
                capture_output=True,
                text=True,
                timeout=60,
            )
        except subprocess.TimeoutExpired:
            return (
                {
                    "status": "fail",
                    "failure_type": "timeout",
                    "error_message": "Test harness timed out after 60s",
                },
                saved_paths,
                toplevel,
            )

        combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
        if proc.returncode == 0:
            return (
                {
                    "status": "pass",
                    "failure_type": None,
                    "error_message": None,
                },
                saved_paths,
                toplevel,
            )

        ftype = classify_failure(combined)
        err_lines = [
            ln for ln in combined.splitlines()
            if any(tok in ln for tok in ("error:", "ERROR", "FAIL", "AssertionError", "SyntaxError", "Sorry:", "CalledProcessError"))
        ]
        snippet = "\n".join(err_lines[:10]) if err_lines else combined[-600:]
        return (
            {
                "status": "fail",
                "failure_type": ftype,
                "error_message": snippet[:600].strip(),
            },
            saved_paths,
            toplevel,
        )


def synthesize_yosys_xilinx(sv_paths: list[Path], toplevel: str) -> dict:
    with tempfile.TemporaryDirectory() as tmpdir:
        stat_json = Path(tmpdir) / "stat.json"
        files_str = " ".join(str(p) for p in sv_paths)
        top_arg = f"-top {toplevel}" if toplevel else "-auto-top"
        script = f"read_verilog -sv {files_str}; synth_xilinx {top_arg}; tee -q -o {stat_json} stat -json"
        try:
            proc = subprocess.run(
                ["yosys", "-q", "-p", script],
                capture_output=True,
                text=True,
                timeout=90,
            )
        except subprocess.TimeoutExpired:
            return {"synth_ok": False, "luts": None, "ffs": None, "synth_error": "Yosys timed out after 90s"}
        except FileNotFoundError:
            return {"synth_ok": False, "luts": None, "ffs": None, "synth_error": "yosys not found"}

        if proc.returncode != 0 or not stat_json.exists():
            err = (proc.stderr or proc.stdout or "Yosys synthesis failed").strip()
            return {"synth_ok": False, "luts": None, "ffs": None, "synth_error": err[-400:]}

        try:
            data = json.loads(stat_json.read_text(encoding="utf-8"))
            design = data.get("design", {})
            cells = design.get("num_cells_by_type", {})
            luts = sum(v for k, v in cells.items() if re.match(r"^LUT[1-6]$", k))
            ffs = sum(v for k, v in cells.items() if re.match(r"^FD[A-Z0-9_]*$", k))
            return {
                "synth_ok": True,
                "luts": luts,
                "ffs": ffs,
                "cells_by_type": cells,
                "synth_error": None,
            }
        except Exception as exc:
            return {"synth_ok": False, "luts": None, "ffs": None, "synth_error": str(exc)[:300]}


def save_progress(results_by_pid: dict, t_start: float) -> None:
    prob_order = {p: i for i, (p, _) in enumerate(SELECTED_PROBLEMS)}
    ordered = [results_by_pid[p] for p, _ in SELECTED_PROBLEMS if p in results_by_pid]
    ordered.sort(key=lambda r: prob_order[r["problem"]])

    passed = sum(1 for r in ordered if r["status"] == "pass")
    comp_err = sum(1 for r in ordered if r["failure_type"] == "compile_error")
    test_fail = sum(1 for r in ordered if r["failure_type"] == "test_failure")
    timeouts = sum(1 for r in ordered if r["failure_type"] == "timeout")
    api_err = sum(1 for r in ordered if r["failure_type"] == "api_error")
    avg_time = round(sum(r["total_time_seconds"] for r in ordered) / len(ordered), 2) if ordered else 0.0

    synth_ok = [r["yosys"] for r in ordered if r["status"] == "pass" and r["yosys"] and r["yosys"].get("synth_ok")]
    avg_luts = round(sum(y["luts"] for y in synth_ok) / len(synth_ok), 1) if synth_ok else None
    avg_ffs = round(sum(y["ffs"] for y in synth_ok) / len(synth_ok), 1) if synth_ok else None

    payload = {
        "metadata": {
            "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "baseline_name": "Neon with retries, no tools",
            "model": MODEL,
            "initial_rounds": 1,
            "review_rounds": NUM_REVIEW_ROUNDS,
            "total_rounds_per_problem": 1 + NUM_REVIEW_ROUNDS,
            "completed_problems": len(ordered),
            "total_problems": len(SELECTED_PROBLEMS),
            "total_wall_seconds": round(time.perf_counter() - t_start, 2),
        },
        "summary": {
            "passed": passed,
            "total": len(ordered),
            "pass_rate_pct": round(100.0 * passed / len(ordered), 1) if ordered else 0.0,
            "avg_luts": avg_luts,
            "avg_ffs": avg_ffs,
            "synthesized_count": len(synth_ok),
            "avg_time_seconds": avg_time,
            "compile_errors": comp_err,
            "test_failures": test_fail,
            "timeouts": timeouts,
            "api_errors": api_err,
        },
        "results": ordered,
    }
    with file_lock:
        tmp = RESULTS_FILE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        tmp.replace(RESULTS_FILE)


def run_problem(api_key: str, item: dict, domain: str, results_by_pid: dict, t_start: float) -> dict:
    pid = item["id"]
    diff = item["categories"][1] if len(item["categories"]) > 1 else "unknown"
    spec_prompt = item["input"]["prompt"].strip()
    client = get_client(api_key)
    save_root = GENERATED_DIR / pid
    save_root.mkdir(parents=True, exist_ok=True)

    round_times = []
    current_code = ""
    api_error = None

    # Round 1: Initial design
    t0 = time.perf_counter()
    try:
        resp = client.models.generate_content(
            model=MODEL,
            contents=spec_prompt,
            config=types.GenerateContentConfig(system_instruction=DESIGN_SYSTEM),
        )
        r1_time = round(time.perf_counter() - t0, 3)
        round_times.append(r1_time)
        current_code = extract_verilog(resp.text or "")
        (save_root / "round_1.sv").write_text(current_code + "\n", encoding="utf-8")
    except Exception as exc:
        r1_time = round(time.perf_counter() - t0, 3)
        round_times.append(r1_time)
        api_error = f"Round 1 API error: {exc}"

    # Rounds 2..4: Self-review without tools
    if not api_error:
        for rev in range(1, NUM_REVIEW_ROUNDS + 1):
            review_prompt = (
                f"### Specification\n{spec_prompt}\n\n"
                f"### Your Current RTL Design\n```systemverilog\n{current_code}\n```\n\n"
                f"Review your design against the spec and fix any bugs."
            )
            tr = time.perf_counter()
            try:
                resp = client.models.generate_content(
                    model=MODEL,
                    contents=review_prompt,
                    config=types.GenerateContentConfig(system_instruction=REVIEW_SYSTEM),
                )
                dt = round(time.perf_counter() - tr, 3)
                round_times.append(dt)
                new_code = extract_verilog(resp.text or "")
                if new_code:
                    current_code = new_code
                (save_root / f"round_{rev + 1}.sv").write_text(current_code + "\n", encoding="utf-8")
            except Exception as exc:
                dt = round(time.perf_counter() - tr, 3)
                round_times.append(dt)
                api_error = f"Review round {rev} API error: {exc}"
                break

    total_time = round(sum(round_times), 3)

    if api_error and not current_code:
        rec = {
            "problem": pid,
            "domain": domain,
            "difficulty": diff,
            "status": "fail",
            "failure_type": "api_error",
            "total_time_seconds": total_time,
            "round_times_seconds": round_times,
            "error_message": api_error[:500],
            "yosys": None,
        }
    else:
        ev, saved_paths, toplevel = run_cvdp_harness(item, current_code, save_root)
        yosys_info = synthesize_yosys_xilinx(saved_paths, toplevel) if ev["status"] == "pass" else None
        rec = {
            "problem": pid,
            "domain": domain,
            "difficulty": diff,
            "status": ev["status"],
            "failure_type": ev["failure_type"],
            "total_time_seconds": total_time,
            "round_times_seconds": round_times,
            "api_warning": api_error[:300] if api_error else None,
            "error_message": ev["error_message"],
            "yosys": yosys_info,
        }

    with file_lock:
        results_by_pid[pid] = rec
        done_cnt = len(results_by_pid)
    save_progress(results_by_pid, t_start)

    if rec["status"] == "pass":
        y = rec["yosys"]
        tag = f"PASS (LUT={y['luts']}, FF={y['ffs']})" if (y and y.get("synth_ok")) else "PASS (yosys err)"
    else:
        tag = f"FAIL ({rec['failure_type']})"

    with print_lock:
        print(f"[{done_cnt:2d}/{len(SELECTED_PROBLEMS)}] {pid:48s} | {tag:26s} | {total_time:6.1f}s", flush=True)
    return rec


def main() -> None:
    load_dotenv(REPO_ROOT / ".env")
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY not found in .env")

    all_items = {
        obj["id"]: obj
        for obj in (json.loads(line) for line in DATASET_PATH.open(encoding="utf-8"))
    }

    print(
        f"Starting 'Neon with retries, no tools' baseline: "
        f"{len(SELECTED_PROBLEMS)} problems x (1 + {NUM_REVIEW_ROUNDS} rounds) with {MAX_WORKERS} workers\n",
        flush=True,
    )
    t_start = time.perf_counter()
    results_by_pid: dict = {}

    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = [
            executor.submit(run_problem, api_key, all_items[pid], domain, results_by_pid, t_start)
            for pid, domain in SELECTED_PROBLEMS
        ]
        for fut in concurrent.futures.as_completed(futures):
            fut.result()

    save_progress(results_by_pid, t_start)
    data = json.loads(RESULTS_FILE.read_text(encoding="utf-8"))
    s = data["summary"]
    print(
        f"\nDone in {data['metadata']['total_wall_seconds']:.1f}s! "
        f"Pass: {s['passed']}/{s['total']} ({s['pass_rate_pct']:.1f}%), "
        f"Avg LUTs: {s['avg_luts']}, Avg FFs: {s['avg_ffs']}, Avg Time: {s['avg_time_seconds']:.1f}s"
    )


if __name__ == "__main__":
    main()
