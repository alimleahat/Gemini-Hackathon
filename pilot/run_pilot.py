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
DATASET_DIR = ROOT / "verilog-eval" / "dataset_spec-to-rtl"
GENERATED_DIR = ROOT / "generated"
RESULTS_FILE = ROOT / "pilot_results.json"

MODELS = [
    "gemini-4-hydrogen",
    "gemini-4-neon",
    "gemini-4-carbon",
]

PROBLEMS = [
    # 10 Combinational Logic problems
    ("Prob017_mux2to1v", "combinational"),
    ("Prob021_mux256to1v", "combinational"),
    ("Prob030_popcount255", "combinational"),
    ("Prob055_conditional", "combinational"),
    ("Prob069_truthtable1", "combinational"),
    ("Prob071_always_casez", "combinational"),
    ("Prob092_gatesv100", "combinational"),
    ("Prob097_mux9to1v", "combinational"),
    ("Prob113_2012_q1g", "combinational"),
    ("Prob123_bugs_addsubz", "combinational"),
    # 10 Sequential Logic problems (counters, shift registers, FSMs, timers)
    ("Prob035_count1to10", "sequential"),
    ("Prob068_countbcd", "sequential"),
    ("Prob075_counter_2bc", "sequential"),
    ("Prob082_lfsr32", "sequential"),
    ("Prob108_rule90", "sequential"),
    ("Prob119_fsm3", "sequential"),
    ("Prob137_fsm_serial", "sequential"),
    ("Prob141_count_clock", "sequential"),
    ("Prob155_lemmings4", "sequential"),
    ("Prob156_review2015_fancytimer", "sequential"),
]

SYSTEM_INSTRUCTION = (
    "You are an expert Verilog hardware design engineer. "
    "Implement the requested module `TopModule` in clean, synthesizable Verilog/SystemVerilog "
    "compatible with Icarus Verilog (`iverilog -g2012`). "
    "Return ONLY the Verilog module code inside a single ```verilog ... ``` code block. "
    "Do not include a testbench, do not include `timescale, and do not include explanations."
)

print_lock = threading.Lock()
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
            if "module TopModule" in b:
                return b.strip()
        return blocks[-1].strip()
    m = re.search(r"(module\s+TopModule\b.*?endmodule)", text, flags=re.DOTALL)
    if m:
        return m.group(1).strip()
    return text.strip()


def evaluate_verilog(problem: str, sv_code: str, save_path: Path) -> dict:
    save_path.parent.mkdir(parents=True, exist_ok=True)
    save_path.write_text(sv_code + "\n", encoding="utf-8")

    ref_path = DATASET_DIR / f"{problem}_ref.sv"
    test_src = (DATASET_DIR / f"{problem}_test.sv").read_text(encoding="utf-8")
    # Remove unused $dumpfile/$dumpvars block to avoid Icarus Verilog 13.0 forward-ref error on tb_mismatch
    test_fixed = re.sub(
        r"initial\s+begin\s*\$dumpfile\([^;]+;\s*\$dumpvars\([^;]+;\s*end",
        "",
        test_src,
        flags=re.DOTALL,
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        test_path = tmp / f"{problem}_test.sv"
        vvp_path = tmp / f"{problem}.vvp"
        test_path.write_text(test_fixed, encoding="utf-8")

        compile_cmd = [
            "iverilog",
            "-Wall",
            "-Winfloop",
            "-Wno-timescale",
            "-g2012",
            "-s",
            "tb",
            "-o",
            str(vvp_path),
            str(save_path),
            str(test_path),
            str(ref_path),
        ]
        comp = subprocess.run(compile_cmd, capture_output=True, text=True, timeout=30)
        if comp.returncode != 0 or not vvp_path.exists():
            err_msg = (comp.stderr or comp.stdout or "Compilation failed").strip()
            return {
                "status": "fail",
                "failure_type": "compile_error",
                "mismatches": None,
                "total_samples": None,
                "error_message": err_msg[:500],
            }

        try:
            sim = subprocess.run(
                ["vvp", str(vvp_path)],
                capture_output=True,
                text=True,
                timeout=30,
            )
        except subprocess.TimeoutExpired:
            return {
                "status": "fail",
                "failure_type": "wrong_behaviour",
                "mismatches": None,
                "total_samples": None,
                "error_message": "Simulation timed out after 30s",
            }

        out = (sim.stdout or "") + "\n" + (sim.stderr or "")
        m = re.search(r"Mismatches:\s*(\d+)\s+in\s+(\d+)\s+samples", out)
        if m:
            mismatches = int(m.group(1))
            total_samples = int(m.group(2))
            if mismatches == 0:
                return {
                    "status": "pass",
                    "failure_type": None,
                    "mismatches": 0,
                    "total_samples": total_samples,
                    "error_message": None,
                }
            return {
                "status": "fail",
                "failure_type": "wrong_behaviour",
                "mismatches": mismatches,
                "total_samples": total_samples,
                "error_message": f"Mismatches: {mismatches} in {total_samples} samples",
            }

        return {
            "status": "fail",
            "failure_type": "wrong_behaviour",
            "mismatches": None,
            "total_samples": None,
            "error_message": out.strip()[:500] or "No mismatch summary in simulation output",
        }


def run_one(api_key: str, model: str, problem: str, category: str, idx: int, total: int) -> dict:
    prompt_text = (DATASET_DIR / f"{problem}_prompt.txt").read_text(encoding="utf-8").strip()
    client = get_client(api_key)

    t0 = time.perf_counter()
    try:
        response = client.models.generate_content(
            model=model,
            contents=prompt_text,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_INSTRUCTION,
            ),
        )
        elapsed = round(time.perf_counter() - t0, 3)
        raw_text = response.text or ""
    except Exception as exc:
        elapsed = round(time.perf_counter() - t0, 3)
        rec = {
            "problem": problem,
            "category": category,
            "model": model,
            "status": "fail",
            "failure_type": "api_error",
            "elapsed_seconds": elapsed,
            "mismatches": None,
            "total_samples": None,
            "error_message": str(exc)[:500],
        }
        with print_lock:
            print(f"[{idx:2d}/{total}] {model:18s} | {problem:30s} | API_ERROR ({elapsed:.2f}s): {exc}", flush=True)
        return rec

    sv_code = extract_verilog(raw_text)
    save_path = GENERATED_DIR / model / f"{problem}.sv"
    ev = evaluate_verilog(problem, sv_code, save_path)

    rec = {
        "problem": problem,
        "category": category,
        "model": model,
        "status": ev["status"],
        "failure_type": ev["failure_type"],
        "elapsed_seconds": elapsed,
        "mismatches": ev["mismatches"],
        "total_samples": ev["total_samples"],
        "error_message": ev["error_message"],
    }
    tag = "PASS" if ev["status"] == "pass" else f"FAIL ({ev['failure_type']})"
    with print_lock:
        print(f"[{idx:2d}/{total}] {model:18s} | {problem:30s} | {tag:24s} | {elapsed:6.2f}s", flush=True)
    return rec


def main() -> None:
    load_dotenv(ROOT.parent / ".env")
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY not found in .env")

    tasks = []
    idx = 0
    total = len(MODELS) * len(PROBLEMS)
    for problem, category in PROBLEMS:
        for model in MODELS:
            idx += 1
            tasks.append((model, problem, category, idx))

    print(f"Starting pilot evaluation: {len(PROBLEMS)} problems x {len(MODELS)} models = {total} calls\n", flush=True)
    t_start = time.perf_counter()

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        futures = [
            executor.submit(run_one, api_key, model, problem, category, i, total)
            for model, problem, category, i in tasks
        ]
        for fut in concurrent.futures.as_completed(futures):
            results.append(fut.result())

    # Sort deterministically by problem order then model order
    prob_order = {p: i for i, (p, _) in enumerate(PROBLEMS)}
    model_order = {m: i for i, m in enumerate(MODELS)}
    results.sort(key=lambda r: (model_order[r["model"]], prob_order[r["problem"]]))

    summary = {}
    for model in MODELS:
        m_res = [r for r in results if r["model"] == model]
        passed = sum(1 for r in m_res if r["status"] == "pass")
        comp_err = sum(1 for r in m_res if r["failure_type"] == "compile_error")
        wrong_beh = sum(1 for r in m_res if r["failure_type"] == "wrong_behaviour")
        api_err = sum(1 for r in m_res if r["failure_type"] == "api_error")
        avg_time = round(sum(r["elapsed_seconds"] for r in m_res) / len(m_res), 3)
        comb_pass = sum(1 for r in m_res if r["category"] == "combinational" and r["status"] == "pass")
        seq_pass = sum(1 for r in m_res if r["category"] == "sequential" and r["status"] == "pass")
        summary[model] = {
            "passed": passed,
            "total": len(m_res),
            "pass_rate_pct": round(100.0 * passed / len(m_res), 1),
            "combinational_passed": comb_pass,
            "sequential_passed": seq_pass,
            "avg_time_seconds": avg_time,
            "compile_errors": comp_err,
            "wrong_behaviour": wrong_beh,
            "api_errors": api_err,
        }

    total_wall = round(time.perf_counter() - t_start, 2)
    payload = {
        "metadata": {
            "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "benchmark": "NVlabs/verilog-eval (dataset_spec-to-rtl)",
            "benchmark_license": "MIT License",
            "num_problems": len(PROBLEMS),
            "models": MODELS,
            "problems": [{"name": p, "category": c} for p, c in PROBLEMS],
            "total_wall_seconds": total_wall,
        },
        "summary": summary,
        "results": results,
    }

    RESULTS_FILE.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    print(f"\nDone in {total_wall:.1f}s! Results saved to {RESULTS_FILE}\n")
    print(f"{'Model':<20} | {'Pass Rate':<12} | {'Avg Time':<10} | {'Compile Err':<11} | {'Wrong Behav':<11} | {'API Err':<7}")
    print("-" * 85)
    for model in MODELS:
        s = summary[model]
        pr = f"{s['passed']}/{s['total']} ({s['pass_rate_pct']:.1f}%)"
        print(
            f"{model:<20} | {pr:<12} | {s['avg_time_seconds']:>7.2f}s   | "
            f"{s['compile_errors']:<11} | {s['wrong_behaviour']:<11} | {s['api_errors']:<7}"
        )


if __name__ == "__main__":
    main()
