"""Step 4: Compile and simulate Verilog with Icarus Verilog (iverilog + vvp).

Verifies two things:
1. The generated `top` module matches the exact virtual FPGA board interface
   by compiling it against a lightweight port-check harness.
2. `design.v` + `tb.v` compile cleanly and the self-checking testbench passes
   (`PASS` printed, no `FAIL`, clean exit).
"""

import os
import re
import subprocess
import tempfile
import time
from typing import Any, Dict

from app.config import TEST_CONFIG

PORT_CHECK_HARNESS = """
module __board_port_check;
    reg clk = 0;
    reg [15:0] sw = 16'h0000;
    reg [4:0] btn = 5'h00;
    wire [15:0] led;
    wire [6:0] seg;
    wire [3:0] an;
    top __dut (
        .clk(clk),
        .sw(sw),
        .btn(btn),
        .led(led),
        .seg(seg),
        .an(an)
    );
    initial $finish;
endmodule
"""


def _strip_code_fences(code: str) -> str:
    """Remove accidental markdown code fences if a model emits them."""
    text = code.strip()
    if text.startswith("```"):
        text = re.sub(r"^```[a-zA-Z0-9_-]*\n?", "", text)
        text = re.sub(r"\n?```$", "", text)
    return text.strip() + "\n"


def run_test(verilog_code: str, testbench_code: str) -> Dict[str, Any]:
    """Compile and simulate design.v + tb.v with Icarus Verilog."""
    t0 = time.perf_counter()
    design_src = _strip_code_fences(verilog_code)
    tb_src = _strip_code_fences(testbench_code)

    compile_timeout = TEST_CONFIG["compile_timeout_sec"]
    sim_timeout = TEST_CONFIG["sim_timeout_sec"]

    with tempfile.TemporaryDirectory(prefix="fpga_test_") as tmpdir:
        design_path = os.path.join(tmpdir, "design.v")
        tb_path = os.path.join(tmpdir, "tb.v")
        port_check_path = os.path.join(tmpdir, "port_check.v")
        port_vvp = os.path.join(tmpdir, "port_check.vvp")
        sim_vvp = os.path.join(tmpdir, "sim.vvp")

        with open(design_path, "w", encoding="utf-8") as f:
            f.write(design_src)
        with open(tb_path, "w", encoding="utf-8") as f:
            f.write(tb_src)
        with open(port_check_path, "w", encoding="utf-8") as f:
            f.write(PORT_CHECK_HARNESS)

        # 1. Verify `module top` matches the exact virtual FPGA board ports
        try:
            port_res = subprocess.run(
                ["iverilog", "-g2012", "-o", port_vvp, design_path, port_check_path],
                capture_output=True,
                text=True,
                timeout=compile_timeout,
            )
        except subprocess.TimeoutExpired:
            return _result(
                passed=False,
                compile_ok=False,
                board_interface_ok=False,
                sim_ok=False,
                stdout="",
                stderr="Board interface check timed out during compilation.",
                summary="Compilation timed out",
                t0=t0,
            )

        if port_res.returncode != 0:
            err_text = (port_res.stderr or port_res.stdout).strip()
            return _result(
                passed=False,
                compile_ok=False,
                board_interface_ok=False,
                sim_ok=False,
                stdout=port_res.stdout.strip(),
                stderr=f"Board interface / design.v compile error:\n{err_text}",
                summary="Design failed board-interface compile check",
                t0=t0,
            )

        # 2. Compile design.v + tb.v
        try:
            comp_res = subprocess.run(
                ["iverilog", "-g2012", "-o", sim_vvp, design_path, tb_path],
                capture_output=True,
                text=True,
                timeout=compile_timeout,
            )
        except subprocess.TimeoutExpired:
            return _result(
                passed=False,
                compile_ok=False,
                board_interface_ok=True,
                sim_ok=False,
                stdout="",
                stderr="Testbench compilation timed out.",
                summary="Testbench compilation timed out",
                t0=t0,
            )

        if comp_res.returncode != 0:
            err_text = (comp_res.stderr or comp_res.stdout).strip()
            return _result(
                passed=False,
                compile_ok=False,
                board_interface_ok=True,
                sim_ok=False,
                stdout=comp_res.stdout.strip(),
                stderr=f"Testbench compile error:\n{err_text}",
                summary="Testbench failed to compile",
                t0=t0,
            )

        # 3. Run simulation with vvp
        try:
            sim_res = subprocess.run(
                ["vvp", sim_vvp],
                capture_output=True,
                text=True,
                timeout=sim_timeout,
            )
        except subprocess.TimeoutExpired:
            return _result(
                passed=False,
                compile_ok=True,
                board_interface_ok=True,
                sim_ok=False,
                stdout="",
                stderr=(
                    f"Simulation timed out after {sim_timeout}s. "
                    "Make sure the testbench calls $finish; and has no infinite loop."
                ),
                summary="Simulation timed out",
                t0=t0,
            )

        stdout = sim_res.stdout.strip()
        stderr = sim_res.stderr.strip()
        combined = f"{stdout}\n{stderr}"

        has_fail = bool(re.search(r"\b(FAIL|ERROR)\b", combined, re.IGNORECASE))
        has_pass = bool(re.search(r"\bPASS\b", stdout, re.IGNORECASE))

        sim_ok = sim_res.returncode == 0 and not has_fail and has_pass
        if sim_ok:
            summary = "Compiled and passed all simulation checks"
        elif sim_res.returncode != 0:
            summary = f"Simulation exited with code {sim_res.returncode}"
        elif has_fail:
            summary = "Simulation reported test failure(s)"
        else:
            summary = "Simulation finished without printing PASS"

        return _result(
            passed=sim_ok,
            compile_ok=True,
            board_interface_ok=True,
            sim_ok=sim_ok,
            stdout=stdout,
            stderr=stderr,
            summary=summary,
            t0=t0,
        )


def _result(
    *,
    passed: bool,
    compile_ok: bool,
    board_interface_ok: bool,
    sim_ok: bool,
    stdout: str,
    stderr: str,
    summary: str,
    t0: float,
) -> Dict[str, Any]:
    return {
        "passed": passed,
        "compile_ok": compile_ok,
        "board_interface_ok": board_interface_ok,
        "sim_ok": sim_ok,
        "stdout": stdout,
        "stderr": stderr,
        "summary": summary,
        "duration_ms": round((time.perf_counter() - t0) * 1000),
    }
