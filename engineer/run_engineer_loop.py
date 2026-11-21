"""Engineer Loop Evaluation on the 20 CVDP cid003 problems.

STRICT ANTI-CHEAT RULE:
During steps 1-4 (design, independent testbench, fix loop, area optimization),
neither model EVER sees CVDP's hidden tests, harness files, or grading results.
CVDP's hidden harness is executed ONLY in step 5 (final grading) on the
pre-optimization and post-optimization designs.

Reuses the dataset and 20 problems from pilot_cvdp/ (read-only).
Logs every round to engineer/results.json.
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
from typing import Any, Dict, List, Optional, Tuple

from dotenv import load_dotenv
from google import genai

ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parent
PILOT_DIR = REPO_ROOT / "pilot_cvdp"
DATASET_PATH = PILOT_DIR / "cvdp_benchmark" / "cvdp_v1.1.0_nonagentic_code_generation_no_commercial.jsonl"
BASELINE_RESULTS_PATH = PILOT_DIR / "results.json"
GENERATED_DIR = ROOT / "generated"
RESULTS_FILE = ROOT / "results.json"
PYTEST_BIN = str((REPO_ROOT / ".venv" / "bin" / "pytest").resolve())

# Model IDs
DESIGN_MODEL = "gemini-4-neon"
TB_MODEL = "gemini-4-hydrogen"
MAX_FIX_ROUNDS = 4
MAX_WORKERS = 6

# Exact same 20 problems from pilot_cvdp/run_cvdp_pilot.py
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

TB_SYSTEM = (
    "You are an expert hardware verification engineer writing an independent self-checking Verilog testbench (`module tb;`). "
    "You are given ONLY the hardware specification (not the RTL implementation). "
    "Write a clean, thorough, self-checking testbench that compiles with `iverilog -g2012` and runs in `vvp`:\n"
    "1. Instantiate the DUT with the EXACT module name, parameters, and port names/widths from the spec.\n"
    "2. Do NOT define the DUT module itself inside the testbench.\n"
    "3. Avoid unsupported SystemVerilog features in Icarus Verilog (no `assert property`, no classes, no randomize, no queues, no `uvm`). Stick to clean Verilog-2005 / basic SV-2012.\n"
    "4. Test reset behavior, normal operation, edge cases, and corner cases thoroughly.\n"
    "5. Keep an `integer errors = 0;` counter; on any mismatch print `$display(\"FAIL: <clear reason with expected vs got>\"); errors = errors + 1;`.\n"
    "6. At the end: if `errors == 0` print `$display(\"PASS\");` else `$display(\"FAIL: %0d errors\", errors);`, and ALWAYS call `$finish;` within a few thousand cycles.\n"
    "Return ONLY the testbench inside a single ```systemverilog ... ``` code block."
)

FIX_SYSTEM = (
    "You are an expert Verilog/SystemVerilog hardware design engineer fixing a bug in your RTL module. "
    "You are given the original specification, your current RTL code, and the Icarus Verilog compile/simulation error output. "
    "Fix the RTL so it adheres strictly to the specification and passes simulation. "
    "Keep it cleanly synthesizable in Yosys (`read_verilog -sv`) and compilable in `iverilog -g2012`. "
    "Return ONLY the complete corrected RTL inside a single ```systemverilog ... ``` code block (no testbench, no explanations)."
)

OPT_SYSTEM = (
    "You are an expert FPGA RTL optimization engineer targeting Xilinx 7-series (Yosys `synth_xilinx`). "
    "You are given the original specification, a functionally working RTL module, and its current LUT and Flip-Flop counts. "
    "Rewrite/optimize the RTL to use FEWER LUTs and FEWER Flip-Flops (smaller chip area) while keeping 100% EXACT identical "
    "module name, parameters, ports, latency, reset behavior, and functional behavior per the specification. "
    "Techniques: remove redundant registers/state bits, share arithmetic/adders/comparators, simplify combinational logic, "
    "avoid unnecessary wide muxes or unused bit widths, use compact state encodings. "
    "Return ONLY the complete optimized RTL inside a single ```systemverilog ... ``` code block (no testbench, no explanations)."
)

print_lock = threading.Lock()
file_lock = threading.Lock()
thread_local = threading.local()


def get_client(api_key: str) -> genai.Client:
    if not hasattr(thread_local, "client"):
        thread_local.client = genai.Client(api_key=api_key)
    return thread_local.client


def call_model(api_key: str, model: str, system_instruction: str, prompt: str) -> str:
    client = get_client(api_key)
    interaction = client.interactions.create(
        model=model,
        system_instruction=system_instruction,
        input=prompt,
        timeout=180.0,
    )
    return interaction.output_text or ""


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


def infer_top_module_name(sv_code: str) -> str:
    names = re.findall(r"\bmodule\s+([a-zA-Z_][a-zA-Z0-9_$]*)", sv_code)
    for n in reversed(names):
        if n.lower() != "tb":
            return n
    return names[0] if names else ""


def run_hydrogen_sim(
    sv_code: str,
    tb_code: str,
    input_context: Dict[str, str],
    target_rel: str,
) -> Dict[str, Any]:
    """Compile and simulate Neon's RTL with Hydrogen's independent testbench."""
    t0 = time.perf_counter()
    with tempfile.TemporaryDirectory(prefix="eng_sim_") as tmpdir:
        d = Path(tmpdir)
        rtl_files: List[str] = []

        for rel, content in (input_context or {}).items():
            if rel.endswith((".v", ".sv", ".vh", ".svh")):
                p = d / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(content, encoding="utf-8")
                if rel.endswith((".v", ".sv")) and rel != target_rel:
                    rtl_files.append(str(p))

        design_path = d / target_rel
        design_path.parent.mkdir(parents=True, exist_ok=True)
        design_path.write_text(sv_code + "\n", encoding="utf-8")
        rtl_files.append(str(design_path))

        tb_path = d / "tb_hydrogen.sv"
        tb_path.write_text(tb_code + "\n", encoding="utf-8")
        vvp_path = d / "sim.vvp"

        inc_dirs = sorted({str(Path(f).parent) for f in rtl_files} | {str(d)})
        inc_flags = []
        for inc in inc_dirs:
            inc_flags.extend(["-I", inc])

        try:
            comp = subprocess.run(
                ["iverilog", "-g2012", *inc_flags, "-o", str(vvp_path), *rtl_files, str(tb_path)],
                capture_output=True,
                text=True,
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            return {
                "passed": False,
                "compile_ok": False,
                "tb_compile_error": False,
                "stdout": "",
                "stderr": "iverilog compilation timed out after 15s.",
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }

        if comp.returncode != 0:
            err = (comp.stderr or comp.stdout).strip()
            tb_only_err = ("tb_hydrogen.sv" in err) and (Path(target_rel).name not in err)
            return {
                "passed": False,
                "compile_ok": False,
                "tb_compile_error": tb_only_err,
                "stdout": comp.stdout.strip(),
                "stderr": err[:2000],
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }

        try:
            sim = subprocess.run(
                ["vvp", str(vvp_path)],
                capture_output=True,
                text=True,
                timeout=12,
            )
        except subprocess.TimeoutExpired:
            return {
                "passed": False,
                "compile_ok": True,
                "tb_compile_error": False,
                "stdout": "",
                "stderr": "Simulation timed out after 12s (infinite loop or missing $finish).",
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }

        stdout = sim.stdout.strip()
        stderr = sim.stderr.strip()
        combined = f"{stdout}\n{stderr}"
        has_fail = bool(re.search(r"\b(FAIL|ERROR)\b", combined, re.IGNORECASE))
        has_pass = bool(re.search(r"\bPASS\b", stdout, re.IGNORECASE))
        passed = (sim.returncode == 0) and (not has_fail) and has_pass

        return {
            "passed": passed,
            "compile_ok": True,
            "tb_compile_error": False,
            "stdout": stdout[:2000],
            "stderr": stderr[:1000],
            "duration_ms": round((time.perf_counter() - t0) * 1000),
        }


def synthesize_yosys_xilinx(
    sv_code: str,
    input_context: Dict[str, str],
    target_rel: str,
    toplevel: str = "",
) -> Dict[str, Any]:
    """Run Yosys synth_xilinx and return LUT and Flip-Flop counts."""
    with tempfile.TemporaryDirectory(prefix="eng_synth_") as tmpdir:
        d = Path(tmpdir)
        sv_paths: List[str] = []
        for rel, content in (input_context or {}).items():
            if rel.endswith((".v", ".sv", ".vh", ".svh")):
                p = d / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(content, encoding="utf-8")
                if rel.endswith((".v", ".sv")) and rel != target_rel:
                    sv_paths.append(str(p))

        design_path = d / target_rel
        design_path.parent.mkdir(parents=True, exist_ok=True)
        design_path.write_text(sv_code + "\n", encoding="utf-8")
        sv_paths.append(str(design_path))

        stat_json = d / "stat.json"
        top = toplevel or infer_top_module_name(sv_code)
        top_arg = f"-top {top}" if top else "-auto-top"
        files_str = " ".join(sv_paths)
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

        if proc.returncode != 0 or not stat_json.exists():
            err = (proc.stderr or proc.stdout or "Yosys synthesis failed").strip()
            return {"synth_ok": False, "luts": None, "ffs": None, "synth_error": err[-400:]}

        try:
            data = json.loads(stat_json.read_text(encoding="utf-8"))
            cells = data.get("design", {}).get("num_cells_by_type", {})
            luts = sum(v for k, v in cells.items() if re.match(r"^LUT[1-6]$", k))
            ffs = sum(v for k, v in cells.items() if re.match(r"^FD[A-Z0-9_]*$", k))
            return {
                "synth_ok": True,
                "luts": luts,
                "ffs": ffs,
                "luts_plus_ffs": luts + ffs,
                "cells_by_type": cells,
                "synth_error": None,
            }
        except Exception as exc:
            return {"synth_ok": False, "luts": None, "ffs": None, "synth_error": str(exc)[:300]}


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


def run_cvdp_hidden_grading(item: dict, sv_code: str) -> Tuple[Dict[str, Any], str]:
    """STEP 5 ONLY: Run CVDP's hidden cocotb/pytest tests for final grading."""
    out_files = list(item["output"]["context"].keys())
    target_rel = out_files[0]

    with tempfile.TemporaryDirectory(prefix="eng_grade_") as tmpdir:
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
                {"status": "fail", "failure_type": "timeout", "error_message": "Timed out after 60s"},
                toplevel,
            )

        combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
        if proc.returncode == 0:
            return ({"status": "pass", "failure_type": None, "error_message": None}, toplevel)

        err_lines = [
            ln for ln in combined.splitlines()
            if any(tok in ln for tok in ("error:", "ERROR", "FAIL", "AssertionError", "SyntaxError", "Sorry:", "CalledProcessError"))
        ]
        snippet = "\n".join(err_lines[:10]) if err_lines else combined[-600:]
        sim_started = ("TESTS=" in combined and "PASS=" in combined) or "running " in combined.lower()
        ftype = "test_failure" if sim_started else "compile_error"
        return (
            {"status": "fail", "failure_type": ftype, "error_message": snippet[:600].strip()},
            toplevel,
        )


def run_problem(api_key: str, item: dict, domain: str, idx: int, total: int) -> Dict[str, Any]:
    pid = item["id"]
    diff = item["categories"][1] if len(item["categories"]) > 1 else "unknown"
    spec_prompt = item["input"]["prompt"].strip()
    input_context = item["input"].get("context", {}) or {}
    target_rel = list(item["output"]["context"].keys())[0]

    t_problem = time.perf_counter()
    rounds_log: List[Dict[str, Any]] = []

    try:
        # --- STEP 1 & STEP 2 (in parallel): Neon writes design, Hydrogen writes independent TB ---
        t12 = time.perf_counter()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as sub:
            fut_design = sub.submit(call_model, api_key, DESIGN_MODEL, DESIGN_SYSTEM, spec_prompt)
            fut_tb = sub.submit(call_model, api_key, TB_MODEL, TB_SYSTEM, spec_prompt)
            raw_design = fut_design.result()
            raw_tb = fut_tb.result()
        step12_sec = round(time.perf_counter() - t12, 2)

        current_sv = extract_verilog(raw_design)
        tb_sv = extract_verilog(raw_tb)

        # --- STEP 3: Simulate with Hydrogen's TB; fix up to 4 rounds with Neon ---
        sim_res = run_hydrogen_sim(current_sv, tb_sv, input_context, target_rel)

        # If Hydrogen's own testbench has a syntax error (without seeing Neon's code), let Hydrogen fix its TB once
        tb_fixed = False
        if not sim_res["compile_ok"] and sim_res.get("tb_compile_error"):
            tb_fix_prompt = (
                f"Your Verilog testbench for this spec failed to compile in `iverilog -g2012`.\n\n"
                f"--- SPEC ---\n{spec_prompt}\n\n"
                f"--- YOUR TESTBENCH (tb_hydrogen.sv) ---\n{tb_sv}\n\n"
                f"--- COMPILER ERROR ---\n{sim_res['stderr']}\n\n"
                "Fix the syntax/compilation error in your testbench only."
            )
            tb_sv = extract_verilog(call_model(api_key, TB_MODEL, TB_SYSTEM, tb_fix_prompt))
            tb_fixed = True
            sim_res = run_hydrogen_sim(current_sv, tb_sv, input_context, target_rel)

        rounds_log.append(
            {
                "round": 0,
                "stage": "initial",
                "elapsed_seconds": step12_sec,
                "tb_syntax_fixed": tb_fixed,
                "hydrogen_passed": sim_res["passed"],
                "compile_ok": sim_res["compile_ok"],
                "error_snippet": (sim_res["stderr"] or sim_res["stdout"])[:500] if not sim_res["passed"] else None,
            }
        )

        fix_rounds_used = 0
        for r in range(1, MAX_FIX_ROUNDS + 1):
            if sim_res["passed"]:
                break
            fix_rounds_used = r
            tr = time.perf_counter()
            err_report = f"STDOUT:\n{sim_res['stdout'] or '(empty)'}\n\nSTDERR:\n{sim_res['stderr'] or '(empty)'}"
            fix_prompt = (
                f"--- ORIGINAL SPECIFICATION ---\n{spec_prompt}\n\n"
                f"--- CURRENT RTL ---\n{current_sv}\n\n"
                f"--- ICARUS VERILOG SIMULATION FAILURE (Round {r}) ---\n{err_report}\n\n"
                "Diagnose and fix the RTL so it strictly satisfies the specification."
            )
            current_sv = extract_verilog(call_model(api_key, DESIGN_MODEL, FIX_SYSTEM, fix_prompt))
            sim_res = run_hydrogen_sim(current_sv, tb_sv, input_context, target_rel)
            rounds_log.append(
                {
                    "round": r,
                    "stage": "fix",
                    "elapsed_seconds": round(time.perf_counter() - tr, 2),
                    "hydrogen_passed": sim_res["passed"],
                    "compile_ok": sim_res["compile_ok"],
                    "error_snippet": (sim_res["stderr"] or sim_res["stdout"])[:500] if not sim_res["passed"] else None,
                }
            )

        pre_opt_sv = current_sv
        hydrogen_passed_pre_opt = sim_res["passed"]

        # --- STEP 4: Area Optimization (only if passed Hydrogen's tests) ---
        pre_opt_synth = synthesize_yosys_xilinx(pre_opt_sv, input_context, target_rel)
        opt_info: Dict[str, Any] = {
            "attempted": False,
            "kept": False,
            "reason": "Skipped (did not pass Hydrogen tests)",
            "hydrogen_passed": None,
            "pre_luts": pre_opt_synth.get("luts"),
            "pre_ffs": pre_opt_synth.get("ffs"),
            "opt_luts": None,
            "opt_ffs": None,
            "elapsed_seconds": 0.0,
        }
        final_sv = pre_opt_sv

        if hydrogen_passed_pre_opt and pre_opt_synth.get("synth_ok"):
            opt_info["attempted"] = True
            t_opt = time.perf_counter()
            pre_total = pre_opt_synth["luts"] + pre_opt_synth["ffs"]
            opt_prompt = (
                f"--- ORIGINAL SPECIFICATION ---\n{spec_prompt}\n\n"
                f"--- WORKING RTL (Current Xilinx synth: {pre_opt_synth['luts']} LUTs, {pre_opt_synth['ffs']} FFs, total={pre_total}) ---\n"
                f"{pre_opt_sv}\n\n"
                "Optimize this RTL to use FEWER LUTs and Flip-Flops while preserving 100% exact functionality and port interface."
            )
            cand_sv = extract_verilog(call_model(api_key, DESIGN_MODEL, OPT_SYSTEM, opt_prompt))
            cand_sim = run_hydrogen_sim(cand_sv, tb_sv, input_context, target_rel)
            cand_synth = synthesize_yosys_xilinx(cand_sv, input_context, target_rel) if cand_sim["passed"] else {"synth_ok": False}

            opt_info["elapsed_seconds"] = round(time.perf_counter() - t_opt, 2)
            opt_info["hydrogen_passed"] = cand_sim["passed"]
            opt_info["opt_luts"] = cand_synth.get("luts")
            opt_info["opt_ffs"] = cand_synth.get("ffs")

            if cand_sim["passed"] and cand_synth.get("synth_ok"):
                cand_total = cand_synth["luts"] + cand_synth["ffs"]
                if cand_total < pre_total:
                    final_sv = cand_sv
                    opt_info["kept"] = True
                    opt_info["reason"] = f"Reduced LUT+FF from {pre_total} to {cand_total} ({pre_total - cand_total} saved)"
                else:
                    opt_info["reason"] = f"Rejected: not smaller ({cand_total} vs {pre_total})"
            elif not cand_sim["passed"]:
                opt_info["reason"] = "Rejected: failed Hydrogen tests"
            else:
                opt_info["reason"] = "Rejected: Yosys synthesis failed"

            rounds_log.append(
                {
                    "round": fix_rounds_used + 1,
                    "stage": "optimize",
                    "elapsed_seconds": opt_info["elapsed_seconds"],
                    "hydrogen_passed": cand_sim["passed"],
                    "kept": opt_info["kept"],
                    "reason": opt_info["reason"],
                }
            )

        # Save generated RTLs & Hydrogen TB for auditability
        prob_dir = GENERATED_DIR / pid
        prob_dir.mkdir(parents=True, exist_ok=True)
        (prob_dir / "tb_hydrogen.sv").write_text(tb_sv + "\n", encoding="utf-8")
        (prob_dir / "pre_opt.sv").write_text(pre_opt_sv + "\n", encoding="utf-8")
        (prob_dir / "final.sv").write_text(final_sv + "\n", encoding="utf-8")

        # --- STEP 5: FINAL GRADING WITH CVDP'S HIDDEN TESTS (ONLY NOW!) ---
        cvdp_pre, toplevel = run_cvdp_hidden_grading(item, pre_opt_sv)
        yosys_pre_graded = synthesize_yosys_xilinx(pre_opt_sv, input_context, target_rel, toplevel=toplevel)

        if opt_info["kept"]:
            cvdp_final, _ = run_cvdp_hidden_grading(item, final_sv)
            yosys_final_graded = synthesize_yosys_xilinx(final_sv, input_context, target_rel, toplevel=toplevel)
        else:
            cvdp_final = cvdp_pre
            yosys_final_graded = yosys_pre_graded

        total_sec = round(time.perf_counter() - t_problem, 2)
        rec = {
            "problem": pid,
            "domain": domain,
            "difficulty": diff,
            "elapsed_seconds": total_sec,
            "fix_rounds_used": fix_rounds_used,
            "hydrogen_passed_pre_opt": hydrogen_passed_pre_opt,
            "rounds": rounds_log,
            "optimization": opt_info,
            "cvdp_pre_opt": cvdp_pre,
            "yosys_pre_opt": {
                "synth_ok": yosys_pre_graded.get("synth_ok"),
                "luts": yosys_pre_graded.get("luts"),
                "ffs": yosys_pre_graded.get("ffs"),
            },
            "cvdp_final": cvdp_final,
            "yosys_final": {
                "synth_ok": yosys_final_graded.get("synth_ok"),
                "luts": yosys_final_graded.get("luts"),
                "ffs": yosys_final_graded.get("ffs"),
            },
        }

        tag_pre = "PASS" if cvdp_pre["status"] == "pass" else "FAIL"
        tag_fin = "PASS" if cvdp_final["status"] == "pass" else "FAIL"
        opt_tag = f"OPT_KEPT({opt_info['pre_luts']}+{opt_info['pre_ffs']}->{opt_info['opt_luts']}+{opt_info['opt_ffs']})" if opt_info["kept"] else "no-opt"
        with print_lock:
            print(
                f"[{idx:2d}/{total}] {pid:46s} | H_tb={'OK' if hydrogen_passed_pre_opt else 'NO'} (r={fix_rounds_used}) "
                f"| CVDP pre={tag_pre} fin={tag_fin} | {opt_tag:22s} | {total_sec:5.1f}s",
                flush=True,
            )
        return rec

    except Exception as exc:
        total_sec = round(time.perf_counter() - t_problem, 2)
        with print_lock:
            print(f"[{idx:2d}/{total}] {pid:46s} | EXCEPTION: {exc}", flush=True)
        return {
            "problem": pid,
            "domain": domain,
            "difficulty": diff,
            "elapsed_seconds": total_sec,
            "error": str(exc)[:500],
            "fix_rounds_used": 0,
            "hydrogen_passed_pre_opt": False,
            "rounds": rounds_log,
            "optimization": {"attempted": False, "kept": False, "reason": f"Exception: {exc}"},
            "cvdp_pre_opt": {"status": "fail", "failure_type": "exception", "error_message": str(exc)[:400]},
            "yosys_pre_opt": {"synth_ok": False, "luts": None, "ffs": None},
            "cvdp_final": {"status": "fail", "failure_type": "exception", "error_message": str(exc)[:400]},
            "yosys_final": {"synth_ok": False, "luts": None, "ffs": None},
        }


def compute_summary(results: List[Dict[str, Any]], baseline_data: Dict[str, Any]) -> Dict[str, Any]:
    # Baseline (single Neon call from pilot_cvdp/results.json)
    base_neon = [r for r in baseline_data.get("results", []) if r.get("model") == DESIGN_MODEL]
    base_by_prob = {r["problem"]: r for r in base_neon}
    base_sum = baseline_data.get("summary", {}).get(DESIGN_MODEL, {})

    def _stats(key_cvdp: str, key_yosys: str) -> Dict[str, Any]:
        n = len(results)
        passed = sum(1 for r in results if (r.get(key_cvdp) or {}).get("status") == "pass")
        synth_ok = [
            r[key_yosys]
            for r in results
            if (r.get(key_cvdp) or {}).get("status") == "pass"
            and (r.get(key_yosys) or {}).get("synth_ok")
        ]
        avg_luts = round(sum(y["luts"] for y in synth_ok) / len(synth_ok), 1) if synth_ok else None
        avg_ffs = round(sum(y["ffs"] for y in synth_ok) / len(synth_ok), 1) if synth_ok else None
        return {
            "passed": passed,
            "total": n,
            "pass_rate_pct": round(100.0 * passed / n, 1) if n else 0.0,
            "avg_luts": avg_luts,
            "avg_ffs": avg_ffs,
            "synthesized_count": len(synth_ok),
        }

    fixed_vs_baseline = []
    still_failed = []
    opt_broke_cvdp = []
    opt_improved = []

    for r in results:
        pid = r["problem"]
        base_pass = (base_by_prob.get(pid) or {}).get("status") == "pass"
        pre_pass = (r.get("cvdp_pre_opt") or {}).get("status") == "pass"
        fin_pass = (r.get("cvdp_final") or {}).get("status") == "pass"

        if not base_pass and fin_pass:
            fixed_vs_baseline.append(pid)
        if not fin_pass:
            still_failed.append(pid)
        if pre_pass and not fin_pass:
            opt_broke_cvdp.append(pid)
        if (r.get("optimization") or {}).get("kept") and fin_pass:
            opt_improved.append(
                {
                    "problem": pid,
                    "pre_luts": r["yosys_pre_opt"]["luts"],
                    "pre_ffs": r["yosys_pre_opt"]["ffs"],
                    "final_luts": r["yosys_final"]["luts"],
                    "final_ffs": r["yosys_final"]["ffs"],
                }
            )

    avg_time = round(sum(r.get("elapsed_seconds", 0) for r in results) / len(results), 2) if results else 0.0

    return {
        "baseline_single_neon": {
            "passed": base_sum.get("passed"),
            "total": base_sum.get("total"),
            "pass_rate_pct": base_sum.get("pass_rate_pct"),
            "avg_luts": base_sum.get("avg_luts"),
            "avg_ffs": base_sum.get("avg_ffs"),
            "avg_time_seconds": base_sum.get("avg_time_seconds"),
        },
        "loop_before_optimization": _stats("cvdp_pre_opt", "yosys_pre_opt"),
        "loop_after_optimization": _stats("cvdp_final", "yosys_final"),
        "avg_time_per_problem_seconds": avg_time,
        "fixed_by_loop_vs_baseline": fixed_vs_baseline,
        "still_failed": still_failed,
        "optimization_broke_cvdp": opt_broke_cvdp,
        "optimization_kept_and_passed": opt_improved,
    }


def save_results(results: List[Dict[str, Any]], baseline_data: Dict[str, Any], wall_sec: float) -> None:
    prob_order = {p: i for i, (p, _) in enumerate(SELECTED_PROBLEMS)}
    ordered = sorted(results, key=lambda r: prob_order.get(r["problem"], 999))
    summary = compute_summary(ordered, baseline_data)
    payload = {
        "metadata": {
            "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "design_model": DESIGN_MODEL,
            "testbench_model": TB_MODEL,
            "max_fix_rounds": MAX_FIX_ROUNDS,
            "completed_problems": len(ordered),
            "total_problems": len(SELECTED_PROBLEMS),
            "total_wall_seconds": round(wall_sec, 2),
        },
        "summary": summary,
        "results": ordered,
    }
    with file_lock:
        RESULTS_FILE.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    load_dotenv(REPO_ROOT / ".env")
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY not found in .env")

    all_items = {
        obj["id"]: obj
        for obj in (json.loads(line) for line in DATASET_PATH.open(encoding="utf-8"))
    }
    baseline_data = json.loads(BASELINE_RESULTS_PATH.read_text(encoding="utf-8"))

    print(
        f"Starting Engineer Loop on {len(SELECTED_PROBLEMS)} CVDP problems "
        f"(design={DESIGN_MODEL}, tb={TB_MODEL}, max_fix={MAX_FIX_ROUNDS}, workers={MAX_WORKERS})\n",
        flush=True,
    )
    t0 = time.perf_counter()
    results: List[Dict[str, Any]] = []
    done_ids = set()
    if RESULTS_FILE.exists():
        try:
            prev = json.loads(RESULTS_FILE.read_text(encoding="utf-8"))
            for r in prev.get("results", []):
                if r.get("problem") and not r.get("error"):
                    results.append(r)
                    done_ids.add(r["problem"])
            if done_ids:
                print(f"Resuming: loaded {len(done_ids)} completed problem(s) from {RESULTS_FILE}\n", flush=True)
        except Exception:
            pass

    remaining = [
        (idx, pid, domain)
        for idx, (pid, domain) in enumerate(SELECTED_PROBLEMS, start=1)
        if pid not in done_ids
    ]

    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = [
            executor.submit(run_problem, api_key, all_items[pid], domain, idx, len(SELECTED_PROBLEMS))
            for idx, pid, domain in remaining
        ]
        for fut in concurrent.futures.as_completed(futures):
            results.append(fut.result())
            save_results(results, baseline_data, time.perf_counter() - t0)

    wall = time.perf_counter() - t0
    save_results(results, baseline_data, wall)
    final_data = json.loads(RESULTS_FILE.read_text(encoding="utf-8"))
    s = final_data["summary"]

    print(f"\nFinished {len(results)}/{len(SELECTED_PROBLEMS)} problems in {wall:.1f}s!\n")
    print(f"{'System':<30} | {'Pass Rate':<15} | {'Avg LUTs':<9} | {'Avg FFs':<9}")
    print("-" * 72)
    for label, key in [
        ("Baseline (single Neon call)", "baseline_single_neon"),
        ("Engineer Loop (before opt)", "loop_before_optimization"),
        ("Engineer Loop (after opt)", "loop_after_optimization"),
    ]:
        row = s[key]
        pr = f"{row['passed']}/{row['total']} ({row['pass_rate_pct']:.1f}%)"
        luts = f"{row['avg_luts']:.1f}" if row["avg_luts"] is not None else "N/A"
        ffs = f"{row['avg_ffs']:.1f}" if row["avg_ffs"] is not None else "N/A"
        print(f"{label:<30} | {pr:<15} | {luts:<9} | {ffs:<9}")
    print(f"\nAverage time per problem: {s['avg_time_per_problem_seconds']:.1f}s")
    print("Fixed vs baseline:", s["fixed_by_loop_vs_baseline"])
    print("Still failed:", s["still_failed"])
    print("Optimization broke CVDP:", s["optimization_broke_cvdp"])


if __name__ == "__main__":
    main()
