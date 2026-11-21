"""Vivado Project Export (.zip) — UNTESTED ON HARDWARE.

Builds a downloadable .zip archive containing:
- rtl/top.v (final generated Verilog)
- sim/tb.v (self-checking testbench, if provided)
- constraints/basys3.xdc (Basys 3 xc7a35tcpg236-1 pin constraints matching top.v)
- build_project.tcl (Vivado project & bitstream script)
- README.txt (explicitly labeled UNTESTED ON HARDWARE)
"""

import io
import re
import zipfile
from typing import Optional

from app.pipeline.tester import _strip_code_fences

BASYS3_XDC = """## ============================================================================
## Basys 3 (Artix-7 xc7a35tcpg236-1) Master Constraints for module top
## STATUS: UNTESTED ON HARDWARE (auto-generated from Paper-to-FPGA app)
## ============================================================================

## 100 MHz Clock (W5)
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];

## 16 Slide Switches (sw[15:0])
set_property -dict { PACKAGE_PIN V17  IOSTANDARD LVCMOS33 } [get_ports { sw[0] }];
set_property -dict { PACKAGE_PIN V16  IOSTANDARD LVCMOS33 } [get_ports { sw[1] }];
set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS33 } [get_ports { sw[2] }];
set_property -dict { PACKAGE_PIN W17  IOSTANDARD LVCMOS33 } [get_ports { sw[3] }];
set_property -dict { PACKAGE_PIN W15  IOSTANDARD LVCMOS33 } [get_ports { sw[4] }];
set_property -dict { PACKAGE_PIN V15  IOSTANDARD LVCMOS33 } [get_ports { sw[5] }];
set_property -dict { PACKAGE_PIN W14  IOSTANDARD LVCMOS33 } [get_ports { sw[6] }];
set_property -dict { PACKAGE_PIN W13  IOSTANDARD LVCMOS33 } [get_ports { sw[7] }];
set_property -dict { PACKAGE_PIN V2   IOSTANDARD LVCMOS33 } [get_ports { sw[8] }];
set_property -dict { PACKAGE_PIN T3   IOSTANDARD LVCMOS33 } [get_ports { sw[9] }];
set_property -dict { PACKAGE_PIN T2   IOSTANDARD LVCMOS33 } [get_ports { sw[10] }];
set_property -dict { PACKAGE_PIN R3   IOSTANDARD LVCMOS33 } [get_ports { sw[11] }];
set_property -dict { PACKAGE_PIN W2   IOSTANDARD LVCMOS33 } [get_ports { sw[12] }];
set_property -dict { PACKAGE_PIN U1   IOSTANDARD LVCMOS33 } [get_ports { sw[13] }];
set_property -dict { PACKAGE_PIN T1   IOSTANDARD LVCMOS33 } [get_ports { sw[14] }];
set_property -dict { PACKAGE_PIN R2   IOSTANDARD LVCMOS33 } [get_ports { sw[15] }];

## 16 LEDs (led[15:0])
set_property -dict { PACKAGE_PIN U16  IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN E19  IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN U19  IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN V19  IOSTANDARD LVCMOS33 } [get_ports { led[3] }];
set_property -dict { PACKAGE_PIN W18  IOSTANDARD LVCMOS33 } [get_ports { led[4] }];
set_property -dict { PACKAGE_PIN U15  IOSTANDARD LVCMOS33 } [get_ports { led[5] }];
set_property -dict { PACKAGE_PIN U14  IOSTANDARD LVCMOS33 } [get_ports { led[6] }];
set_property -dict { PACKAGE_PIN V14  IOSTANDARD LVCMOS33 } [get_ports { led[7] }];
set_property -dict { PACKAGE_PIN V13  IOSTANDARD LVCMOS33 } [get_ports { led[8] }];
set_property -dict { PACKAGE_PIN V3   IOSTANDARD LVCMOS33 } [get_ports { led[9] }];
set_property -dict { PACKAGE_PIN W3   IOSTANDARD LVCMOS33 } [get_ports { led[10] }];
set_property -dict { PACKAGE_PIN U3   IOSTANDARD LVCMOS33 } [get_ports { led[11] }];
set_property -dict { PACKAGE_PIN P3   IOSTANDARD LVCMOS33 } [get_ports { led[12] }];
set_property -dict { PACKAGE_PIN N3   IOSTANDARD LVCMOS33 } [get_ports { led[13] }];
set_property -dict { PACKAGE_PIN P1   IOSTANDARD LVCMOS33 } [get_ports { led[14] }];
set_property -dict { PACKAGE_PIN L1   IOSTANDARD LVCMOS33 } [get_ports { led[15] }];

## 5 Pushbuttons: btn[0]=Center, btn[1]=Up, btn[2]=Left, btn[3]=Right, btn[4]=Down
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports { btn[0] }];
set_property -dict { PACKAGE_PIN T18  IOSTANDARD LVCMOS33 } [get_ports { btn[1] }];
set_property -dict { PACKAGE_PIN W19  IOSTANDARD LVCMOS33 } [get_ports { btn[2] }];
set_property -dict { PACKAGE_PIN T17  IOSTANDARD LVCMOS33 } [get_ports { btn[3] }];
set_property -dict { PACKAGE_PIN U17  IOSTANDARD LVCMOS33 } [get_ports { btn[4] }];

## 4-Digit 7-Segment Display (active-low seg[6:0] = CA..CG, an[3:0] = AN0..AN3)
set_property -dict { PACKAGE_PIN W7   IOSTANDARD LVCMOS33 } [get_ports { seg[0] }];
set_property -dict { PACKAGE_PIN W6   IOSTANDARD LVCMOS33 } [get_ports { seg[1] }];
set_property -dict { PACKAGE_PIN U8   IOSTANDARD LVCMOS33 } [get_ports { seg[2] }];
set_property -dict { PACKAGE_PIN V8   IOSTANDARD LVCMOS33 } [get_ports { seg[3] }];
set_property -dict { PACKAGE_PIN U5   IOSTANDARD LVCMOS33 } [get_ports { seg[4] }];
set_property -dict { PACKAGE_PIN V5   IOSTANDARD LVCMOS33 } [get_ports { seg[5] }];
set_property -dict { PACKAGE_PIN U7   IOSTANDARD LVCMOS33 } [get_ports { seg[6] }];

set_property -dict { PACKAGE_PIN U2   IOSTANDARD LVCMOS33 } [get_ports { an[0] }];
set_property -dict { PACKAGE_PIN U4   IOSTANDARD LVCMOS33 } [get_ports { an[1] }];
set_property -dict { PACKAGE_PIN V4   IOSTANDARD LVCMOS33 } [get_ports { an[2] }];
set_property -dict { PACKAGE_PIN W4   IOSTANDARD LVCMOS33 } [get_ports { an[3] }];

## Configuration options
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
"""


def _make_tcl(project_name: str, has_tb: bool) -> str:
    tb_line = 'add_files -fileset sim_1 -norecurse [file join $script_dir "sim/tb.v"]\n' if has_tb else ""
    return f"""# ============================================================================
# Vivado Project Build Script — UNTESTED ON HARDWARE
# Target: Basys 3 (xc7a35tcpg236-1)
# Usage:  vivado -mode batch -source build_project.tcl
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set proj_name "{project_name}"
set proj_dir [file join $script_dir "vivado_proj"]

create_project $proj_name $proj_dir -part xc7a35tcpg236-1 -force

add_files -norecurse [file join $script_dir "rtl/top.v"]
add_files -fileset constrs_1 -norecurse [file join $script_dir "constraints/basys3.xdc"]
{tb_line}
set_property top top [current_fileset]
update_compile_order -fileset sources_1

# Run Synthesis, Implementation, and Bitstream generation
launch_runs synth_1 -jobs 4
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "Done! Bitstream (if successful): [file join $proj_dir $proj_name.runs impl_1 top.bit]"
"""


def _make_readme(circuit_name: str) -> str:
    return f"""Paper-to-FPGA Vivado Export: {circuit_name}
============================================================
STATUS: UNTESTED ON HARDWARE

This bundle was generated automatically from your circuit design and verified
in simulation (Icarus Verilog) and Yosys synthesis, but has NOT been tested on
a physical Basys 3 FPGA board.

Note on clock speed:
The virtual FPGA board ticks `clk` at ~2-15 Hz so you can watch counters/FSMs
live. On a real Basys 3 board, pin W5 provides a 100 MHz clock — for clocked
designs (like counters), you may want to add a clock divider in `rtl/top.v`
before programming a physical board.

Contents:
- rtl/top.v              : Synthesizable Verilog top module (and any submodules)
- sim/tb.v               : Self-checking testbench
- constraints/basys3.xdc : Basys 3 pin constraints (clk, sw[15:0], btn[4:0], led[15:0], seg[6:0], an[3:0])
- build_project.tcl      : Vivado script targeting xc7a35tcpg236-1

How to open/build in Vivado:
1. Unzip this folder.
2. Open Vivado Tcl Shell (or terminal with Vivado on PATH) in this folder.
3. Run:
     vivado -mode batch -source build_project.tcl
   Or open Vivado GUI and run `source build_project.tcl` in the Tcl Console.
"""


def build_vivado_zip(
    *,
    verilog_code: str,
    testbench_code: Optional[str] = None,
    circuit_name: str = "fpga_design",
) -> tuple[str, bytes]:
    """Return (filename, zip_bytes) for a Vivado project archive."""
    safe_name = re.sub(r"[^a-zA-Z0-9_]+", "_", (circuit_name or "fpga_design").strip().lower()).strip("_")
    if not safe_name:
        safe_name = "fpga_design"

    buf = io.BytesIO()
    has_tb = bool(testbench_code and testbench_code.strip())

    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("rtl/top.v", _strip_code_fences(verilog_code))
        if has_tb:
            zf.writestr("sim/tb.v", _strip_code_fences(testbench_code or ""))
        zf.writestr("constraints/basys3.xdc", BASYS3_XDC)
        zf.writestr("build_project.tcl", _make_tcl(safe_name, has_tb))
        zf.writestr("README.txt", _make_readme(circuit_name or safe_name))

    return f"{safe_name}_vivado_untested.zip", buf.getvalue()
