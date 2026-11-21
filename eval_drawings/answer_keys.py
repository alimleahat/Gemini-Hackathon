"""Answer-Key Testbench Runner & Strict Label-Based Port Mapper.

Supports evaluating BOTH:
1. Standalone Verilog modules (e.g. baseline single-call Neon output like
   `module half_adder(input A, input B, output S, output C)`).
2. Virtual FPGA board-wrapped designs (`module top(clk, sw[15:0], btn[4:0],
   led[15:0], seg[6:0], an[3:0])`) using the run's `pin_mapping`.

STRICT POLICY:
Map ports ONLY by matching drawn/declared signal labels and widths.
If any required port cannot be unambiguously matched, report
`status = "ambiguous_ports"` with details rather than guessing.
"""

import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

CIRCUIT_ORDER = [
    "half_adder",
    "full_adder",
    "adder_4bit",
    "adder_4bit_7seg",
    "counter_4bit",
]

# Synonym tables for matching drawn labels / Verilog port names
ROLE_ALIASES: Dict[str, List[str]] = {
    "a": ["a", "in_a", "ina", "op_a", "opa", "x", "in0", "a_in", "ain", "operand_a"],
    "b": ["b", "in_b", "inb", "op_b", "opb", "y", "in1", "b_in", "bin", "operand_b"],
    "cin": ["cin", "c_in", "carry_in", "carryin", "ci"],
    "sum": ["sum", "s", "s_out", "sout", "out", "result", "y_sum"],
    "cout": ["cout", "c_out", "carry", "carry_out", "carryout", "co", "c"],
    "clk": ["clk", "clock", "sys_clk", "i_clk"],
    "rst": ["rst", "reset", "rst_n", "rstn", "reset_n", "resetn", "clr", "clear"],
    "en": ["en", "enable", "ce", "cnt_en", "count_en"],
    "count": ["count", "cnt", "q", "out", "val", "value", "counter", "count_out"],
    "seg": ["seg", "segs", "seven_seg", "sseg", "cathode", "ca_cg"],
    "an": ["an", "anode", "anodes", "digit_en"],
}

# Active-low 7-segment encodings (bit 0=a .. bit 6=g, 0=ON, 1=OFF)
HEX_TO_SEG_VERILOG = """
  function [6:0] hex_to_seg;
    input [3:0] val;
    begin
      case (val)
        4'h0: hex_to_seg = 7'b1000000;
        4'h1: hex_to_seg = 7'b1111001;
        4'h2: hex_to_seg = 7'b0100100;
        4'h3: hex_to_seg = 7'b0110000;
        4'h4: hex_to_seg = 7'b0011001;
        4'h5: hex_to_seg = 7'b0010010;
        4'h6: hex_to_seg = 7'b0000010;
        4'h7: hex_to_seg = 7'b1111000;
        4'h8: hex_to_seg = 7'b0000000;
        4'h9: hex_to_seg = 7'b0010000;
        4'hA: hex_to_seg = 7'b0001000;
        4'hB: hex_to_seg = 7'b0000011;
        4'hC: hex_to_seg = 7'b1000110;
        4'hD: hex_to_seg = 7'b0100001;
        4'hE: hex_to_seg = 7'b0000110;
        4'hF: hex_to_seg = 7'b0001110;
      endcase
    end
  endfunction
"""


def strip_code_fences(code: str) -> str:
    text = (code or "").strip()
    blocks = re.findall(r"```(?:systemverilog|verilog|sv)?\s*\n(.*?)```", text, flags=re.DOTALL | re.IGNORECASE)
    if blocks:
        for b in blocks:
            if re.search(r"\bmodule\s+\w+", b):
                return b.strip() + "\n"
        return blocks[-1].strip() + "\n"
    return text + "\n"


def inspect_verilog_ports(verilog_code: str) -> Tuple[Optional[str], Optional[List[Dict[str, Any]]], str]:
    """Use Yosys write_json to inspect top module name and exact port directions/widths."""
    src = strip_code_fences(verilog_code)
    cleaned = re.sub(r"//.*", "", src)
    cleaned = re.sub(r"/\*.*?\*/", "", cleaned, flags=re.DOTALL)
    mod_names = re.findall(r"\bmodule\s+([a-zA-Z_][a-zA-Z0-9_$]*)", cleaned)
    if not mod_names:
        return None, None, "No `module` declaration found in Verilog."

    # Prefer `top` if present, otherwise last declared module
    top_name = "top" if "top" in mod_names else mod_names[-1]

    with tempfile.TemporaryDirectory(prefix="ak_ports_") as tmpdir:
        v_path = os.path.join(tmpdir, "dut.v")
        j_path = os.path.join(tmpdir, "dut.json")
        with open(v_path, "w", encoding="utf-8") as f:
            f.write(src)
        script = f"read_verilog -sv {v_path}; hierarchy -check -top {top_name}; proc; write_json {j_path}"
        proc = subprocess.run(["yosys", "-q", "-p", script], capture_output=True, text=True, timeout=20)
        if proc.returncode != 0 or not os.path.exists(j_path):
            return top_name, None, (proc.stderr or proc.stdout)[-400:].strip()

        data = json.loads(Path(j_path).read_text(encoding="utf-8"))
        mod = data.get("modules", {}).get(top_name)
        if not mod:
            return top_name, None, f"Module {top_name} not found after hierarchy."
        ports = [
            {
                "name": pname,
                "direction": pinfo.get("direction", "input"),
                "width": len(pinfo.get("bits", [])),
            }
            for pname, pinfo in mod.get("ports", {}).items()
        ]
        return top_name, ports, ""


def _norm(name: str) -> str:
    n = re.sub(r"\[[^\]]*\]", "", (name or "").strip().lower())
    n = re.sub(r"[^a-z0-9_]+", "_", n).strip("_")
    return n


def _is_board_top(top_name: str, ports: List[Dict[str, Any]]) -> bool:
    if top_name != "top":
        return False
    pnames = {p["name"] for p in ports}
    return {"clk", "sw", "btn", "led", "seg", "an"}.issubset(pnames)


def _match_role_standalone(
    ports: List[Dict[str, Any]],
    role: str,
    direction: str,
    expected_width: Optional[int],
    used: set,
) -> Tuple[Optional[Dict[str, Any]], str]:
    aliases = ROLE_ALIASES.get(role, [role])
    cands = [
        p for p in ports
        if p["direction"] == direction
        and p["name"] not in used
        and (expected_width is None or p["width"] == expected_width)
    ]

    # Exact alias match first
    exact = [p for p in cands if _norm(p["name"]) in aliases]
    if len(exact) == 1:
        return exact[0], ""
    if len(exact) > 1:
        return None, f"Ambiguous match for '{role}': {[p['name'] for p in exact]}"

    # Substring match (e.g. 'a_in_4bit' contains 'a_in')
    sub = [
        p for p in cands
        if any(len(al) >= 2 and al in _norm(p["name"]) for al in aliases)
    ]
    if len(sub) == 1:
        return sub[0], ""
    if len(sub) > 1:
        return None, f"Ambiguous substring match for '{role}': {[p['name'] for p in sub]}"

    return None, f"No matching {direction} port (width={expected_width}) for '{role}' in {[p['name'] for p in cands]}"


def _parse_board_pin_slice(board_pin: str) -> Optional[Tuple[str, int, int]]:
    """Parse 'sw[0]' -> ('sw', 0, 0), 'sw[3:0]' -> ('sw', 3, 0), 'led[7:4]' -> ('led', 7, 4)."""
    m = re.search(r"\b(sw|btn|led|seg|an)\s*\[\s*(\d+)\s*(?::\s*(\d+)\s*)?\]", board_pin or "", re.IGNORECASE)
    if not m:
        return None
    bus = m.group(1).lower()
    hi = int(m.group(2))
    lo = int(m.group(3)) if m.group(3) is not None else hi
    return bus, max(hi, lo), min(hi, lo)


def _match_role_board_top(
    pin_mapping: List[Dict[str, Any]],
    role: str,
    direction: str,
    expected_width: int,
) -> Tuple[Optional[str], str]:
    """Match a logical role to a Basys-3 board pin expression like `sw[3:0]` or `led[0]`."""
    aliases = ROLE_ALIASES.get(role, [role])
    if role == "seg":
        return "seg[6:0]", ""
    if role == "an":
        return "an[3:0]", ""
    if role == "clk":
        return "clk", ""

    matches = []
    for item in pin_mapping or []:
        if (item.get("direction") or "").lower() != direction:
            continue
        sig_norm = _norm(item.get("signal_name", ""))
        desc_norm = _norm(item.get("description", ""))
        parsed = _parse_board_pin_slice(item.get("board_pin", ""))
        if not parsed:
            continue
        bus, hi, lo = parsed
        width = hi - lo + 1
        if width != expected_width:
            continue
        expr = f"{bus}[{hi}:{lo}]" if hi != lo else f"{bus}[{hi}]"
        if sig_norm in aliases:
            matches.append((2, expr, item.get("signal_name")))
        elif any(len(al) >= 2 and (al in sig_norm or al in desc_norm) for al in aliases):
            matches.append((1, expr, item.get("signal_name")))

    if not matches:
        return None, f"No pin_mapping entry for '{role}' ({direction}, width={expected_width})"

    # Prefer exact signal_name matches over description matches
    best_score = max(m[0] for m in matches)
    top_matches = [m for m in matches if m[0] == best_score]
    unique_exprs = list(dict.fromkeys(m[1] for m in top_matches))
    if len(unique_exprs) == 1:
        return unique_exprs[0], ""
    return None, f"Ambiguous board pin mapping for '{role}': {unique_exprs}"


def _build_harness(
    circuit: str,
    top_name: str,
    ports: List[Dict[str, Any]],
    is_board: bool,
    role_map: Dict[str, Any],
) -> str:
    """Generate a tailored Icarus Verilog answer-key testbench for the matched ports."""
    lines = ["module tb_answer_key;"]

    if is_board:
        lines.extend([
            "  reg clk = 0;",
            "  reg [15:0] sw = 16'h0000;",
            "  reg [4:0] btn = 5'h00;",
            "  wire [15:0] led;",
            "  wire [6:0] seg;",
            "  wire [3:0] an;",
            "  top dut (.clk(clk), .sw(sw), .btn(btn), .led(led), .seg(seg), .an(an));",
        ])
    else:
        conns = []
        for p in ports:
            w = p["width"]
            decl = f"[{w-1}:0] " if w > 1 else ""
            if p["direction"] == "input":
                lines.append(f"  reg {decl}{p['name']} = 0;")
            else:
                lines.append(f"  wire {decl}{p['name']};")
            conns.append(f".{p['name']}({p['name']})")
        lines.append(f"  {top_name} dut ({', '.join(conns)});")

    if circuit == "adder_4bit_7seg":
        lines.append(HEX_TO_SEG_VERILOG)

    lines.append("  integer i, ia, ib, ic;")
    lines.append("  integer errors = 0;")

    if circuit == "half_adder":
        a, b, s, c = role_map["a"], role_map["b"], role_map["sum"], role_map["cout"]
        lines.extend([
            "  reg exp_s, exp_c;",
            "  initial begin",
            "    for (i = 0; i < 4; i = i + 1) begin",
            f"      {a} = i[0]; {b} = i[1]; #10;",
            "      exp_s = i[0] ^ i[1]; exp_c = i[0] & i[1];",
            f"      if ({s} !== exp_s || {c} !== exp_c) begin",
            f"        $display(\"FAIL: a=%b b=%b got sum=%b carry=%b exp %b %b\", i[0], i[1], {s}, {c}, exp_s, exp_c);",
            "        errors = errors + 1;",
            "      end",
            "    end",
            "    if (errors == 0) $display(\"ANSWER_KEY_PASS\"); else $display(\"ANSWER_KEY_FAIL %0d\", errors);",
            "    $finish;",
            "  end",
        ])

    elif circuit == "full_adder":
        a, b, cin, s, c = role_map["a"], role_map["b"], role_map["cin"], role_map["sum"], role_map["cout"]
        lines.extend([
            "  reg [1:0] exp_r;",
            "  initial begin",
            "    for (i = 0; i < 8; i = i + 1) begin",
            f"      {a} = i[0]; {b} = i[1]; {cin} = i[2]; #10;",
            "      exp_r = i[0] + i[1] + i[2];",
            f"      if ({s} !== exp_r[0] || {c} !== exp_r[1]) begin",
            f"        $display(\"FAIL: a=%b b=%b cin=%b got s=%b c=%b exp %b %b\", i[0], i[1], i[2], {s}, {c}, exp_r[0], exp_r[1]);",
            "        errors = errors + 1;",
            "      end",
            "    end",
            "    if (errors == 0) $display(\"ANSWER_KEY_PASS\"); else $display(\"ANSWER_KEY_FAIL %0d\", errors);",
            "    $finish;",
            "  end",
        ])

    elif circuit == "adder_4bit":
        a, b, s = role_map["a"], role_map["b"], role_map["sum"]
        cin = role_map.get("cin")
        cout = role_map.get("cout")
        lines.append("  reg [4:0] exp_r;")
        lines.append("  initial begin")
        if cin:
            lines.append("    for (ic = 0; ic < 2; ic = ic + 1) begin")
        else:
            lines.append("    ic = 0; begin")
        lines.extend([
            "      for (ia = 0; ia < 16; ia = ia + 1) begin",
            "        for (ib = 0; ib < 16; ib = ib + 1) begin",
            f"          {a} = ia[3:0]; {b} = ib[3:0];" + (f" {cin} = ic[0];" if cin else ""),
            "          #10;",
            "          exp_r = ia + ib + ic;",
        ])
        if cout:
            lines.append(f"          if ({s} !== exp_r[3:0] || {cout} !== exp_r[4]) begin")
            lines.append(f"            if (errors < 8) $display(\"FAIL: a=%0d b=%0d cin=%0d got s=%0d c=%b exp %0d %b\", ia, ib, ic, {s}, {cout}, exp_r[3:0], exp_r[4]);")
        else:
            lines.append(f"          if ({s} !== exp_r[3:0]) begin")
            lines.append(f"            if (errors < 8) $display(\"FAIL: a=%0d b=%0d got s=%0d exp %0d\", ia, ib, {s}, exp_r[3:0]);")
        lines.extend([
            "            errors = errors + 1;",
            "          end",
            "        end",
            "      end",
            "    end",
            "    if (errors == 0) $display(\"ANSWER_KEY_PASS\"); else $display(\"ANSWER_KEY_FAIL %0d\", errors);",
            "    $finish;",
            "  end",
        ])

    elif circuit == "adder_4bit_7seg":
        a, b, seg = role_map["a"], role_map["b"], role_map["seg"]
        an = role_map.get("an")
        lines.extend([
            "  reg [3:0] exp_s;",
            "  reg [6:0] exp_seg;",
            "  initial begin",
            "    for (ia = 0; ia < 16; ia = ia + 1) begin",
            "      for (ib = 0; ib < 16; ib = ib + 1) begin",
            f"        {a} = ia[3:0]; {b} = ib[3:0]; #10;",
            "        exp_s = ia + ib;",
            "        exp_seg = hex_to_seg(exp_s);",
            f"        if ({seg} !== exp_seg" + (f" || ({an} === 4'b1111)" if an else "") + ") begin",
            f"          if (errors < 8) $display(\"FAIL: a=%0d b=%0d sum=%h got seg=%b exp %b\", ia, ib, exp_s, {seg}, exp_seg);",
            "          errors = errors + 1;",
            "        end",
            "      end",
            "    end",
            "    if (errors == 0) $display(\"ANSWER_KEY_PASS\"); else $display(\"ANSWER_KEY_FAIL %0d\", errors);",
            "    $finish;",
            "  end",
        ])

    elif circuit == "counter_4bit":
        clk = role_map["clk"]
        cnt = role_map["count"]
        rst = role_map.get("rst")
        rst_active_low = bool(rst and any(k in rst.lower() for k in ("rst_n", "rstn", "reset_n", "resetn")))
        en = role_map.get("en")
        rst_on = "1'b0" if rst_active_low else "1'b1"
        rst_off = "1'b1" if rst_active_low else "1'b0"
        lines.extend([
            "  task tick;",
            "    begin",
            f"      #5 {clk} = 1; #5 {clk} = 0; #1;",
            "    end",
            "  endtask",
            "  initial begin",
        ])
        if en:
            lines.append(f"    {en} = 1'b1;")
        if rst:
            lines.append(f"    {rst} = {rst_on}; tick(); {rst} = {rst_off};")
        else:
            lines.append("    #5;")
        lines.extend([
            f"    if ({cnt} !== 4'd0) begin $display(\"FAIL: initial/reset count=%0d exp 0\", {cnt}); errors = errors + 1; end",
            "    for (i = 1; i <= 16; i = i + 1) begin",
            "      tick();",
            f"      if ({cnt} !== (i % 16)) begin",
            f"        if (errors < 8) $display(\"FAIL: step %0d got %0d exp %0d\", i, {cnt}, i % 16);",
            "        errors = errors + 1;",
            "      end",
            "    end",
        ])
        if rst:
            lines.extend([
                "    tick(); tick(); tick();",
                f"    {rst} = {rst_on}; tick(); {rst} = {rst_off};",
                f"    if ({cnt} !== 4'd0) begin $display(\"FAIL: mid-count reset got %0d exp 0\", {cnt}); errors = errors + 1; end",
            ])
        lines.extend([
            "    if (errors == 0) $display(\"ANSWER_KEY_PASS\"); else $display(\"ANSWER_KEY_FAIL %0d\", errors);",
            "    $finish;",
            "  end",
        ])

    lines.append("endmodule")
    return "\n".join(lines) + "\n"


def evaluate_against_answer_key(
    circuit: str,
    verilog_code: str,
    pin_mapping: Optional[List[Dict[str, Any]]] = None,
) -> Dict[str, Any]:
    """Run a candidate Verilog design against the exhaustive reference answer key."""
    t0 = time.perf_counter()
    if circuit not in CIRCUIT_ORDER:
        return {"passed": False, "status": "invalid_circuit", "reason": f"Unknown circuit '{circuit}'"}

    top_name, ports, err = inspect_verilog_ports(verilog_code)
    if not ports:
        return {
            "passed": False,
            "status": "compile_error",
            "reason": f"Verilog parse/hierarchy failed: {err}",
            "duration_ms": round((time.perf_counter() - t0) * 1000),
        }

    is_board = _is_board_top(top_name, ports)

    # Required & optional roles per circuit
    specs = {
        "half_adder": (
            [("a", "input", 1), ("b", "input", 1), ("sum", "output", 1), ("cout", "output", 1)],
            [],
        ),
        "full_adder": (
            [("a", "input", 1), ("b", "input", 1), ("cin", "input", 1), ("sum", "output", 1), ("cout", "output", 1)],
            [],
        ),
        "adder_4bit": (
            [("a", "input", 4), ("b", "input", 4), ("sum", "output", 4)],
            [("cin", "input", 1), ("cout", "output", 1)],
        ),
        "adder_4bit_7seg": (
            [("a", "input", 4), ("b", "input", 4), ("seg", "output", 7)],
            [("an", "output", 4)],
        ),
        "counter_4bit": (
            [("clk", "input", 1), ("count", "output", 4)],
            [("rst", "input", 1), ("en", "input", 1)],
        ),
    }

    req_roles, opt_roles = specs[circuit]
    role_map: Dict[str, str] = {}
    used: set = set()
    port_issues: List[str] = []

    for role, direction, width in req_roles:
        if is_board:
            expr, merr = _match_role_board_top(pin_mapping or [], role, direction, width)
            if expr:
                role_map[role] = expr
            else:
                port_issues.append(merr)
        else:
            p, merr = _match_role_standalone(ports, role, direction, width, used)
            if p:
                role_map[role] = p["name"]
                used.add(p["name"])
            else:
                port_issues.append(merr)

    for role, direction, width in opt_roles:
        if is_board:
            expr, _ = _match_role_board_top(pin_mapping or [], role, direction, width)
            if expr:
                role_map[role] = expr
        else:
            p, _ = _match_role_standalone(ports, role, direction, width, used)
            if p:
                role_map[role] = p["name"]
                used.add(p["name"])

    if port_issues:
        return {
            "passed": False,
            "status": "ambiguous_ports",
            "top_module": top_name,
            "is_board_top": is_board,
            "detected_ports": ports,
            "matched_roles": role_map,
            "reason": "; ".join(port_issues),
            "duration_ms": round((time.perf_counter() - t0) * 1000),
        }

    tb_code = _build_harness(circuit, top_name, ports, is_board, role_map)
    with tempfile.TemporaryDirectory(prefix="ak_sim_") as tmpdir:
        dut_path = os.path.join(tmpdir, "dut.v")
        tb_path = os.path.join(tmpdir, "tb_ak.v")
        vvp_path = os.path.join(tmpdir, "ak.vvp")
        Path(dut_path).write_text(strip_code_fences(verilog_code), encoding="utf-8")
        Path(tb_path).write_text(tb_code, encoding="utf-8")

        comp = subprocess.run(
            ["iverilog", "-g2012", "-o", vvp_path, dut_path, tb_path],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if comp.returncode != 0:
            return {
                "passed": False,
                "status": "compile_error",
                "top_module": top_name,
                "matched_roles": role_map,
                "reason": (comp.stderr or comp.stdout)[-400:].strip(),
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }

        try:
            sim = subprocess.run(["vvp", vvp_path], capture_output=True, text=True, timeout=10)
        except subprocess.TimeoutExpired:
            return {
                "passed": False,
                "status": "timeout",
                "top_module": top_name,
                "matched_roles": role_map,
                "reason": "Answer-key simulation timed out.",
                "duration_ms": round((time.perf_counter() - t0) * 1000),
            }

        stdout = sim.stdout.strip()
        passed = sim.returncode == 0 and "ANSWER_KEY_PASS" in stdout and "ANSWER_KEY_FAIL" not in stdout
        return {
            "passed": passed,
            "status": "pass" if passed else "logic_error",
            "top_module": top_name,
            "is_board_top": is_board,
            "matched_roles": role_map,
            "stdout": stdout[:1000],
            "reason": "Passed exhaustive answer key" if passed else (stdout.splitlines()[0] if stdout else "Simulation failed"),
            "duration_ms": round((time.perf_counter() - t0) * 1000),
        }
