"""Step 3: Verilog & Testbench Generation powered by gemini-4-neon.

Reads the hand-drawn circuit image (or typed description) and produces:
- Synthesizable Verilog wrapped in the fixed virtual FPGA board top module:
    module top(
        input clk,
        input [15:0] sw,
        input [4:0] btn,
        output [15:0] led,
        output [6:0] seg,
        output [3:0] an
    );
- A self-checking Icarus Verilog testbench (`module tb;`).
- A clear board pin mapping explanation for the user & judges.
"""

import time
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field

from app.config import MODELS
from app.pipeline.client import get_client


class PinMappingItem(BaseModel):
    board_pin: str = Field(
        description="Board pin name, e.g. 'sw[0]', 'sw[3:0]', 'btn[0]', 'led[0]', 'led[7:0]', 'seg[6:0] / an[3:0]'."
    )
    signal_name: str = Field(
        description="Logical signal name from the circuit diagram, e.g. 'A', 'Reset', 'Sum', 'Count'."
    )
    direction: str = Field(
        description="Either 'input' or 'output'."
    )
    description: str = Field(
        description="Short plain-English description of what flipping/watching this pin does."
    )


class GeneratedDesign(BaseModel):
    circuit_name: str = Field(
        description="Short, clear title for the recognized circuit (e.g. '4-Bit Ripple Counter', 'Full Adder')."
    )
    design_summary: str = Field(
        description="2-3 sentence plain-English explanation of what was recognized and how it works on the board."
    )
    is_clocked: bool = Field(
        description="True if the circuit uses the clk signal (counters, FSMs, shift registers, etc.); False if purely combinational."
    )
    recommended_clock_hz: int = Field(
        description="Recommended virtual board clock rate in Hz (1 to 15) for visibly observing clocked behavior. Use 2-4 for counters/FSMs, 1 for combinational."
    )
    pin_mapping: List[PinMappingItem] = Field(
        description="Complete mapping between the circuit's logical signals and the virtual board pins."
    )
    verilog_code: str = Field(
        description="Complete, self-contained, synthesizable Verilog-2005 code containing `module top(...)` and any helper submodules."
    )
    testbench_code: str = Field(
        description="Complete, self-checking Verilog testbench `module tb;` that instantiates `top`, tests key cases, prints `PASS` on success or `FAIL: <reason>` on failure, and calls `$finish;`."
    )


SYSTEM_INSTRUCTION = """You are an expert digital hardware and FPGA engineer.
Your job is to inspect a hand-drawn circuit diagram (or text specification) and implement it in clean, synthesizable Verilog-2005 for a virtual FPGA board.

MANDATORY TOP-LEVEL INTERFACE (exact module name and port names/widths):
```verilog
module top(
    input clk,
    input [15:0] sw,
    input [4:0] btn,
    output [15:0] led,
    output [6:0] seg,
    output [3:0] an
);
```

CRITICAL RULES FOR THE VIRTUAL BOARD:
1. `module top` MUST have the exact 6 ports above: `clk`, `sw[15:0]`, `btn[4:0]`, `led[15:0]`, `seg[6:0]`, `an[3:0]`. Put the core user circuit in a clean helper submodule (e.g. `module user_circuit(...)`) instantiated inside `module top` so the user's circuit can also be synthesized separately from the board wrapper.
2. **NO 100 MHz clock dividers!** The virtual board ticks `clk` directly at ~2 to 10 Hz so judges can watch clocked circuits live. Use `clk` directly for counters/FSMs/shift registers (never divide by 50,000,000 or 100,000,000!).
3. **Reset & Initialization**: Initialize all state registers to 0 (e.g. `reg [3:0] count = 4'd0;`) AND wire `btn[0]` (Center button) as a synchronous active-high reset for sequential designs so there are never `X` (unknown) values.
4. **Drive ALL outputs**: Never leave `led`, `seg`, or `an` undriven (`z`/`x`). Set unused `led` bits to `0`.
5. **7-Segment Display (`seg[6:0]`, `an[3:0]`)**:
   - Both `seg` and `an` are **active-low** (0 = ON, 1 = OFF).
   - `seg[0]=a` (top), `seg[1]=b` (top-right), `seg[2]=c` (bottom-right), `seg[3]=d` (bottom), `seg[4]=e` (bottom-left), `seg[5]=f` (top-left), `seg[6]=g` (middle).
   - For example, digit `0` is `7'b1000000`, digit `1` is `7'b1111001`, digit `8` is `7'b0000000`, blank is `7'b1111111`.
   - `an[0]` is the rightmost digit, `an[3]` is the leftmost digit. `an = 4'b1110` lights digit 0.
   - If the circuit outputs a numeric value (adder sum, counter value, ALU result, FSM state), show it on the 7-segment display in addition to LEDs! If not using the 7-segment display, set `an = 4'b1111; seg = 7'b1111111;`.
6. **Buttons (`btn[4:0]`)**: `btn[0]`=Center, `btn[1]`=Up, `btn[2]`=Left, `btn[3]`=Right, `btn[4]`=Down. All active-high when pressed.
7. **Verilog-2005 & Yosys compatibility**:
   - Write standard synthesizable Verilog-2005 that compiles cleanly in BOTH `iverilog` AND `yosys synth_xilinx`.
   - Avoid SystemVerilog-only features like `logic`, `always_ff`, `always_comb`, `enum`, or unpacked array ports.
   - In Icarus Verilog, `always @(*)` may not trigger at `t=0` for initialized registers until a signal changes; drive combinational outputs (like `seg`) with `assign` or give the combinational `reg` a matching default initializer, and assert synchronous reset (`btn[0]=1` for 1 clock edge) at the start of `tb.v`.
   - Do NOT put `module tb` inside `verilog_code` — keep `verilog_code` strictly synthesizable hardware and put `module tb` only in `testbench_code`.
8. **Self-checking testbench (`testbench_code`)**:
   - Instantiate `top dut(.clk(clk), .sw(sw), .btn(btn), .led(led), .seg(seg), .an(an));`.
   - Do NOT include `verilog_code` inside `testbench_code` (they are compiled together as separate files: `iverilog design.v tb.v`).
   - Test all key input combinations or clock sequences thoroughly.
   - Track an `integer errors = 0;` counter; on mismatch print `$display("FAIL: ..."); errors = errors + 1;`.
   - At the end: if `errors == 0` print `$display("PASS");` else `$display("FAIL: %0d errors", errors);`, then call `$finish;`.
   - Ensure the testbench ALWAYS terminates via `$finish;` within a few thousand time units (no infinite loops).
"""


def run_generate(
    *,
    image_b64: Optional[str] = None,
    mime_type: Optional[str] = None,
    text_prompt: Optional[str] = None,
    circuit_type: Optional[str] = None,
    schematic_json: Optional[Dict[str, Any]] = None,
    saved_modules: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """Generate top-level Verilog, testbench, and pin mapping from image/text."""
    import json as _json

    t0 = time.perf_counter()
    client = get_client()

    input_blocks = []
    if image_b64:
        input_blocks.append(
            {
                "type": "image",
                "data": image_b64,
                "mime_type": mime_type or "image/jpeg",
            }
        )

    prompt_lines = [
        "Analyze this digital circuit and generate the complete Verilog implementation (`module top`), "
        "a thorough self-checking testbench (`module tb`), and a clear virtual FPGA board pin mapping."
    ]
    if circuit_type:
        prompt_lines.append(f"Detected circuit category: {circuit_type}.")
    if text_prompt and text_prompt.strip():
        prompt_lines.append(f"User description / notes: {text_prompt.strip()}")
    if schematic_json:
        prompt_lines.append(
            "Structured schematic extracted during live camera mirroring (use this alongside the image):\n"
            + _json.dumps(schematic_json, indent=2)
        )
    if saved_modules:
        mod_sections = [
            "SAVED MODULE LIBRARY (if the diagram instantiates any of these modules by name, "
            "instantiate them inside `module top` AND include their module definitions verbatim in `verilog_code` "
            "so `design.v` compiles cleanly on its own):"
        ]
        for m in saved_modules:
            ins = ", ".join(p["name"] for p in m.get("inputs", []))
            outs = ", ".join(p["name"] for p in m.get("outputs", []))
            mod_sections.append(
                f"### Module `{m['verilog_module_name']}` (display name: `{m['name']}`, inputs: [{ins}], outputs: [{outs}])\n"
                f"```verilog\n{m.get('verilog_code', '')}\n```"
            )
        prompt_lines.append("\n\n".join(mod_sections))

    prompt_lines.append(
        "Remember: keep `module top` strictly matching `(clk, sw[15:0], btn[4:0], led[15:0], seg[6:0], an[3:0])`, "
        "no 100MHz clock dividers, initialize registers to 0, and write standard Verilog-2005."
    )

    input_blocks.append({"type": "text", "text": "\n".join(prompt_lines)})

    interaction = client.interactions.create(
        model=MODELS["generate"],
        system_instruction=SYSTEM_INSTRUCTION,
        input=input_blocks,
        response_format={
            "type": "text",
            "mime_type": "application/json",
            "schema": GeneratedDesign.model_json_schema(),
        },
    )

    design = GeneratedDesign.model_validate_json(interaction.output_text)
    duration_ms = round((time.perf_counter() - t0) * 1000)

    return {
        "model": MODELS["generate"],
        "circuit_name": design.circuit_name,
        "design_summary": design.design_summary,
        "is_clocked": design.is_clocked,
        "recommended_clock_hz": max(1, min(15, design.recommended_clock_hz)),
        "pin_mapping": [item.model_dump() for item in design.pin_mapping],
        "verilog_code": design.verilog_code,
        "testbench_code": design.testbench_code,
        "duration_ms": duration_ms,
    }
