"""Follow-up Evaluation for Engineer Loop:
1. Fair Area Comparison (intersection of problems passing CVDP in BOTH baseline
   and after-optimisation) + full Yosys DSP & BRAM audit for every design,
   flagging any case where logic shifted into DSP/BRAM instead of truly shrinking.
2. Yosys Formal Equivalence Gate (`equiv_make` / `equiv_simple` / `equiv_struct` /
   `equiv_induct` / `equiv_status -assert`) on the 15 problems that passed CVDP
   before optimisation (reusing existing `pre_opt.sv` and `tb_hydrogen.sv`).

STRICT ANTI-CHEAT RULE:
CVDP's hidden tests are NEVER seen or used during optimisation or equivalence
checking; they are run ONLY at final grading.
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

import sys
ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from run_engineer_loop import (
    BASELINE_RESULTS_PATH,
    DATASET_PATH,
    DESIGN_MODEL,
    GENERATED_DIR,
    RESULTS_FILE,
    SELECTED_PROBLEMS,
    extract_verilog,
    infer_top_module_name,
    run_cvdp_hidden_grading,
    run_hydrogen_sim,
)

PILOT_GEN_DIR = REPO_ROOT / "pilot_cvdp" / "generated" / DESIGN_MODEL
FOLLOWUP_RESULTS_FILE = ROOT / "followup_results.json"

EQUIV_OPT_SYSTEM = (
    "You are an expert FPGA RTL optimization engineer targeting Xilinx 7-series (Yosys `synth_xilinx`). "
    "You are given the original specification, a working RTL module (`pre_opt`), and its current Xilinx resource counts "
    "(LUTs, FFs, DSPs, BRAMs). "
    "Optimize the RTL to use FEWER LUTs and/or FEWER Flip-Flops while keeping 100% STRICT cycle-for-cycle I/O equivalence "
    "with `pre_opt` — your output will be formally verified against `pre_opt` using Yosys `equiv_make` + `equiv_induct`! "
    "IMPORTANT RULES:\n"
    "1. Preserve EXACT module name, parameters, port names/widths, reset behavior, latency, and every output on every cycle.\n"
    "2. Prefer optimizations that formal equivalence can prove cleanly: simplify boolean/combinational expressions, eliminate dead/redundant logic, "
    "share common subexpressions/adders/muxes, remove unused registers, tighten internal bit widths.\n"
    "3. Do NOT shift logic into DSP48 or Block RAM just to reduce LUT count — reduce real logic without increasing DSP or BRAM usage.\n"
    "Return ONLY the complete optimized RTL inside a single ```systemverilog ... ``` code block (no testbench, no explanations)."
)

print_lock = threading.Lock()
thread_local = threading.local()


def get_client(api_key: str) -> genai.Client:
    if not hasattr(thread_local, "client"):
        thread_local.client = genai.Client(api_key=api_key)
    return thread_local.client


def call_neon(api_key: str, prompt: str) -> str:
    client = get_client(api_key)
    inter = client.interactions.create(
        model=DESIGN_MODEL,
        system_instruction=EQUIV_OPT_SYSTEM,
        input=prompt,
        timeout=240.0,
    )
    return inter.output_text or ""


def classify_xilinx_resources(cells: Dict[str, int]) -> Dict[str, Any]:
    luts = sum(v for k, v in cells.items() if re.match(r"^LUT[1-6]$", k))
    ffs = sum(v for k, v in cells.items() if re.match(r"^FD[A-Z0-9_]*$", k))
    carries = sum(v for k, v in cells.items() if k.upper().startswith("CARRY"))
    dsps = sum(v for k, v in cells.items() if k.upper().startswith("DSP"))
    brams = sum(v for k, v in cells.items() if re.match(r"^RAMB", k.upper()))
    dist_rams = sum(v for k, v in cells.items() if re.match(r"^RAM(32|64|128|256)", k.upper()))
    return {
        "luts": luts,
        "ffs": ffs,
        "carries": carries,
        "dsps": dsps,
        "brams": brams,
        "dist_rams": dist_rams,
        "luts_plus_ffs": luts + ffs,
        "cells_by_type": cells,
    }


def synth_full_resources(
    sv_code: str,
    input_context: Dict[str, str],
    target_rel: str,
    toplevel: str = "",
) -> Dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="eng_res_") as tmpdir:
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
            return {"synth_ok": False, "error": "Yosys timed out"}

        if proc.returncode != 0 or not stat_json.exists():
            return {"synth_ok": False, "error": (proc.stderr or proc.stdout)[-300:].strip()}

        data = json.loads(stat_json.read_text(encoding="utf-8"))
        cells = data.get("design", {}).get("num_cells_by_type", {})
        res = classify_xilinx_resources(cells)
        res["synth_ok"] = True
        return res


def check_formal_equivalence(
    gold_sv: str,
    gate_sv: str,
    input_context: Dict[str, str],
    target_rel: str,
    toplevel: str = "",
) -> Dict[str, Any]:
    """Run Yosys formal equivalence checking (`equiv_make` + `equiv_simple` + `equiv_induct` + `equiv_status -assert`)."""
    t0 = time.perf_counter()
    top = toplevel or infer_top_module_name(gold_sv)
    if not top:
        return {"proven": False, "reason": "Could not infer top module name", "duration_ms": 0}

    with tempfile.TemporaryDirectory(prefix="eng_equiv_") as tmpdir:
        d = Path(tmpdir)
        gold_dir = d / "gold"
        gate_dir = d / "gate"
        gold_dir.mkdir()
        gate_dir.mkdir()

        def _write_set(base: Path, code: str) -> str:
            files = []
            for rel, content in (input_context or {}).items():
                if rel.endswith((".v", ".sv", ".vh", ".svh")):
                    p = base / rel
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text(content, encoding="utf-8")
                    if rel.endswith((".v", ".sv")) and rel != target_rel:
                        files.append(str(p))
            tp = base / target_rel
            tp.parent.mkdir(parents=True, exist_ok=True)
            tp.write_text(code + "\n", encoding="utf-8")
            files.append(str(tp))
            return " ".join(files)

        gold_files = _write_set(gold_dir, gold_sv)
        gate_files = _write_set(gate_dir, gate_sv)

        script = f"""
read_verilog -sv {gold_files}
prep -top {top}
flatten
memory -nomap
memory_map
opt -fast
async2sync
rename {top} gold
design -stash gold

read_verilog -sv {gate_files}
prep -top {top}
flatten
memory -nomap
memory_map
opt -fast
async2sync
rename {top} gate
design -stash gate

design -copy-from gold -as gold gold
design -copy-from gate -as gate gate
equiv_make gold gate equiv
prep -top equiv
opt_clean -purge
equiv_simple -undef
equiv_struct -icells
equiv_simple -undef
equiv_induct -undef -seq 5
equiv_status -assert
"""
        try:
            proc = subprocess.run(
                ["yosys", "-q", "-p", script],
                capture_output=True,
                text=True,
                timeout=60,
            )
        except subprocess.TimeoutExpired:
            return {
                "proven": False,
                "reason": "Yosys equivalence check timed out after 60s",
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }

        ms = round((time.perf_counter() - t0) * 1000)
        if proc.returncode == 0:
            return {"proven": True, "reason": "Proven formally equivalent (0 unproven $equiv cells)", "duration_ms": ms}

        msg = (proc.stderr or proc.stdout).strip()
        last_lines = [ln.strip() for ln in msg.splitlines() if ln.strip()][-2:]
        return {
            "proven": False,
            "reason": " | ".join(last_lines)[-260:] or "Equivalence could not be proven",
            "duration_ms": ms,
        }


def run_equiv_opt_for_problem(
    api_key: str,
    item: dict,
    eng_rec: dict,
    pre_res: dict,
    idx: int,
    total: int,
) -> Dict[str, Any]:
    pid = item["id"]
    spec_prompt = item["input"]["prompt"].strip()
    input_context = item["input"].get("context", {}) or {}
    target_rel = list(item["output"]["context"].keys())[0]

    prob_dir = GENERATED_DIR / pid
    pre_sv = (prob_dir / "pre_opt.sv").read_text(encoding="utf-8")
    tb_sv = (prob_dir / "tb_hydrogen.sv").read_text(encoding="utf-8")
    old_fin_sv = (prob_dir / "final.sv").read_text(encoding="utf-8")
    top = infer_top_module_name(pre_sv)

    t0 = time.perf_counter()

    # 1. Check existing final.sv against the formal equivalence gate (if it differed from pre_opt)
    existing_opt_kept = bool((eng_rec.get("optimization") or {}).get("kept"))
    existing_equiv = None
    if existing_opt_kept:
        existing_equiv = check_formal_equivalence(pre_sv, old_fin_sv, input_context, target_rel, toplevel=top)

    # 2. Run an equivalence-aware optimization attempt with gemini-4-neon
    opt_prompt = (
        f"--- ORIGINAL SPECIFICATION ---\n{spec_prompt}\n\n"
        f"--- WORKING PRE-OPT RTL (Xilinx synth: {pre_res['luts']} LUTs, {pre_res['ffs']} FFs, "
        f"{pre_res['dsps']} DSPs, {pre_res['brams']} BRAMs) ---\n"
        f"{pre_sv}\n\n"
        "Optimize this RTL to use FEWER LUTs and/or FFs while preserving 100% strict formal equivalence "
        "with the working pre-opt RTL and WITHOUT increasing DSP or BRAM count."
    )

    cand_sv = ""
    cand_sim = {"passed": False}
    cand_equiv = {"proven": False, "reason": "Not run"}
    cand_synth: Dict[str, Any] = {"synth_ok": False}

    try:
        cand_sv = extract_verilog(call_neon(api_key, opt_prompt))
        cand_sim = run_hydrogen_sim(cand_sv, tb_sv, input_context, target_rel)
        if cand_sim["passed"]:
            cand_equiv = check_formal_equivalence(pre_sv, cand_sv, input_context, target_rel, toplevel=top)
            if cand_equiv["proven"]:
                cand_synth = synth_full_resources(cand_sv, input_context, target_rel, toplevel=top)
    except Exception as exc:
        cand_equiv = {"proven": False, "reason": f"Exception: {exc}"}

    # Decide best formally-proven candidate (between fresh candidate and existing final.sv)
    pre_total = pre_res["luts"] + pre_res["ffs"]
    chosen_sv = pre_sv
    chosen_res = pre_res
    kept = False
    kept_source = "pre_opt"
    reason = "Kept pre-opt (no candidate proved formally equivalent and smaller)"

    # Helper to check strict improvement without DSP/BRAM shift
    def _is_true_shrink(c_res: dict) -> bool:
        if not c_res.get("synth_ok"):
            return False
        if c_res["dsps"] > pre_res["dsps"] or c_res["brams"] > pre_res["brams"]:
            return False
        return (c_res["luts"] + c_res["ffs"]) < pre_total

    candidates = []
    if cand_sim["passed"] and cand_equiv["proven"] and _is_true_shrink(cand_synth):
        candidates.append(("fresh_equiv_opt", cand_sv, cand_synth))

    if existing_opt_kept and existing_equiv and existing_equiv["proven"]:
        old_res = synth_full_resources(old_fin_sv, input_context, target_rel, toplevel=top)
        if _is_true_shrink(old_res):
            candidates.append(("existing_final_proven", old_fin_sv, old_res))

    if candidates:
        candidates.sort(key=lambda x: x[2]["luts"] + x[2]["ffs"])
        kept_source, chosen_sv, chosen_res = candidates[0]
        kept = True
        reason = (
            f"Proven equivalent & smaller ({kept_source}): "
            f"LUT+FF {pre_total} -> {chosen_res['luts'] + chosen_res['ffs']}"
        )
    else:
        if not cand_sim["passed"]:
            reason = "Kept pre-opt: candidate failed Hydrogen tests"
        elif not cand_equiv["proven"]:
            reason = f"Kept pre-opt: formal equivalence not proven ({cand_equiv['reason'][:120]})"
        elif cand_synth.get("synth_ok") and (
            cand_synth["dsps"] > pre_res["dsps"] or cand_synth["brams"] > pre_res["brams"]
        ):
            reason = "Kept pre-opt: candidate shifted logic into DSP/BRAM"
        else:
            reason = "Kept pre-opt: proven equivalent but not smaller"

    (prob_dir / "final_equiv.sv").write_text(chosen_sv + "\n", encoding="utf-8")

    # FINAL GRADING WITH CVDP HIDDEN TESTS (ONLY NOW!)
    if kept:
        cvdp_equiv, toplevel = run_cvdp_hidden_grading(item, chosen_sv)
        chosen_res = synth_full_resources(chosen_sv, input_context, target_rel, toplevel=toplevel)
    else:
        cvdp_equiv = eng_rec["cvdp_pre_opt"]

    elapsed = round(time.perf_counter() - t0, 2)
    with print_lock:
        tag = f"KEPT ({pre_res['luts']}/{pre_res['ffs']} -> {chosen_res['luts']}/{chosen_res['ffs']})" if kept else "REVERTED_TO_PRE_OPT"
        print(
            f"[{idx:2d}/{total}] {pid:46s} | old_eq={existing_equiv['proven'] if existing_equiv else None} "
            f"| new_eq={cand_equiv['proven']} | {tag:24s} | CVDP={cvdp_equiv['status'].upper()} | {elapsed:5.1f}s",
            flush=True,
        )

    return {
        "problem": pid,
        "elapsed_seconds": elapsed,
        "existing_final_equiv": existing_equiv,
        "fresh_opt_hydrogen_passed": cand_sim["passed"],
        "fresh_opt_equiv": cand_equiv,
        "kept": kept,
        "kept_source": kept_source,
        "reason": reason,
        "cvdp_after_equiv_opt": cvdp_equiv,
        "resources_after_equiv_opt": {
            k: chosen_res.get(k) for k in ("synth_ok", "luts", "ffs", "carries", "dsps", "brams", "dist_rams")
        },
    }


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
    eng_data = json.loads(RESULTS_FILE.read_text(encoding="utf-8"))

    base_by_prob = {
        r["problem"]: r for r in baseline_data["results"] if r["model"] == DESIGN_MODEL
    }
    eng_by_prob = {r["problem"]: r for r in eng_data["results"]}

    print("=== PART 1: Auditing full Yosys resources (LUT, FF, Carry, DSP, BRAM) for all 20 problems ===", flush=True)
    resource_audit: Dict[str, Dict[str, Any]] = {}
    dsp_bram_shifts: List[Dict[str, Any]] = []

    for pid, domain in SELECTED_PROBLEMS:
        item = all_items[pid]
        input_context = item["input"].get("context", {}) or {}
        target_rel = list(item["output"]["context"].keys())[0]

        base_r = base_by_prob.get(pid, {})
        eng_r = eng_by_prob.get(pid, {})

        # Baseline resources (from pilot_cvdp/results.json cells_by_type or re-synth)
        base_y = base_r.get("yosys") or {}
        if base_y.get("synth_ok") and base_y.get("cells_by_type"):
            base_res = classify_xilinx_resources(base_y["cells_by_type"])
            base_res["synth_ok"] = True
        else:
            base_res = {"synth_ok": False, "luts": None, "ffs": None, "carries": None, "dsps": None, "brams": None, "dist_rams": None}

        # Pre-opt & post-opt (no equiv gate) resources
        prob_dir = GENERATED_DIR / pid
        pre_path = prob_dir / "pre_opt.sv"
        fin_path = prob_dir / "final.sv"

        pre_res = (
            synth_full_resources(pre_path.read_text(encoding="utf-8"), input_context, target_rel)
            if pre_path.exists()
            else {"synth_ok": False, "luts": None, "ffs": None, "carries": None, "dsps": None, "brams": None, "dist_rams": None}
        )
        fin_res = (
            synth_full_resources(fin_path.read_text(encoding="utf-8"), input_context, target_rel)
            if fin_path.exists()
            else {"synth_ok": False, "luts": None, "ffs": None, "carries": None, "dsps": None, "brams": None, "dist_rams": None}
        )

        # Detect DSP/BRAM shifts (comparing pre_opt -> post_opt AND baseline -> post_opt)
        shift_flags = []
        if pre_res.get("synth_ok") and fin_res.get("synth_ok"):
            if fin_res["dsps"] > pre_res["dsps"]:
                shift_flags.append(f"DSP increased vs pre_opt ({pre_res['dsps']} -> {fin_res['dsps']})")
            if fin_res["brams"] > pre_res["brams"]:
                shift_flags.append(f"BRAM increased vs pre_opt ({pre_res['brams']} -> {fin_res['brams']})")
            if fin_res["dist_rams"] > pre_res["dist_rams"]:
                shift_flags.append(f"DistRAM increased vs pre_opt ({pre_res['dist_rams']} -> {fin_res['dist_rams']})")
        if base_res.get("synth_ok") and fin_res.get("synth_ok"):
            if fin_res["dsps"] > base_res["dsps"]:
                shift_flags.append(f"DSP increased vs baseline ({base_res['dsps']} -> {fin_res['dsps']})")
            if fin_res["brams"] > base_res["brams"]:
                shift_flags.append(f"BRAM increased vs baseline ({base_res['brams']} -> {fin_res['brams']})")

        if shift_flags:
            dsp_bram_shifts.append(
                {
                    "problem": pid,
                    "flags": shift_flags,
                    "baseline": {k: base_res.get(k) for k in ("luts", "ffs", "dsps", "brams", "dist_rams")},
                    "pre_opt": {k: pre_res.get(k) for k in ("luts", "ffs", "dsps", "brams", "dist_rams")},
                    "post_opt": {k: fin_res.get(k) for k in ("luts", "ffs", "dsps", "brams", "dist_rams")},
                }
            )

        resource_audit[pid] = {
            "domain": domain,
            "baseline_status": base_r.get("status"),
            "pre_opt_status": (eng_r.get("cvdp_pre_opt") or {}).get("status"),
            "post_opt_status": (eng_r.get("cvdp_final") or {}).get("status"),
            "baseline": {k: base_res.get(k) for k in ("synth_ok", "luts", "ffs", "carries", "dsps", "brams", "dist_rams")},
            "pre_opt": {k: pre_res.get(k) for k in ("synth_ok", "luts", "ffs", "carries", "dsps", "brams", "dist_rams")},
            "post_opt_no_equiv": {k: fin_res.get(k) for k in ("synth_ok", "luts", "ffs", "carries", "dsps", "brams", "dist_rams")},
            "shift_flags": shift_flags,
        }

    # Fair intersection for Part 1 (passed CVDP in BOTH baseline AND post-opt without equiv gate)
    fair_ids_no_equiv = [
        pid
        for pid, _ in SELECTED_PROBLEMS
        if resource_audit[pid]["baseline_status"] == "pass"
        and resource_audit[pid]["post_opt_status"] == "pass"
        and resource_audit[pid]["baseline"]["synth_ok"]
        and resource_audit[pid]["post_opt_no_equiv"]["synth_ok"]
    ]

    def _avg_metrics(pids: List[str], field: str) -> Dict[str, Any]:
        rows = [resource_audit[p][field] for p in pids if resource_audit[p][field].get("synth_ok")]
        n = len(rows)
        if not n:
            return {"count": 0}
        return {
            "count": n,
            "avg_luts": round(sum(r["luts"] for r in rows) / n, 1),
            "avg_ffs": round(sum(r["ffs"] for r in rows) / n, 1),
            "avg_dsps": round(sum(r["dsps"] for r in rows) / n, 2),
            "avg_brams": round(sum(r["brams"] for r in rows) / n, 2),
        }

    print(f"Fair intersection (passed baseline & post-opt): {len(fair_ids_no_equiv)} problems", flush=True)
    print(f"DSP/BRAM shift flags found: {len(dsp_bram_shifts)}", flush=True)
    for sh in dsp_bram_shifts:
        print(f"  FLAG {sh['problem']}: {sh['flags']}", flush=True)

    # === PART 2: Equivalence-Gated Optimization Rerun on the 15 Pre-Opt Passing Problems ===
    pre_opt_passing = [
        pid for pid, _ in SELECTED_PROBLEMS if resource_audit[pid]["pre_opt_status"] == "pass"
    ]
    print(f"\n=== PART 2: Running Yosys Formal Equivalence-Gated Optimization on {len(pre_opt_passing)} pre-opt passing problems ===\n", flush=True)

    t2 = time.perf_counter()
    equiv_results: Dict[str, Dict[str, Any]] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        futs = {
            executor.submit(
                run_equiv_opt_for_problem,
                api_key,
                all_items[pid],
                eng_by_prob[pid],
                resource_audit[pid]["pre_opt"],
                idx,
                len(pre_opt_passing),
            ): pid
            for idx, pid in enumerate(pre_opt_passing, start=1)
        }
        for fut in concurrent.futures.as_completed(futs):
            res = fut.result()
            equiv_results[res["problem"]] = res
            resource_audit[res["problem"]]["post_opt_equiv"] = res["resources_after_equiv_opt"]
            resource_audit[res["problem"]]["post_opt_equiv_status"] = res["cvdp_after_equiv_opt"]["status"]

    # Fill non-passing pre-opt problems
    for pid, _ in SELECTED_PROBLEMS:
        if pid not in equiv_results:
            resource_audit[pid]["post_opt_equiv"] = resource_audit[pid]["pre_opt"]
            resource_audit[pid]["post_opt_equiv_status"] = resource_audit[pid]["pre_opt_status"]

    equiv_passed_total = sum(
        1 for pid, _ in SELECTED_PROBLEMS if resource_audit[pid]["post_opt_equiv_status"] == "pass"
    )
    equiv_broke = [
        pid for pid in pre_opt_passing if resource_audit[pid]["post_opt_equiv_status"] != "pass"
    ]
    equiv_kept_list = [pid for pid in pre_opt_passing if equiv_results[pid]["kept"]]

    fair_ids_equiv = [
        pid
        for pid, _ in SELECTED_PROBLEMS
        if resource_audit[pid]["baseline_status"] == "pass"
        and resource_audit[pid]["post_opt_equiv_status"] == "pass"
        and resource_audit[pid]["baseline"]["synth_ok"]
        and resource_audit[pid]["post_opt_equiv"].get("synth_ok")
    ]

    summary = {
        "fair_comparison_no_equiv_gate": {
            "intersection_count": len(fair_ids_no_equiv),
            "intersection_problems": fair_ids_no_equiv,
            "baseline": _avg_metrics(fair_ids_no_equiv, "baseline"),
            "pre_opt": _avg_metrics(fair_ids_no_equiv, "pre_opt"),
            "post_opt_no_equiv": _avg_metrics(fair_ids_no_equiv, "post_opt_no_equiv"),
        },
        "dsp_bram_shifts": dsp_bram_shifts,
        "equiv_gate_rerun": {
            "pre_opt_passing_count": len(pre_opt_passing),
            "after_equiv_opt_passing_count": equiv_passed_total,
            "after_equiv_opt_pass_rate_pct": round(100.0 * equiv_passed_total / len(SELECTED_PROBLEMS), 1),
            "optimizations_kept_count": len(equiv_kept_list),
            "optimizations_kept": equiv_kept_list,
            "breakages_after_equiv_gate": equiv_broke,
            "prevented_restoring_division_breakage": resource_audit["cvdp_copilot_restoring_division_0001"]["post_opt_equiv_status"] == "pass",
            "prevented_sync_lifo_breakage": resource_audit["cvdp_copilot_sync_lifo_0001"]["post_opt_equiv_status"] == "pass",
            "wall_seconds": round(time.perf_counter() - t2, 2),
        },
        "fair_comparison_with_equiv_gate": {
            "intersection_count": len(fair_ids_equiv),
            "intersection_problems": fair_ids_equiv,
            "baseline": _avg_metrics(fair_ids_equiv, "baseline"),
            "pre_opt": _avg_metrics(fair_ids_equiv, "pre_opt"),
            "post_opt_equiv": _avg_metrics(fair_ids_equiv, "post_opt_equiv"),
        },
    }

    payload = {
        "metadata": {
            "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "model": DESIGN_MODEL,
        },
        "summary": summary,
        "resource_audit": resource_audit,
        "equiv_rerun_details": equiv_results,
    }
    FOLLOWUP_RESULTS_FILE.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    print("\n=== FOLLOW-UP SUMMARY ===")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
