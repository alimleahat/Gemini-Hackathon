"""Step 5: Swappable Iterative Improvement Loop powered by gemini-4-hydrogen.

Designed as an isolated, swappable module so its objective can easily be
changed later (e.g., fixing compile/test errors, optimizing LUT/FF area, or
both) without touching the rest of the pipeline.

Current strategy (`mode = "fix_errors"`):
When Icarus Verilog compilation or simulation fails, sends the Verilog,
testbench, and error output to `gemini-4-hydrogen` and returns a repaired
version, up to `IMPROVE_CONFIG["max_rounds"]` rounds.
"""

import time
from typing import Any, Callable, Dict, List, Optional
from pydantic import BaseModel, Field

from app.config import IMPROVE_CONFIG, MODELS
from app.pipeline.client import get_client
from app.pipeline.tester import run_test


class ImprovedDesign(BaseModel):
    fix_summary: str = Field(
        description="1-2 sentence plain-English summary of what bug was found and how it was fixed."
    )
    verilog_code: str = Field(
        description="Complete updated, synthesizable Verilog-2005 code with `module top(clk, sw, btn, led, seg, an)`."
    )
    testbench_code: str = Field(
        description="Complete updated self-checking Verilog testbench `module tb;`."
    )


IMPROVE_SYSTEM_INSTRUCTION = """You are an expert Verilog debugging and hardware verification engineer.
You will be given:
1. A Verilog-2005 design (`module top`) targeting a virtual FPGA board with exact ports:
   `module top(input clk, input [15:0] sw, input [4:0] btn, output [15:0] led, output [6:0] seg, output [3:0] an);`
2. A self-checking testbench (`module tb;`).
3. Compiler or simulation errors from Icarus Verilog (`iverilog -g2012` / `vvp`).

Your job:
- Diagnose the root cause of the failure (syntax error, port mismatch, logic bug, testbench bug, missing `$finish`, X-propagation, etc.).
- Return the COMPLETE fixed `verilog_code` and `testbench_code`.
- Keep `module top` ports EXACTLY as specified, keep it Verilog-2005 / Yosys-synthesizable, initialize registers to 0, and avoid 100MHz clock dividers.
- Ensure `module tb` prints `PASS` when all checks succeed and calls `$finish;`.
"""


def run_improve_round(
    *,
    round_num: int,
    verilog_code: str,
    testbench_code: str,
    test_result: Dict[str, Any],
    circuit_name: str = "",
    design_summary: str = "",
    mode: Optional[str] = None,
) -> Dict[str, Any]:
    """Run a single improvement round and re-test with Icarus Verilog."""
    t0 = time.perf_counter()
    active_mode = mode or IMPROVE_CONFIG["mode"]
    client = get_client()

    prompt = (
        f"Circuit: {circuit_name}\n"
        f"Summary: {design_summary}\n"
        f"Improvement round: {round_num} (mode: {active_mode})\n\n"
        f"--- CURRENT design.v ---\n{verilog_code}\n\n"
        f"--- CURRENT tb.v ---\n{testbench_code}\n\n"
        f"--- ICARUS VERILOG FAILURE ---\n"
        f"Summary: {test_result.get('summary', '')}\n"
        f"STDOUT:\n{test_result.get('stdout', '') or '(empty)'}\n"
        f"STDERR:\n{test_result.get('stderr', '') or '(empty)'}\n\n"
        "Fix the issue and return the complete corrected `verilog_code`, `testbench_code`, and a short `fix_summary`."
    )

    interaction = client.interactions.create(
        model=MODELS["improve"],
        system_instruction=IMPROVE_SYSTEM_INSTRUCTION,
        input=prompt,
        response_format={
            "type": "text",
            "mime_type": "application/json",
            "schema": ImprovedDesign.model_json_schema(),
        },
    )

    improved = ImprovedDesign.model_validate_json(interaction.output_text)
    new_test = run_test(improved.verilog_code, improved.testbench_code)
    duration_ms = round((time.perf_counter() - t0) * 1000)

    return {
        "round": round_num,
        "mode": active_mode,
        "model": MODELS["improve"],
        "fix_summary": improved.fix_summary,
        "verilog_code": improved.verilog_code,
        "testbench_code": improved.testbench_code,
        "test_result": new_test,
        "passed": new_test["passed"],
        "duration_ms": duration_ms,
    }


def run_improve_loop(
    *,
    verilog_code: str,
    testbench_code: str,
    initial_test: Dict[str, Any],
    circuit_name: str = "",
    design_summary: str = "",
    max_rounds: Optional[int] = None,
    on_round: Optional[Callable[[Dict[str, Any]], None]] = None,
) -> Dict[str, Any]:
    """Run up to `max_rounds` improvement iterations until tests pass."""
    limit = max_rounds if max_rounds is not None else IMPROVE_CONFIG["max_rounds"]
    rounds: List[Dict[str, Any]] = []

    current_verilog = verilog_code
    current_tb = testbench_code
    current_test = initial_test

    if current_test.get("passed"):
        return {
            "ran": False,
            "reason": "Initial design already passed all tests.",
            "rounds": rounds,
            "final_verilog": current_verilog,
            "final_testbench": current_tb,
            "final_test": current_test,
        }

    for r in range(1, limit + 1):
        round_data = run_improve_round(
            round_num=r,
            verilog_code=current_verilog,
            testbench_code=current_tb,
            test_result=current_test,
            circuit_name=circuit_name,
            design_summary=design_summary,
        )
        rounds.append(round_data)
        current_verilog = round_data["verilog_code"]
        current_tb = round_data["testbench_code"]
        current_test = round_data["test_result"]

        if on_round:
            on_round(round_data)

        if round_data["passed"]:
            break

    return {
        "ran": True,
        "reason": (
            f"Passed on round {len(rounds)}."
            if current_test.get("passed")
            else f"Still failing after {len(rounds)} round(s)."
        ),
        "rounds": rounds,
        "final_verilog": current_verilog,
        "final_testbench": current_tb,
        "final_test": current_test,
    }
