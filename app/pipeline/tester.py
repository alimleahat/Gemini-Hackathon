"""Step 4: Compile and simulate Verilog with Icarus Verilog (iverilog + vvp).

Verifies two things:
1. The generated `top` module matches the exact virtual FPGA board interface
   by compiling it against a lightweight port-check harness.
2. `design.v` + `tb.v` compile cleanly and the self-checking testbench passes
   (`PASS` printed, no `FAIL`, clean exit).
"""

import json
import os
import re
import subprocess
import tempfile
import time
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field

from app.config import MODELS, TEST_CONFIG
from app.pipeline.client import get_client


class IndependentTestbench(BaseModel):
    test_plan: str = Field(
        description="1-2 sentence summary of what behaviors and edge cases this independent testbench checks."
    )
    testbench_code: str = Field(
        description="Complete self-checking Verilog-2005 testbench `module tb;` that instantiates `top`, prints `PASS` or `FAIL: <reason>`, and calls `$finish;`."
    )


TB_SYSTEM_INSTRUCTION = """You are an independent digital hardware verification engineer.
You are given ONLY the user's circuit drawing/description and the virtual FPGA board pin mapping — you NEVER see the RTL implementation.

Write a thorough, self-checking Verilog-2005 testbench (`module tb;`) that compiles cleanly with `iverilog -g2012` and runs in `vvp`:
1. Instantiate the DUT with the exact fixed virtual board ports:
   `top dut(.clk(clk), .sw(sw), .btn(btn), .led(led), .seg(seg), .an(an));`
2. Do NOT define `module top` inside `testbench_code` (it is compiled alongside `design.v`).
3. Use standard Verilog-2005 constructs supported by Icarus Verilog (no `assert property`, no classes, no queues).
4. For sequential/clocked circuits: assert reset (`btn[0] = 1`) for 1-2 clock edges at the start, then release reset and verify the expected state transitions.
5. Verify the mapped LEDs (`led[...]`) and/or active-low 7-segment display (`seg[6:0]`, `an[3:0]`) against the expected behavior from the drawing/spec.
6. Track `integer errors = 0;`. On any mismatch print `$display("FAIL: <reason>"); errors = errors + 1;`.
7. At the end: if `errors == 0` print `$display("PASS");` else `$display("FAIL: %0d errors", errors);`, and ALWAYS call `$finish;` within a few thousand time units.
"""


def generate_independent_testbench(
    *,
    image_b64: Optional[str] = None,
    mime_type: Optional[str] = None,
    text_prompt: Optional[str] = None,
    circuit_type: Optional[str] = None,
    circuit_name: Optional[str] = None,
    design_summary: Optional[str] = None,
    pin_mapping: Optional[List[Dict[str, Any]]] = None,
    schematic_json: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Use gemini-4-hydrogen to write an independent testbench WITHOUT seeing Neon's Verilog."""
    t0 = time.perf_counter()
    client = get_client()

    input_blocks = []
    if image_b64:
        input_blocks.append(
            {"type": "image", "data": image_b64, "mime_type": mime_type or "image/jpeg"}
        )

    lines = [
        "Write an independent self-checking Verilog testbench (`module tb;`) for this circuit."
    ]
    if circuit_name:
        lines.append(f"Circuit name: {circuit_name}")
    if circuit_type:
        lines.append(f"Circuit type: {circuit_type}")
    if design_summary:
        lines.append(f"Expected behavior summary: {design_summary}")
    if text_prompt and text_prompt.strip():
        lines.append(f"User description / notes: {text_prompt.strip()}")
    if pin_mapping:
        lines.append("Virtual FPGA board pin mapping (drive inputs and check outputs on these exact pins):")
        lines.append(json.dumps(pin_mapping, indent=2))
    if schematic_json:
        lines.append("Extracted schematic JSON:\n" + json.dumps(schematic_json, indent=2))

    input_blocks.append({"type": "text", "text": "\n\n".join(lines)})

    interaction = client.interactions.create(
        model=MODELS["testbench"],
        system_instruction=TB_SYSTEM_INSTRUCTION,
        input=input_blocks,
        generation_config={"thinking_level": "high"},
        response_format={
            "type": "text",
            "mime_type": "application/json",
            "schema": IndependentTestbench.model_json_schema(),
        },
    )
    parsed = IndependentTestbench.model_validate_json(interaction.output_text)
    return {
        "model": MODELS["testbench"],
        "test_plan": parsed.test_plan,
        "testbench_code": parsed.testbench_code,
        "duration_ms": round((time.perf_counter() - t0) * 1000),
    }

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
