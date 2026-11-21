"""Step 6: Swappable Yosys Synthesis Report module (`synth_xilinx`).

Runs TWO Yosys syntheses:
1. Full board top (`synth_xilinx -top top`):
   - Separates **Logic** (`LUTs + Flip-Flops + Carry`) as the main figure.
   - Separates **Board I/O (fixed cost)** (`IBUF`, `OBUF`, `OBUFT`, `IOBUF`, `BUFG`).
2. Circuit-only synthesis (without the `top` board wrapper):
   - If `design.v` defines user submodule(s) separate from `top`, synthesizes
     the top-most user circuit module(s) directly with `synth_xilinx -noiopad`.
   - If the circuit is written inline inside `top`, runs
     `synth_xilinx -noiopad -top top` to measure pure circuit logic without
     board I/O pads.
"""

import json
import os
import re
import subprocess
import tempfile
import time
from typing import Any, Dict, List, Optional

from app.config import SYNTHESIS_CONFIG
from app.pipeline.tester import _strip_code_fences


def _classify_cells(cells_by_type: Dict[str, int]) -> Dict[str, int]:
    """Classify Xilinx cells into Logic (LUTs, FFs, Carry) vs Board I/O (fixed cost)."""
    luts = 0
    ffs = 0
    carries = 0
    board_io = 0
    other = 0
    for cell_type, count in cells_by_type.items():
        name = cell_type.upper()
        if re.match(r"^LUT[1-6]$", name):
            luts += count
        elif name.startswith("FD"):  # FDRE, FDSE, FDCE, FDPE, etc.
            ffs += count
        elif name.startswith("CARRY"):
            carries += count
        elif name in ("IBUF", "OBUF", "OBUFT", "IOBUF", "BUFG", "IBUFG"):
            board_io += count
        else:
            other += count
    logic_total = luts + ffs + carries
    return {
        "luts": luts,
        "ffs": ffs,
        "carries": carries,
        "logic_total": logic_total,
        "board_io": board_io,
        "other": other,
    }


def _find_user_modules(design_src: str, top_mod: str = "top") -> List[str]:
    """Return non-top module names declared in design_src."""
    # Strip line comments and block comments before regex search
    cleaned = re.sub(r"//.*", "", design_src)
    cleaned = re.sub(r"/\*.*?\*/", "", cleaned, flags=re.DOTALL)
    names = re.findall(r"\bmodule\s+([a-zA-Z_][a-zA-Z0-9_$]*)", cleaned)
    seen = []
    for n in names:
        if n != top_mod and n not in seen:
            seen.append(n)
    return seen


def _run_yosys_once(
    design_path: str,
    stat_path: str,
    target_cmd: str,
    top_mod: str,
    noiopad: bool = False,
    timeout_sec: int = 30,
) -> Dict[str, Any]:
    """Execute a single Yosys synth_xilinx run and parse stat.json."""
    extra = " -noiopad" if noiopad else ""
    yosys_script = (
        f"read_verilog -sv {design_path}; "
        f"{target_cmd}{extra} -top {top_mod}; "
        f"tee -q -o {stat_path} stat -json"
    )
    res = subprocess.run(
        ["yosys", "-q", "-p", yosys_script],
        capture_output=True,
        text=True,
        timeout=timeout_sec,
    )
    if res.returncode != 0 or not os.path.exists(stat_path):
        err = (res.stderr or res.stdout or "Yosys synthesis failed.").strip()
        return {"ok": False, "error": err[-1500:]}

    with open(stat_path, "r", encoding="utf-8") as f:
        stat_data = json.load(f)

    design_stats = stat_data.get("design", {})
    cells_by_type = design_stats.get("num_cells_by_type", {})
    total_cells = int(design_stats.get("num_cells", sum(cells_by_type.values())))
    counts = _classify_cells(cells_by_type)
    return {
        "ok": True,
        "module": top_mod,
        "luts": counts["luts"],
        "ffs": counts["ffs"],
        "carries": counts["carries"],
        "logic_total": counts["logic_total"],
        "board_io": counts["board_io"],
        "ios": counts["board_io"],
        "other_cells": counts["other"],
        "total_cells": total_cells,
        "cells_by_type": cells_by_type,
    }


def run_synthesis(verilog_code: str) -> Dict[str, Any]:
    """Run Yosys synth_xilinx on full `top` AND on just the user's circuit module(s)."""
    t0 = time.perf_counter()
    design_src = _strip_code_fences(verilog_code)
    top_mod = SYNTHESIS_CONFIG["top_module"]
    target_cmd = SYNTHESIS_CONFIG["target_cmd"]
    timeout_sec = SYNTHESIS_CONFIG["timeout_sec"]

    with tempfile.TemporaryDirectory(prefix="fpga_synth_") as tmpdir:
        design_path = os.path.join(tmpdir, "design.v")
        stat_top_path = os.path.join(tmpdir, "stat_top.json")
        with open(design_path, "w", encoding="utf-8") as f:
            f.write(design_src)

        try:
            top_res = _run_yosys_once(
                design_path, stat_top_path, target_cmd, top_mod, noiopad=False, timeout_sec=timeout_sec
            )
        except FileNotFoundError:
            return _err_result("Yosys is not installed or not on PATH.", t0)
        except subprocess.TimeoutExpired:
            return _err_result(f"Yosys synthesis timed out after {timeout_sec}s.", t0)

        if not top_res.get("ok"):
            return _err_result(top_res.get("error", "Yosys synthesis failed."), t0)

        # Second synthesis run: user's circuit modules only (without the `top` board wrapper)
        user_mods = _find_user_modules(design_src, top_mod=top_mod)
        circuit_only: Dict[str, Any] = {
            "ok": False,
            "mode": None,
            "modules": [],
            "luts": 0,
            "ffs": 0,
            "carries": 0,
            "logic_total": 0,
            "per_module": [],
        }

        try:
            if user_mods:
                # Synthesize each user module (without I/O pads) and also identify primary non-top root(s)
                per_mod = []
                total_luts = 0
                total_ffs = 0
                total_carries = 0
                for idx, mod_name in enumerate(user_mods):
                    mod_stat_path = os.path.join(tmpdir, f"stat_mod_{idx}.json")
                    mres = _run_yosys_once(
                        design_path, mod_stat_path, target_cmd, mod_name, noiopad=True, timeout_sec=timeout_sec
                    )
                    if mres.get("ok"):
                        per_mod.append(
                            {
                                "module": mod_name,
                                "luts": mres["luts"],
                                "ffs": mres["ffs"],
                                "carries": mres["carries"],
                                "logic_total": mres["logic_total"],
                                "cells_by_type": mres["cells_by_type"],
                            }
                        )
                        total_luts += mres["luts"]
                        total_ffs += mres["ffs"]
                        total_carries += mres["carries"]
                if per_mod:
                    # If there's 1 submodule, report it directly; if multiple, sum/show breakdown
                    circuit_only = {
                        "ok": True,
                        "mode": "user_modules",
                        "label": f"Circuit Module{'s' if len(per_mod) > 1 else ''}: {', '.join(m['module'] for m in per_mod)}",
                        "modules": [m["module"] for m in per_mod],
                        "luts": total_luts,
                        "ffs": total_ffs,
                        "carries": total_carries,
                        "logic_total": total_luts + total_ffs + total_carries,
                        "per_module": per_mod,
                    }
            else:
                # Inline circuit inside `top`: synthesize with -noiopad to exclude board I/O buffers
                noio_stat_path = os.path.join(tmpdir, "stat_noiopad.json")
                nres = _run_yosys_once(
                    design_path, noio_stat_path, target_cmd, top_mod, noiopad=True, timeout_sec=timeout_sec
                )
                if nres.get("ok"):
                    circuit_only = {
                        "ok": True,
                        "mode": "inline_noiopad",
                        "label": "Circuit Only (inline in top, no board I/O pads)",
                        "modules": [top_mod],
                        "luts": nres["luts"],
                        "ffs": nres["ffs"],
                        "carries": nres["carries"],
                        "logic_total": nres["logic_total"],
                        "per_module": [],
                    }
        except Exception as e:
            circuit_only["error"] = str(e)

        return {
            "ok": True,
            "target": target_cmd,
            "luts": top_res["luts"],
            "ffs": top_res["ffs"],
            "carries": top_res["carries"],
            "logic_total": top_res["logic_total"],
            "board_io": top_res["board_io"],
            "ios": top_res["board_io"],
            "total_cells": top_res["total_cells"],
            "cells_by_type": top_res["cells_by_type"],
            "circuit_only": circuit_only,
            "duration_ms": round((time.perf_counter() - t0) * 1000),
        }


def _err_result(msg: str, t0: float) -> Dict[str, Any]:
    return {
        "ok": False,
        "error": msg,
        "luts": 0,
        "ffs": 0,
        "carries": 0,
        "logic_total": 0,
        "board_io": 0,
        "ios": 0,
        "total_cells": 0,
        "cells_by_type": {},
        "circuit_only": {"ok": False},
        "duration_ms": round((time.perf_counter() - t0) * 1000),
    }
