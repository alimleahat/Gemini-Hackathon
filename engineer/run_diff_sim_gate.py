"""Task 1: Differential Simulation Gate (10,000+ random cycles) for Engineer Loop.

For each optimization from the original loop run (reusing existing `pre_opt.sv`
and `final.sv` in `engineer/generated/` — NO regeneration):
1. Extract exact module ports & widths via Yosys JSON.
2. Simulate `pre_opt` and `final` side-by-side in Icarus Verilog (`iverilog -g2012`)
   for 10,000+ random input cycles (including initial + periodic resets),
   comparing every output every cycle.
3. Also reject if Yosys `synth_xilinx` shows DSP, BRAM, or Distributed RAM
   usage increased (area moved rather than saved).
4. Grade accepted designs with CVDP hidden tests and compute fair-intersection
   area averages vs. the baseline single Neon call.
"""

import concurrent.futures
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

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
    infer_top_module_name,
    run_cvdp_hidden_grading,
)
from run_followup import synth_full_resources

DIFF_RESULTS_FILE = ROOT / "diff_sim_results.json"
NUM_RANDOM_CYCLES = 10500
print_lock = threading.Lock()


def extract_ports_via_yosys(
    sv_code: str,
    input_context: Dict[str, str],
    target_rel: str,
    top_name: str,
) -> Tuple[Optional[List[Dict[str, Any]]], str]:
    """Use Yosys write_json to get exact resolved port names, directions, and bit widths."""
    with tempfile.TemporaryDirectory(prefix="diff_ports_") as tmpdir:
        d = Path(tmpdir)
        files = []
        for rel, content in (input_context or {}).items():
            if rel.endswith((".v", ".sv", ".vh", ".svh")):
                p = d / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(content, encoding="utf-8")
                if rel.endswith((".v", ".sv")) and rel != target_rel:
                    files.append(str(p))
        tp = d / target_rel
        tp.parent.mkdir(parents=True, exist_ok=True)
        tp.write_text(sv_code + "\n", encoding="utf-8")
        files.append(str(tp))

        out_json = d / "netlist.json"
        script = f"read_verilog -sv {' '.join(files)}; hierarchy -check -top {top_name}; proc; write_json {out_json}"
        proc = subprocess.run(["yosys", "-q", "-p", script], capture_output=True, text=True, timeout=30)
        if proc.returncode != 0 or not out_json.exists():
            return None, (proc.stderr or proc.stdout)[-400:].strip()

        data = json.loads(out_json.read_text(encoding="utf-8"))
        mod = data.get("modules", {}).get(top_name)
        if not mod:
            return None, f"Module {top_name} not found in Yosys JSON"

        ports = []
        for pname, pinfo in mod.get("ports", {}).items():
            ports.append(
                {
                    "name": pname,
                    "direction": pinfo.get("direction", "input"),
                    "width": len(pinfo.get("bits", [])),
                }
            )
        return ports, ""


def rename_all_modules(sv_code: str, suffix: str) -> Tuple[str, List[str]]:
    """Suffix all module names declared in `sv_code` and their instantiations inside `sv_code`."""
    cleaned = re.sub(r"//.*", "", sv_code)
    cleaned = re.sub(r"/\*.*?\*/", "", cleaned, flags=re.DOTALL)
    mod_names = re.findall(r"\bmodule\s+([a-zA-Z_][a-zA-Z0-9_$]*)", cleaned)
    seen = []
    for m in mod_names:
        if m not in seen:
            seen.append(m)

    out = sv_code
    for m in seen:
        # Replace `module <m>` and instantiations `<m> #(` or `<m> <inst>(`
        out = re.sub(rf"\bmodule\s+{re.escape(m)}\b", f"module {m}{suffix}", out)
        # Replace instantiations of helper submodules within the same file
        out = re.sub(rf"(?m)^(\s*){re.escape(m)}(\s+(?:#\s*\(|[a-zA-Z_]))", rf"\1{m}{suffix}\2", out)
    return out, seen


def is_clock_port(name: str) -> bool:
    n = name.lower()
    return n in ("clk", "clock", "i_clk", "aclk", "pclk", "hclk", "wb_clk_i", "clk_i", "sys_clk") or n.endswith("_clk") or n.startswith("clk_")


def is_reset_port(name: str) -> Tuple[bool, bool]:
    """Return (is_reset, active_low)."""
    n = name.lower()
    active_low_names = ("rst_n", "rstn", "reset_n", "resetn", "aresetn", "presetn", "hresetn", "rst_ni", "nrst", "nreset")
    if any(n == a or n.endswith("_" + a) or n.endswith("rst_n") or n.endswith("reset_n") or n.endswith("rstn") or n.endswith("resetn") for a in active_low_names):
        return True, True
    if n in ("rst", "reset", "i_rst", "wb_rst_i", "rst_i", "sys_rst", "srst", "arst") or n.startswith("rst_") or n.endswith("_rst"):
        return True, False
    return False, False


def build_diff_testbench(top_name: str, ports: List[Dict[str, Any]], num_cycles: int) -> str:
    inputs = [p for p in ports if p["direction"] == "input"]
    outputs = [p for p in ports if p["direction"] == "output"]

    clk_ports = [p for p in inputs if is_clock_port(p["name"]) and p["width"] == 1]
    rst_ports = [(p, is_reset_port(p["name"])[1]) for p in inputs if is_reset_port(p["name"])[0] and p["width"] == 1]
    rst_names = {p["name"] for p, _ in rst_ports}
    clk_names = {p["name"] for p in clk_ports}
    data_inputs = [p for p in inputs if p["name"] not in clk_names and p["name"] not in rst_names]

    lines = ["module tb_diff;"]
    for p in inputs:
        w = p["width"]
        decl = f"[{w-1}:0] " if w > 1 else ""
        lines.append(f"  reg {decl}{p['name']} = 0;")
    for p in outputs:
        w = p["width"]
        decl = f"[{w-1}:0] " if w > 1 else ""
        lines.append(f"  wire {decl}pre_{p['name']};")
        lines.append(f"  wire {decl}opt_{p['name']};")

    # Instantiate pre and opt DUTs
    pre_conns = [f".{p['name']}({p['name']})" for p in inputs] + [f".{p['name']}(pre_{p['name']})" for p in outputs]
    opt_conns = [f".{p['name']}({p['name']})" for p in inputs] + [f".{p['name']}(opt_{p['name']})" for p in outputs]

    lines.append(f"  {top_name}_pre u_pre ({', '.join(pre_conns)});")
    lines.append(f"  {top_name}_opt u_opt ({', '.join(opt_conns)});")

    lines.append("  integer cyc;")
    lines.append("  integer mismatches = 0;")
    lines.append("  integer seed = 32'h1357_2468;")
    lines.append("  reg [31:0] rtmp;")

    def _drive_resets(asserted: bool) -> List[str]:
        out = []
        for p, active_low in rst_ports:
            val = ("0" if active_low else "1") if asserted else ("1" if active_low else "0")
            out.append(f"      {p['name']} = 1'b{val};")
        return out

    def _step_clock() -> List[str]:
        if clk_ports:
            step = ["      #5;"]
            for p in clk_ports:
                step.append(f"      {p['name']} = 1'b1;")
            step.append("      #5;")
            for p in clk_ports:
                step.append(f"      {p['name']} = 1'b0;")
            step.append("      #1;")
            return step
        return ["      #10;"]

    def _randomize_inputs() -> List[str]:
        out = []
        for p in data_inputs:
            w = p["width"]
            if w <= 32:
                out.append(f"      {p['name']} = $urandom(seed);")
            else:
                chunks = (w + 31) // 32
                concat = ", ".join(["$urandom(seed)"] * chunks)
                out.append(f"      {p['name']} = {{{concat}}};")
        return out

    lines.append("  initial begin")
    # Initial reset (5 cycles)
    lines.extend(_drive_resets(True))
    lines.append("    for (cyc = 0; cyc < 5; cyc = cyc + 1) begin")
    lines.extend(_step_clock())
    lines.append("    end")
    lines.extend(_drive_resets(False))

    # Main 10,000+ random cycles loop
    lines.append(f"    for (cyc = 0; cyc < {num_cycles}; cyc = cyc + 1) begin")
    lines.extend(_randomize_inputs())
    if rst_ports:
        lines.append("      rtmp = $urandom(seed);")
        lines.append("      if (rtmp[7:0] == 8'h00) begin")
        lines.extend(["  " + s for s in _drive_resets(True)])
        lines.append("      end else begin")
        lines.extend(["  " + s for s in _drive_resets(False)])
        lines.append("      end")
    lines.extend(_step_clock())

    # Compare every output every cycle
    for p in outputs:
        pn = p["name"]
        lines.append(f"      if (pre_{pn} !== opt_{pn}) begin")
        lines.append(f"        if (mismatches < 5) $display(\"MISMATCH cyc=%0d port={pn} pre=%h opt=%h\", cyc, pre_{pn}, opt_{pn});")
        lines.append("        mismatches = mismatches + 1;")
        lines.append("      end")

    lines.append("    end")
    lines.append(f"    if (mismatches == 0) $display(\"DIFF_PASS cycles={num_cycles}\");")
    lines.append("    else $display(\"DIFF_FAIL mismatches=%0d\", mismatches);")
    lines.append("    $finish;")
    lines.append("  end")
    lines.append("endmodule")
    return "\n".join(lines) + "\n"


def run_diff_sim(
    pre_sv: str,
    opt_sv: str,
    input_context: Dict[str, str],
    target_rel: str,
    top_name: str,
    num_cycles: int = NUM_RANDOM_CYCLES,
) -> Dict[str, Any]:
    t0 = time.perf_counter()
    ports, perr = extract_ports_via_yosys(pre_sv, input_context, target_rel, top_name)
    if not ports:
        return {"passed": False, "reason": f"Port extraction failed: {perr}", "cycles": 0, "duration_ms": round((time.perf_counter() - t0) * 1000)}

    pre_renamed, _ = rename_all_modules(pre_sv, "_pre")
    opt_renamed, _ = rename_all_modules(opt_sv, "_opt")
    tb_code = build_diff_testbench(top_name, ports, num_cycles)

    with tempfile.TemporaryDirectory(prefix="diff_sim_") as tmpdir:
        d = Path(tmpdir)
        ctx_files = []
        for rel, content in (input_context or {}).items():
            if rel.endswith((".v", ".sv", ".vh", ".svh")):
                p = d / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(content, encoding="utf-8")
                if rel.endswith((".v", ".sv")) and rel != target_rel:
                    ctx_files.append(str(p))

        pre_path = d / "dut_pre.sv"
        opt_path = d / "dut_opt.sv"
        tb_path = d / "tb_diff.sv"
        vvp_path = d / "diff.vvp"
        pre_path.write_text(pre_renamed + "\n", encoding="utf-8")
        opt_path.write_text(opt_renamed + "\n", encoding="utf-8")
        tb_path.write_text(tb_code, encoding="utf-8")

        inc_dirs = sorted({str(Path(f).parent) for f in ctx_files} | {str(d)})
        inc_flags = []
        for inc in inc_dirs:
            inc_flags.extend(["-I", inc])

        comp = subprocess.run(
            ["iverilog", "-g2012", *inc_flags, "-o", str(vvp_path), *ctx_files, str(pre_path), str(opt_path), str(tb_path)],
            capture_output=True,
            text=True,
            timeout=20,
        )
        if comp.returncode != 0:
            return {
                "passed": False,
                "reason": f"Diff TB compile error: {(comp.stderr or comp.stdout).strip()[:400]}",
                "cycles": 0,
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }

        try:
            sim = subprocess.run(["vvp", str(vvp_path)], capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            return {
                "passed": False,
                "reason": "Diff simulation timed out after 60s",
                "cycles": 0,
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }

        stdout = sim.stdout.strip()
        passed = sim.returncode == 0 and f"DIFF_PASS cycles={num_cycles}" in stdout
        first_mismatch = next((ln for ln in stdout.splitlines() if "MISMATCH" in ln), None)
        return {
            "passed": passed,
            "cycles": num_cycles if passed else 0,
            "first_mismatch": first_mismatch,
            "stdout_tail": "\n".join(stdout.splitlines()[-6:]),
            "reason": f"Exact match across {num_cycles} random cycles" if passed else (first_mismatch or stdout[-300:]),
            "duration_ms": round((time.perf_counter() - t0) * 1000),
        }


def evaluate_problem(item: dict, eng_rec: dict, base_rec: dict, idx: int, total: int) -> Dict[str, Any]:
    pid = item["id"]
    input_context = item["input"].get("context", {}) or {}
    target_rel = list(item["output"]["context"].keys())[0]
    prob_dir = GENERATED_DIR / pid

    pre_path = prob_dir / "pre_opt.sv"
    fin_path = prob_dir / "final.sv"
    orig_opt_kept = bool((eng_rec.get("optimization") or {}).get("kept"))

    pre_res = synth_full_resources(pre_path.read_text(encoding="utf-8"), input_context, target_rel) if pre_path.exists() else {"synth_ok": False}
    fin_res = synth_full_resources(fin_path.read_text(encoding="utf-8"), input_context, target_rel) if fin_path.exists() else {"synth_ok": False}

    diff_res = None
    dsp_ram_increased = False
    dsp_ram_reason = None
    accepted = False

    if orig_opt_kept and pre_path.exists() and fin_path.exists():
        pre_sv = pre_path.read_text(encoding="utf-8")
        fin_sv = fin_path.read_text(encoding="utf-8")
        top = infer_top_module_name(pre_sv)

        # Check DSP / RAM increase
        if pre_res.get("synth_ok") and fin_res.get("synth_ok"):
            reasons = []
            if fin_res["dsps"] > pre_res["dsps"]:
                reasons.append(f"DSP {pre_res['dsps']}->{fin_res['dsps']}")
            if fin_res["brams"] > pre_res["brams"]:
                reasons.append(f"BRAM {pre_res['brams']}->{fin_res['brams']}")
            if fin_res["dist_rams"] > pre_res["dist_rams"]:
                reasons.append(f"DistRAM {pre_res['dist_rams']}->{fin_res['dist_rams']}")
            if reasons:
                dsp_ram_increased = True
                dsp_ram_reason = ", ".join(reasons)

        # Run 10,500-cycle differential simulation regardless (so we log both signals!)
        diff_res = run_diff_sim(pre_sv, fin_sv, input_context, target_rel, top, NUM_RANDOM_CYCLES)
        accepted = bool(diff_res["passed"]) and (not dsp_ram_increased)

    # Final CVDP grading
    if accepted:
        cvdp_final, toplevel = run_cvdp_hidden_grading(item, fin_path.read_text(encoding="utf-8"))
        final_res = synth_full_resources(fin_path.read_text(encoding="utf-8"), input_context, target_rel, toplevel=toplevel)
    else:
        cvdp_final = eng_rec["cvdp_pre_opt"]
        final_res = pre_res

    with print_lock:
        if orig_opt_kept:
            d_str = "DIFF_OK" if (diff_res and diff_res["passed"]) else "DIFF_FAIL"
            r_str = f"SHIFT({dsp_ram_reason})" if dsp_ram_increased else "no-shift"
            acc_str = "ACCEPTED" if accepted else "REJECTED"
            print(
                f"[{idx:2d}/{total}] {pid:46s} | {d_str:9s} | {r_str:16s} | {acc_str:8s} | CVDP={cvdp_final['status'].upper()}",
                flush=True,
            )
        else:
            print(
                f"[{idx:2d}/{total}] {pid:46s} | no-orig-opt | kept pre_opt | CVDP={cvdp_final['status'].upper()}",
                flush=True,
            )

    return {
        "problem": pid,
        "baseline_status": base_rec.get("status"),
        "pre_opt_status": (eng_rec.get("cvdp_pre_opt") or {}).get("status"),
        "orig_opt_kept": orig_opt_kept,
        "orig_post_opt_status": (eng_rec.get("cvdp_final") or {}).get("status"),
        "diff_sim": diff_res,
        "dsp_ram_increased": dsp_ram_increased,
        "dsp_ram_reason": dsp_ram_reason,
        "accepted_by_diff_gate": accepted,
        "cvdp_after_diff_gate": cvdp_final,
        "pre_opt_resources": {k: pre_res.get(k) for k in ("synth_ok", "luts", "ffs", "dsps", "brams", "dist_rams")},
        "final_resources": {k: final_res.get(k) for k in ("synth_ok", "luts", "ffs", "dsps", "brams", "dist_rams")},
    }


def main() -> None:
    all_items = {
        obj["id"]: obj
        for obj in (json.loads(line) for line in DATASET_PATH.open(encoding="utf-8"))
    }
    baseline_data = json.loads(BASELINE_RESULTS_PATH.read_text(encoding="utf-8"))
    eng_data = json.loads(RESULTS_FILE.read_text(encoding="utf-8"))

    base_by_prob = {r["problem"]: r for r in baseline_data["results"] if r["model"] == DESIGN_MODEL}
    eng_by_prob = {r["problem"]: r for r in eng_data["results"]}

    print(f"Starting Differential Simulation Gate ({NUM_RANDOM_CYCLES} random cycles/design) on all 20 problems...\n", flush=True)
    t0 = time.perf_counter()

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
        futs = [
            ex.submit(evaluate_problem, all_items[pid], eng_by_prob[pid], base_by_prob[pid], idx, len(SELECTED_PROBLEMS))
            for idx, (pid, _) in enumerate(SELECTED_PROBLEMS, start=1)
        ]
        for fut in concurrent.futures.as_completed(futs):
            results.append(fut.result())

    order = {pid: i for i, (pid, _) in enumerate(SELECTED_PROBLEMS)}
    results.sort(key=lambda r: order[r["problem"]])
    by_pid = {r["problem"]: r for r in results}

    # Compute summary stats
    passed_total = sum(1 for r in results if r["cvdp_after_diff_gate"]["status"] == "pass")
    accepted_all = [r["problem"] for r in results if r["accepted_by_diff_gate"]]
    accepted_passing = [
        r["problem"] for r in results if r["accepted_by_diff_gate"] and r["cvdp_after_diff_gate"]["status"] == "pass"
    ]
    breakages = [
        r["problem"]
        for r in results
        if r["pre_opt_status"] == "pass" and r["cvdp_after_diff_gate"]["status"] != "pass"
    ]

    # Fair intersection: passed CVDP in BOTH baseline AND after diff-sim gate
    from run_followup import classify_xilinx_resources
    fair_ids = []
    base_rows = []
    pre_rows = []
    diff_rows = []
    for r in results:
        pid = r["problem"]
        b_y = (base_by_prob[pid].get("yosys") or {})
        if (
            r["baseline_status"] == "pass"
            and r["cvdp_after_diff_gate"]["status"] == "pass"
            and b_y.get("synth_ok")
            and b_y.get("cells_by_type")
            and r["final_resources"].get("synth_ok")
        ):
            fair_ids.append(pid)
            base_rows.append(classify_xilinx_resources(b_y["cells_by_type"]))
            pre_rows.append(r["pre_opt_resources"])
            diff_rows.append(r["final_resources"])

    def _avg(rows):
        n = len(rows)
        return {
            "count": n,
            "avg_luts": round(sum(x["luts"] for x in rows) / n, 1) if n else None,
            "avg_ffs": round(sum(x["ffs"] for x in rows) / n, 1) if n else None,
            "avg_dsps": round(sum(x["dsps"] for x in rows) / n, 2) if n else None,
            "avg_brams": round(sum(x["brams"] for x in rows) / n, 2) if n else None,
        }

    axi = by_pid["cvdp_copilot_axi_register_0001"]
    summary = {
        "wall_seconds": round(time.perf_counter() - t0, 2),
        "num_random_cycles": NUM_RANDOM_CYCLES,
        "final_passed": passed_total,
        "total_problems": len(SELECTED_PROBLEMS),
        "final_pass_rate_pct": round(100.0 * passed_total / len(SELECTED_PROBLEMS), 1),
        "accepted_optimizations_all": accepted_all,
        "accepted_optimizations_all_count": len(accepted_all),
        "accepted_optimizations_passing_cvdp": accepted_passing,
        "accepted_optimizations_passing_cvdp_count": len(accepted_passing),
        "breakages": breakages,
        "caught_restoring_division": not by_pid["cvdp_copilot_restoring_division_0001"]["accepted_by_diff_gate"],
        "caught_sync_lifo": not by_pid["cvdp_copilot_sync_lifo_0001"]["accepted_by_diff_gate"],
        "axi_register_detail": {
            "baseline_status": axi["baseline_status"],
            "pre_opt_status": axi["pre_opt_status"],
            "orig_post_opt_status": axi["orig_post_opt_status"],
            "diff_sim_passed": (axi["diff_sim"] or {}).get("passed"),
            "diff_sim_reason": (axi["diff_sim"] or {}).get("reason"),
            "accepted_by_diff_gate": axi["accepted_by_diff_gate"],
            "cvdp_after_diff_gate": axi["cvdp_after_diff_gate"]["status"],
            "note": "In the earlier formal equiv rerun, only the 15 pre-opt passing problems were rerun, so axi_register (pre-opt FAIL) was not checked by the formal gate. Here, differential simulation explicitly checks axi_register pre_opt vs final.",
        },
        "fair_intersection": {
            "count": len(fair_ids),
            "problems": fair_ids,
            "baseline": _avg(base_rows),
            "pre_opt": _avg(pre_rows),
            "after_diff_sim_gate": _avg(diff_rows),
        },
    }

    payload = {
        "metadata": {
            "timestamp_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "cycles": NUM_RANDOM_CYCLES,
        },
        "summary": summary,
        "results": results,
    }
    DIFF_RESULTS_FILE.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    print("\n=== DIFFERENTIAL SIMULATION GATE SUMMARY ===")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
