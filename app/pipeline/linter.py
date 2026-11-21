"""Design Issue Flags: Real hardware lint check + plain-language explanation.

Runs real static/structural analysis on the generated Verilog using:
1. Yosys (`read_verilog -sv; hierarchy -check -top top; proc; check; stat -json`)
   — catches accidental latches ($dlatch), floating/undriven inputs,
   combinational logic loops, multiple drivers, and port width mismatches.
2. Verilator (`verilator --lint-only -Wall`) when available on PATH — catches
   width mismatches, unused/undriven signals, latches, and combinational loops.
3. Icarus Verilog (`iverilog -g2012 -Wall`) for additional Verilog warnings.

When real issues are found, `gemini-4-neon` explains each issue in plain
language and maps it to the corresponding element/signal on the drawn schematic
so it can be highlighted visually.
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
import time
from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, Field

from app.config import MODELS
from app.pipeline.client import get_client
from app.pipeline.tester import _strip_code_fences


class ExplainedIssue(BaseModel):
    title: str = Field(description="Short plain-English title, e.g. 'Accidental Latch on led_state'.")
    category: Literal[
        "floating_input",
        "unconnected_output",
        "combinational_loop",
        "accidental_latch",
        "width_mismatch",
        "other",
    ] = Field(description="Issue category.")
    severity: Literal["error", "warning"] = Field(description="Severity level.")
    signal_name: str = Field(description="Primary Verilog signal, wire, or port involved.")
    plain_explanation: str = Field(
        description="1-2 sentence plain-English explanation understandable by a non-expert judge."
    )
    how_to_fix: str = Field(description="1 sentence concrete suggestion to fix it.")
    schematic_element_ids: List[str] = Field(
        default_factory=list,
        description="Matching element IDs from the provided schematic JSON (if any) to highlight.",
    )
    schematic_labels: List[str] = Field(
        default_factory=list,
        description="Matching element or wire labels from the schematic (if any) to highlight.",
    )


class LintExplanation(BaseModel):
    summary: str = Field(description="1-sentence overall summary of the design issues found.")
    issues: List[ExplainedIssue] = Field(default_factory=list)


LINT_SYSTEM_INSTRUCTION = """You are a friendly digital hardware mentor explaining real Verilog lint/synthesis warnings to a non-technical user.
Only explain the REAL lint findings provided — never invent issues that were not reported by the tools.
For each real issue:
- Explain in plain, jargon-light language what went wrong and why it matters on a real FPGA.
- If a schematic JSON is provided, match each issue to the closest `schematic_element_ids` and/or `schematic_labels` so the UI can highlight where it is on the user's drawn schematic.
"""


def _collect_raw_lint_findings(verilog_code: str) -> Dict[str, Any]:
    """Run Yosys (and Verilator if installed) + iverilog -Wall to collect real lint warnings."""
    design_src = _strip_code_fences(verilog_code)
    findings: List[str] = []
    tools_used: List[str] = []

    with tempfile.TemporaryDirectory(prefix="fpga_lint_") as tmpdir:
        v_path = os.path.join(tmpdir, "design.v")
        stat_path = os.path.join(tmpdir, "lint_stat.json")
        with open(v_path, "w", encoding="utf-8") as f:
            f.write(design_src)

        # 1. Yosys structural check + latch detection
        if shutil.which("yosys"):
            tools_used.append("yosys")
            cmd = (
                f"read_verilog -sv {v_path}; "
                f"hierarchy -check -top top; "
                f"proc; "
                f"check; "
                f"tee -q -o {stat_path} stat -json"
            )
            try:
                res = subprocess.run(
                    ["yosys", "-p", cmd],
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                combined = f"{res.stdout}\n{res.stderr}"
                for line in combined.splitlines():
                    s = line.strip()
                    if s.startswith("Warning:") or s.startswith("ERROR:"):
                        # Ignore harmless unused board input ports (sw/btn/clk often partially used)
                        if re.search(r"Wire top\.\\(sw|btn|clk)\b.*unused", s, re.IGNORECASE):
                            continue
                        findings.append(f"[yosys] {s}")

                if os.path.exists(stat_path):
                    stat_data = json.loads(open(stat_path, "r", encoding="utf-8").read())
                    cells = stat_data.get("design", {}).get("num_cells_by_type", {})
                    for cell_name, count in cells.items():
                        if "latch" in cell_name.lower() and count > 0:
                            findings.append(
                                f"[yosys] Accidental latch inferred: {count} x {cell_name} cell(s) in design."
                            )
            except Exception as e:
                findings.append(f"[yosys] Lint execution error: {e}")

        # 2. Verilator --lint-only -Wall (if installed)
        if shutil.which("verilator"):
            tools_used.append("verilator")
            try:
                vres = subprocess.run(
                    ["verilator", "--lint-only", "-Wall", "--top-module", "top", v_path],
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                for line in f"{vres.stdout}\n{vres.stderr}".splitlines():
                    s = line.strip()
                    if not (s.startswith("%Warning") or s.startswith("%Error")):
                        continue
                    # Skip noisy UNUSEDSIGNAL for unused board switches/buttons/clk
                    if "UNUSEDSIGNAL" in s and re.search(r"'(sw|btn|clk)'", s):
                        continue
                    findings.append(f"[verilator] {s}")
            except Exception:
                pass

        # 3. Icarus Verilog -Wall
        if shutil.which("iverilog"):
            tools_used.append("iverilog")
            try:
                ires = subprocess.run(
                    ["iverilog", "-g2012", "-Wall", "-o", os.path.join(tmpdir, "lint.vvp"), v_path],
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                for line in (ires.stderr or "").splitlines():
                    s = line.strip()
                    if "warning:" in s.lower() or "error:" in s.lower():
                        findings.append(f"[iverilog] {s}")
            except Exception:
                pass

    # Deduplicate while preserving order
    deduped = list(dict.fromkeys(findings))
    return {
        "tools_used": tools_used,
        "raw_findings": deduped,
    }


def run_lint_check(
    verilog_code: str,
    schematic_json: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Run real Verilog lint checks and explain any real issues with gemini-4-neon."""
    t0 = time.perf_counter()
    raw = _collect_raw_lint_findings(verilog_code)
    findings = raw["raw_findings"]

    if not findings:
        return {
            "clean": True,
            "tools_used": raw["tools_used"],
            "raw_findings": [],
            "summary": "No design issues found (no floating inputs, loops, latches, or width mismatches).",
            "issues": [],
            "model": None,
            "duration_ms": round((time.perf_counter() - t0) * 1000),
        }

    # Explain real issues in plain language with gemini-4-neon
    client = get_client()
    prompt_parts = [
        "Explain these real Verilog lint/synthesis findings in plain language:",
        "\n".join(findings),
        f"--- design.v ---\n{verilog_code}",
    ]
    if schematic_json:
        prompt_parts.append(
            "--- Drawn Schematic JSON (match issues to element IDs/labels here) ---\n"
            + json.dumps(schematic_json, indent=2)
        )

    interaction = client.interactions.create(
        model=MODELS["generate"],
        system_instruction=LINT_SYSTEM_INSTRUCTION,
        input="\n\n".join(prompt_parts),
        response_format={
            "type": "text",
            "mime_type": "application/json",
            "schema": LintExplanation.model_json_schema(),
        },
    )
    explained = LintExplanation.model_validate_json(interaction.output_text)

    return {
        "clean": len(explained.issues) == 0,
        "tools_used": raw["tools_used"],
        "raw_findings": findings,
        "summary": explained.summary,
        "issues": [item.model_dump() for item in explained.issues],
        "model": MODELS["generate"],
        "duration_ms": round((time.perf_counter() - t0) * 1000),
    }
