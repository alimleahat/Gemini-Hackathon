"""Step 6: Swappable Yosys Synthesis Report module (`synth_xilinx`).

Synthesizes the final `module top` targeting Xilinx 7-series FPGAs and extracts
LUT counts, Flip-Flop counts, Carry chains, and full cell breakdown.
"""

import json
import os
import subprocess
import tempfile
import time
from typing import Any, Dict

from app.config import SYNTHESIS_CONFIG
from app.pipeline.tester import _strip_code_fences


def _classify_cells(cells_by_type: Dict[str, int]) -> Dict[str, int]:
    """Sum Xilinx LUTs, Flip-Flops, Carry chains, and IO buffers from Yosys stat."""
    luts = 0
    ffs = 0
    carries = 0
    ios = 0
    for cell_type, count in cells_by_type.items():
        name = cell_type.upper()
        if name.startswith("LUT"):
            luts += count
        elif name.startswith("FD"):  # FDRE, FDSE, FDCE, FDPE, etc.
            ffs += count
        elif name.startswith("CARRY"):
            carries += count
        elif name in ("IBUF", "OBUF", "OBUFT", "IOBUF", "BUFG"):
            ios += count
    return {
        "luts": luts,
        "ffs": ffs,
        "carries": carries,
        "ios": ios,
    }


def run_synthesis(verilog_code: str) -> Dict[str, Any]:
    """Run `yosys synth_xilinx` on `module top` and return LUT/FF counts."""
    t0 = time.perf_counter()
    design_src = _strip_code_fences(verilog_code)
    top_mod = SYNTHESIS_CONFIG["top_module"]
    target_cmd = SYNTHESIS_CONFIG["target_cmd"]
    timeout_sec = SYNTHESIS_CONFIG["timeout_sec"]

    with tempfile.TemporaryDirectory(prefix="fpga_synth_") as tmpdir:
        design_path = os.path.join(tmpdir, "design.v")
        stat_path = os.path.join(tmpdir, "stat.json")

        with open(design_path, "w", encoding="utf-8") as f:
            f.write(design_src)

        yosys_script = (
            f"read_verilog -sv {design_path}; "
            f"{target_cmd} -top {top_mod}; "
            f"tee -q -o {stat_path} stat -json"
        )

        try:
            res = subprocess.run(
                ["yosys", "-q", "-p", yosys_script],
                capture_output=True,
                text=True,
                timeout=timeout_sec,
            )
        except FileNotFoundError:
            return {
                "ok": False,
                "error": "Yosys is not installed or not on PATH.",
                "luts": 0,
                "ffs": 0,
                "carries": 0,
                "total_cells": 0,
                "cells_by_type": {},
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }
        except subprocess.TimeoutExpired:
            return {
                "ok": False,
                "error": f"Yosys synthesis timed out after {timeout_sec}s.",
                "luts": 0,
                "ffs": 0,
                "carries": 0,
                "total_cells": 0,
                "cells_by_type": {},
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }

        if res.returncode != 0 or not os.path.exists(stat_path):
            err = (res.stderr or res.stdout or "Yosys synthesis failed.").strip()
            return {
                "ok": False,
                "error": err[-1500:],
                "luts": 0,
                "ffs": 0,
                "carries": 0,
                "total_cells": 0,
                "cells_by_type": {},
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }

        with open(stat_path, "r", encoding="utf-8") as f:
            stat_data = json.load(f)

        design_stats = stat_data.get("design", {})
        cells_by_type = design_stats.get("num_cells_by_type", {})
        total_cells = int(design_stats.get("num_cells", sum(cells_by_type.values())))
        counts = _classify_cells(cells_by_type)

        return {
            "ok": True,
            "target": target_cmd,
            "luts": counts["luts"],
            "ffs": counts["ffs"],
            "carries": counts["carries"],
            "ios": counts["ios"],
            "total_cells": total_cells,
            "cells_by_type": cells_by_type,
            "duration_ms": round((time.perf_counter() - t0) * 1000),
        }
