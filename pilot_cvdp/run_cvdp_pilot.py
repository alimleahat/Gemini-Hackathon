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
DATASET_PATH = ROOT / "cvdp_benchmark" / "cvdp_v1.1.0_nonagentic_code_generation_no_commercial.jsonl"
GENERATED_DIR = ROOT / "generated"
RESULTS_FILE = ROOT / "results.json"
PYTEST_BIN = str((REPO_ROOT / ".venv" / "bin" / "pytest").resolve())

MODELS = [
    "gemini-4-hydrogen",
    "gemini-4-neon",
    "gemini-4-carbon",
]

# 20 diverse cid003 (Spec-to-RTL) problems across arithmetic, FSMs, memory, and protocols
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

SYSTEM_INSTRUCTION = (
    "You are an expert Verilog/SystemVerilog hardware design engineer. "
    "Implement the requested RTL module cleanly so that it compiles with Icarus Verilog (`iverilog -g2012`) "
    "and synthesizes cleanly with Yosys (`read_verilog -sv`). "
    "Return ONLY the complete Verilog/SystemVerilog source code inside a single ```systemverilog ... ``` code block. "
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
    # Check if cocotb actually started running tests
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

    saved_paths = []
    out_path = save_root / target_rel
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(sv_code + "\n", encoding="utf-8")
    saved_paths.append(out_path)

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
        # Extract concise error snippet
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


def run_one(api_key: str, model: str, item: dict, domain: str, idx: int, total: int) -> dict:
    pid = item["id"]
    diff = item["categories"][1] if len(item["categories"]) > 1 else "unknown"
    prompt_text = item["input"]["prompt"].strip()
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
            "problem": pid,
            "domain": domain,
            "difficulty": diff,
            "model": model,
            "status": "fail",
            "failure_type": "api_error",
            "elapsed_seconds": elapsed,
            "error_message": str(exc)[:500],
            "yosys": None,
        }
        with print_lock:
            print(f"[{idx:2d}/{total}] {model:18s} | {pid:46s} | API_ERROR ({elapsed:.2f}s)", flush=True)
        return rec

    sv_code = extract_verilog(raw_text)
    save_root = GENERATED_DIR / model / pid
    ev, saved_paths, toplevel = run_cvdp_harness(item, sv_code, save_root)

    yosys_info = None
    if ev["status"] == "pass":
        yosys_info = synthesize_yosys_xilinx(saved_paths, toplevel)

    rec = {
        "problem": pid,
        "domain": domain,
        "difficulty": diff,
        "model": model,
        "status": ev["status"],
        "failure_type": ev["failure_type"],
        "elapsed_seconds": elapsed,
        "error_message": ev["error_message"],
        "yosys": yosys_info,
    }

    if ev["status"] == "pass":
        if yosys_info and yosys_info.get("synth_ok"):
            tag = f"PASS (LUT={yosys_info['luts']}, FF={yosys_info['ffs']})"
        else:
            tag = "PASS (yosys err)"
    else:
        tag = f"FAIL ({ev['failure_type']})"

    with print_lock:
        print(f"[{idx:2d}/{total}] {model:18s} | {pid:46s} | {tag:26s} | {elapsed:6.2f}s", flush=True)
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

    tasks = []
    idx = 0
    total = len(SELECTED_PROBLEMS) * len(MODELS)
    for pid, domain in SELECTED_PROBLEMS:
        item = all_items[pid]
        for model in MODELS:
            idx += 1
            tasks.append((model, item, domain, idx))

    print(f"Starting CVDP pilot evaluation: {len(SELECTED_PROBLEMS)} problems x {len(MODELS)} models = {total} calls\n", flush=True)
    t_start = time.perf_counter()

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        futures = [
            executor.submit(run_one, api_key, model, item, domain, i, total)
            for model, item, domain, i in tasks
        ]
        for fut in concurrent.futures.as_completed(futures):
            results.append(fut.result())

    prob_order = {p: i for i, (p, _) in enumerate(SELECTED_PROBLEMS)}
    model_order = {m: i for i, m in enumerate(MODELS)}
    results.sort(key=lambda r: (model_order[r["model"]], prob_order[r["problem"]]))

    summary = {}
    for model in MODELS:
        m_res = [r for r in results if r["model"] == model]
        passed = sum(1 for r in m_res if r["status"] == "pass")
        comp_err = sum(1 for r in m_res if r["failure_type"] == "compile_error")
        test_fail = sum(1 for r in m_res if r["failure_type"] == "test_failure")
        timeouts = sum(1 for r in m_res if r["failure_type"] == "timeout")
        api_err = sum(1 for r in m_res if r["failure_type"] == "api_error")
        avg_time = round(sum(r["elapsed_seconds"] for r in m_res) / len(m_res), 3)

        synth_ok = [r["yosys"] for r in m_res if r["status"] == "pass" and r["yosys"] and r["yosys"].get("synth_ok")]
        avg_luts = round(sum(y["luts"] for y in synth_ok) / len(synth_ok), 1) if synth_ok else None
        avg_ffs = round(sum(y["ffs"] for y in synth_ok) / len(synth_ok), 1) if synth_ok else None

        summary[model] = {
            "passed": passed,
            "total": len(m_res),
            "pass_rate_pct": round(100.0 * passed / len(m_res), 1),
            "avg_time_seconds": avg_time,
            "compile_errors": comp_err,
            "test_failures": test_fail,
            "timeouts": timeouts,
            "api_errors": api_err,
            "yosys_synthesized": len(synth_ok),
            "avg_luts": avg_luts,
            "avg_ffs": avg_ffs,
        }

    total_wall = round(time.perf_counter() - t_start, 2)
    payload = {
        "metadata": {
            "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "benchmark": "NVlabs/cvdp_benchmark (cvdp_v1.1.0_nonagentic_code_generation_no_commercial.jsonl, cid003)",
            "code_license": "Apache License 2.0",
            "data_license": "CC BY 4.0 (non-code) & Apache License 2.0 (code), plus upstream third-party licenses in NOTICE",
            "reference_solutions_available": False,
            "reference_solutions_note": "NVIDIA intentionally excluded golden reference RTL solutions from the public Hugging Face CVDP dataset to mitigate data contamination.",
            "num_problems": len(SELECTED_PROBLEMS),
            "models": MODELS,
            "problems": [
                {
                    "id": pid,
                    "domain": domain,
                    "difficulty": all_items[pid]["categories"][1],
                }
                for pid, domain in SELECTED_PROBLEMS
            ],
            "total_wall_seconds": total_wall,
        },
        "summary": summary,
        "results": results,
    }

    RESULTS_FILE.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    print(f"\nDone in {total_wall:.1f}s! Results saved to {RESULTS_FILE}\n")
    print(f"{'Model':<18} | {'Pass Rate':<13} | {'Avg Time':<8} | {'Comp':<4} | {'Test':<4} | {'Tout':<4} | {'Avg LUTs':<8} | {'Avg FFs':<8}")
    print("-" * 92)
    for model in MODELS:
        s = summary[model]
        pr = f"{s['passed']}/{s['total']} ({s['pass_rate_pct']:.1f}%)"
        luts = f"{s['avg_luts']:.1f}" if s["avg_luts"] is not None else "N/A"
        ffs = f"{s['avg_ffs']:.1f}" if s["avg_ffs"] is not None else "N/A"
        print(
            f"{model:<18} | {pr:<13} | {s['avg_time_seconds']:>6.2f}s  | "
            f"{s['compile_errors']:<4} | {s['test_failures']:<4} | {s['timeouts']:<4} | {luts:<8} | {ffs:<8}"
        )


if __name__ == "__main__":
    main()
