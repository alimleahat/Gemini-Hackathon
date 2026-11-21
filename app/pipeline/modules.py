"""Module Library & Hierarchy Manager.

The app (not the model) stores saved reusable Verilog modules in
`app/runs/module_library.json` and supports saving/loading the library as a
portable JSON file.

- Save a module: generates a standalone Verilog-2005 module + standalone
  self-checking testbench, tests it on its own with Icarus Verilog, and stores
  its ports, Verilog, test status, and schematic snapshot.
- Use a module: module names + input/output signatures are passed with every
  live camera frame, and full module Verilog is passed to `gemini-4-neon` during
  final hardware generation so hierarchical instantiation compiles cleanly.
"""

import json
import os
import re
import subprocess
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

from app.config import MODELS, RUNS_DIR, TEST_CONFIG
from app.pipeline.client import get_client
from app.pipeline.tester import _strip_code_fences

LIBRARY_PATH = RUNS_DIR / "module_library.json"


class ModulePort(BaseModel):
    name: str = Field(description="Port name, e.g. 'a', 'b', 'sum', 'cout'.")
    width: int = Field(default=1, description="Bit width (1 for scalar, 4 for [3:0], etc.).")


class GeneratedStandaloneModule(BaseModel):
    verilog_module_name: str = Field(
        description="Valid lowercase Verilog identifier for the module, e.g. 'half_adder'."
    )
    description: str = Field(
        description="1-2 sentence plain-English description of what this reusable module does."
    )
    inputs: List[ModulePort] = Field(description="List of module input ports.")
    outputs: List[ModulePort] = Field(description="List of module output ports.")
    verilog_code: str = Field(
        description="Complete standalone Verilog-2005 module definition `module <name>(...); ... endmodule` (do NOT wrap in `module top`)."
    )
    testbench_code: str = Field(
        description="Complete self-checking Verilog testbench `module tb;` that instantiates `<name>`, prints `PASS` or `FAIL`, and calls `$finish;`."
    )


MODULE_SYSTEM_INSTRUCTION = """You are an expert Verilog hardware engineer creating a reusable submodule for a module library.

RULES:
1. Create a clean, synthesizable Verilog-2005 module with the exact requested `verilog_module_name`.
2. Do NOT wrap it in `module top` or Basys 3 board pins — expose ONLY the logical input/output ports of the drawn circuit (e.g. `a`, `b`, `sum`, `cout`, `clk`, `rst`, etc.).
3. Avoid SystemVerilog-only features (`logic`, `always_ff`, `always_comb`) so it compiles in both `iverilog` and `yosys`.
4. If the drawn module instantiates any already-saved modules from the library, instantiate them by their `verilog_module_name` (the library will compile them alongside this module — do NOT redefine already-saved modules inside `verilog_code`).
5. Write a thorough self-checking testbench `module tb;` in `testbench_code` that prints `PASS` if all checks pass or `FAIL: <reason>` on error, and always calls `$finish;`.
"""


def sanitize_module_name(raw_name: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9_]+", "_", raw_name.strip().lower()).strip("_")
    if not cleaned:
        cleaned = "custom_mod"
    if cleaned[0].isdigit():
        cleaned = f"m_{cleaned}"
    if cleaned in ("top", "tb", "module", "wire", "reg", "input", "output"):
        cleaned = f"{cleaned}_mod"
    return cleaned


def test_standalone_module(
    verilog_code: str,
    testbench_code: str,
    dependency_verilogs: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """Compile and simulate a standalone module + its testbench with Icarus Verilog."""
    t0 = time.perf_counter()
    with tempfile.TemporaryDirectory(prefix="fpga_mod_") as tmpdir:
        files = []
        for idx, dep in enumerate(dependency_verilogs or []):
            dep_path = os.path.join(tmpdir, f"dep_{idx}.v")
            with open(dep_path, "w", encoding="utf-8") as f:
                f.write(_strip_code_fences(dep))
            files.append(dep_path)

        mod_path = os.path.join(tmpdir, "mod.v")
        tb_path = os.path.join(tmpdir, "tb.v")
        vvp_path = os.path.join(tmpdir, "mod.vvp")

        with open(mod_path, "w", encoding="utf-8") as f:
            f.write(_strip_code_fences(verilog_code))
        with open(tb_path, "w", encoding="utf-8") as f:
            f.write(_strip_code_fences(testbench_code))
        files.extend([mod_path, tb_path])

        comp = subprocess.run(
            ["iverilog", "-g2012", "-o", vvp_path, *files],
            capture_output=True,
            text=True,
            timeout=TEST_CONFIG["compile_timeout_sec"],
        )
        if comp.returncode != 0:
            return {
                "passed": False,
                "compile_ok": False,
                "stdout": comp.stdout.strip(),
                "stderr": (comp.stderr or comp.stdout).strip(),
                "summary": "Module failed to compile",
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }

        try:
            sim = subprocess.run(
                ["vvp", vvp_path],
                capture_output=True,
                text=True,
                timeout=TEST_CONFIG["sim_timeout_sec"],
            )
        except subprocess.TimeoutExpired:
            return {
                "passed": False,
                "compile_ok": True,
                "stdout": "",
                "stderr": "Module testbench timed out.",
                "summary": "Module simulation timed out",
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }

        stdout = sim.stdout.strip()
        stderr = sim.stderr.strip()
        combined = f"{stdout}\n{stderr}"
        has_fail = bool(re.search(r"\b(FAIL|ERROR)\b", combined, re.IGNORECASE))
        has_pass = bool(re.search(r"\bPASS\b", stdout, re.IGNORECASE))
        passed = sim.returncode == 0 and not has_fail and has_pass

        return {
            "passed": passed,
            "compile_ok": True,
            "stdout": stdout,
            "stderr": stderr,
            "summary": "Module passed standalone tests" if passed else "Module testbench failed",
            "duration_ms": round((time.perf_counter() - t0) * 1000),
        }


class ModuleLibrary:
    """Thread-safe persistent store of reusable Verilog modules."""

    def __init__(self, path: Path = LIBRARY_PATH) -> None:
        self._path = path
        self._lock = threading.Lock()
        self._modules: Dict[str, Dict[str, Any]] = {}
        self._load()

    def _load(self) -> None:
        if not self._path.exists():
            return
        try:
            data = json.loads(self._path.read_text(encoding="utf-8"))
            items = data.get("modules", []) if isinstance(data, dict) else data
            for m in items:
                if isinstance(m, dict) and m.get("name"):
                    self._modules[m["name"]] = m
        except Exception:
            pass

    def _save(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "version": 1,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            "modules": list(self._modules.values()),
        }
        self._path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    def list_modules(self) -> List[Dict[str, Any]]:
        with self._lock:
            return list(self._modules.values())

    def delete_module(self, name: str) -> bool:
        with self._lock:
            removed = self._modules.pop(name, None) is not None
            if removed:
                self._save()
            return removed

    def import_library(self, raw_data: Any, replace: bool = False) -> List[Dict[str, Any]]:
        items = raw_data.get("modules", []) if isinstance(raw_data, dict) else raw_data
        if not isinstance(items, list):
            raise ValueError("Library file must contain a list of modules or {'modules': [...]}.")
        with self._lock:
            if replace:
                self._modules.clear()
            for m in items:
                if isinstance(m, dict) and m.get("name") and m.get("verilog_code"):
                    self._modules[str(m["name"])] = m
            self._save()
            return list(self._modules.values())

    def create_and_save_module(
        self,
        *,
        name: str,
        image_b64: Optional[str] = None,
        mime_type: Optional[str] = None,
        schematic_json: Optional[Dict[str, Any]] = None,
        text_prompt: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Generate a standalone Verilog module, test it on its own, and save to the library."""
        t0 = time.perf_counter()
        display_name = name.strip()
        if not display_name:
            raise ValueError("Module name is required.")
        v_mod_name = sanitize_module_name(display_name)

        existing = self.list_modules()
        dep_verilogs = [
            m["verilog_code"]
            for m in existing
            if m.get("verilog_module_name") != v_mod_name and m.get("verilog_code")
        ]

        client = get_client()
        input_blocks = []
        if image_b64:
            input_blocks.append(
                {"type": "image", "data": image_b64, "mime_type": mime_type or "image/jpeg"}
            )

        lines = [
            f"Create a standalone reusable Verilog-2005 module named `{v_mod_name}` (display name: `{display_name}`).",
            "If there is a box drawn around gates with this name in a corner, implement the circuit INSIDE that box.",
        ]
        if text_prompt and text_prompt.strip():
            lines.append(f"Additional description: {text_prompt.strip()}")
        if schematic_json:
            lines.append("Extracted schematic JSON:\n" + json.dumps(schematic_json, indent=2))
        if existing:
            lines.append("Existing saved modules you may instantiate if referenced:")
            for m in existing:
                ins = ", ".join(p["name"] for p in m.get("inputs", []))
                outs = ", ".join(p["name"] for p in m.get("outputs", []))
                lines.append(f"- `{m['verilog_module_name']}` (display: `{m['name']}`, in: [{ins}], out: [{outs}])")

        input_blocks.append({"type": "text", "text": "\n\n".join(lines)})

        interaction = client.interactions.create(
            model=MODELS["generate"],
            system_instruction=MODULE_SYSTEM_INSTRUCTION,
            input=input_blocks,
            response_format={
                "type": "text",
                "mime_type": "application/json",
                "schema": GeneratedStandaloneModule.model_json_schema(),
            },
        )
        gen = GeneratedStandaloneModule.model_validate_json(interaction.output_text)

        verilog_code = gen.verilog_code
        tb_code = gen.testbench_code
        test_res = test_standalone_module(verilog_code, tb_code, dep_verilogs)

        # Up to 2 automatic fix attempts with gemini-4-hydrogen if standalone test fails
        fix_rounds = 0
        while not test_res["passed"] and fix_rounds < 2:
            fix_rounds += 1
            fix_prompt = (
                f"Fix the standalone Verilog module `{gen.verilog_module_name}` and its testbench.\n\n"
                f"--- mod.v ---\n{verilog_code}\n\n"
                f"--- tb.v ---\n{tb_code}\n\n"
                f"--- Icarus Verilog Error ---\nSTDOUT:\n{test_res['stdout']}\nSTDERR:\n{test_res['stderr']}"
            )
            fix_inter = client.interactions.create(
                model=MODELS["improve"],
                system_instruction=MODULE_SYSTEM_INSTRUCTION,
                input=fix_prompt,
                response_format={
                    "type": "text",
                    "mime_type": "application/json",
                    "schema": GeneratedStandaloneModule.model_json_schema(),
                },
            )
            fixed = GeneratedStandaloneModule.model_validate_json(fix_inter.output_text)
            verilog_code = fixed.verilog_code
            tb_code = fixed.testbench_code
            gen = fixed
            test_res = test_standalone_module(verilog_code, tb_code, dep_verilogs)

        entry = {
            "name": display_name,
            "verilog_module_name": sanitize_module_name(gen.verilog_module_name or v_mod_name),
            "description": gen.description,
            "inputs": [p.model_dump() for p in gen.inputs],
            "outputs": [p.model_dump() for p in gen.outputs],
            "verilog_code": verilog_code,
            "testbench_code": tb_code,
            "test_result": test_res,
            "test_passed": test_res["passed"],
            "fix_rounds": fix_rounds,
            "schematic_json": schematic_json,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "duration_ms": round((time.perf_counter() - t0) * 1000),
        }

        with self._lock:
            self._modules[display_name] = entry
            self._save()

        return entry


module_library = ModuleLibrary()
