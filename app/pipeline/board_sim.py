"""Step 7 Backend: Live interactive Icarus Verilog simulation for the virtual FPGA board.

Compiles the generated `module top` together with a lightweight interactive
Verilog harness (`__board_sim`) and keeps a persistent `vvp` subprocess alive.
Each browser request sends the current 16-bit switch state (`sw`), 5-bit button
state (`btn`), and number of clock cycles to advance (`cycles`), and receives
the live `led[15:0]`, `seg[6:0]`, `an[3:0]`, and multiplexed 4-digit 7-segment
snapshot in < 1 ms.
"""

import os
import shutil
import subprocess
import tempfile
import threading
import uuid
from typing import Any, Dict, Optional

from app.pipeline.tester import _strip_code_fences

INTERACTIVE_HARNESS = """
module __board_sim;
    reg clk = 0;
    reg [15:0] sw = 16'h0000;
    reg [4:0] btn = 5'h00;
    wire [15:0] led;
    wire [6:0] seg;
    wire [3:0] an;

    top dut (
        .clk(clk),
        .sw(sw),
        .btn(btn),
        .led(led),
        .seg(seg),
        .an(an)
    );

    integer rc, cycles, i;
    reg [255:0] line;
    reg [6:0] d0, d1, d2, d3;
    reg [3:0] seen;

    task sample_digits;
        begin
            if (an[0] === 1'b0) begin d0 = seg; seen[0] = 1'b1; end
            if (an[1] === 1'b0) begin d1 = seg; seen[1] = 1'b1; end
            if (an[2] === 1'b0) begin d2 = seg; seen[2] = 1'b1; end
            if (an[3] === 1'b0) begin d3 = seg; seen[3] = 1'b1; end
        end
    endtask

    initial begin
        #1;
        while ($fgets(line, 32'h8000_0000) > 0) begin
            rc = $sscanf(line, "%h %h %d", sw, btn, cycles);
            if (rc == 3) begin
                d0 = 7'b1111111;
                d1 = 7'b1111111;
                d2 = 7'b1111111;
                d3 = 7'b1111111;
                seen = 4'b0000;
                #1;
                sample_digits();
                for (i = 0; i < cycles; i = i + 1) begin
                    clk = 1'b1; #5;
                    sample_digits();
                    clk = 1'b0; #5;
                    sample_digits();
                end
                #1;
                sample_digits();
                $display("STATE %b %b %b %b %b %b %b %b", led, seg, an, seen, d0, d1, d2, d3);
                $fflush(32'h8000_0001);
            end
        end
        $finish;
    end
endmodule
"""


def _bin_to_int(bits: str, default_bit: str = "0") -> int:
    """Convert a Verilog %b string (which may contain x/z) safely to an int."""
    cleaned = "".join(ch if ch in ("0", "1") else default_bit for ch in bits.strip())
    return int(cleaned, 2) if cleaned else 0


class BoardSession:
    """A single live `vvp` process backing one virtual FPGA board instance."""

    def __init__(self, session_id: str, verilog_code: str):
        self.session_id = session_id
        self.tmpdir = tempfile.mkdtemp(prefix="fpga_board_")
        self.lock = threading.Lock()
        self.total_cycles = 0
        self.proc: Optional[subprocess.Popen] = None

        design_path = os.path.join(self.tmpdir, "design.v")
        harness_path = os.path.join(self.tmpdir, "harness.v")
        vvp_path = os.path.join(self.tmpdir, "board.vvp")

        with open(design_path, "w", encoding="utf-8") as f:
            f.write(_strip_code_fences(verilog_code))
        with open(harness_path, "w", encoding="utf-8") as f:
            f.write(INTERACTIVE_HARNESS)

        comp = subprocess.run(
            ["iverilog", "-g2012", "-o", vvp_path, design_path, harness_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if comp.returncode != 0:
            self.close()
            raise RuntimeError(f"Failed to compile board simulation:\n{comp.stderr or comp.stdout}")

        self.proc = subprocess.Popen(
            ["vvp", vvp_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

    def step(self, sw: int, btn: int, cycles: int = 0) -> Dict[str, Any]:
        """Apply switch/button inputs, advance `cycles` clock ticks, return board outputs."""
        sw_val = int(sw) & 0xFFFF
        btn_val = int(btn) & 0x1F
        cyc_val = max(0, min(64, int(cycles)))

        with self.lock:
            if not self.proc or self.proc.poll() is not None:
                raise RuntimeError("Board simulation process is no longer running.")

            assert self.proc.stdin is not None and self.proc.stdout is not None
            self.proc.stdin.write(f"{sw_val:04x} {btn_val:02x} {cyc_val}\n")
            self.proc.stdin.flush()

            # Read lines until we get our STATE line (ignoring any $display from user Verilog)
            line = ""
            for _ in range(50):
                line = self.proc.stdout.readline()
                if not line:
                    raise RuntimeError("Board simulation ended unexpectedly.")
                if line.startswith("STATE "):
                    break
            else:
                raise RuntimeError("Did not receive STATE response from simulation.")

            parts = line.strip().split()
            if len(parts) < 9:
                raise RuntimeError(f"Malformed STATE line: {line!r}")

            led_bits, seg_bits, an_bits, seen_bits, d0_bits, d1_bits, d2_bits, d3_bits = parts[1:9]
            self.total_cycles += cyc_val

            # Active-high LEDs: x/z -> 0 (off)
            led_int = _bin_to_int(led_bits, default_bit="0")
            # Active-low seg & an: x/z -> 1 (off)
            seg_int = _bin_to_int(seg_bits, default_bit="1")
            an_int = _bin_to_int(an_bits, default_bit="1")
            seen_int = _bin_to_int(seen_bits, default_bit="0")

            digits = [
                _bin_to_int(d0_bits, default_bit="1") if (seen_int & 1) else 0x7F,
                _bin_to_int(d1_bits, default_bit="1") if (seen_int & 2) else 0x7F,
                _bin_to_int(d2_bits, default_bit="1") if (seen_int & 4) else 0x7F,
                _bin_to_int(d3_bits, default_bit="1") if (seen_int & 8) else 0x7F,
            ]

            return {
                "session_id": self.session_id,
                "led": led_int,
                "seg": seg_int,
                "an": an_int,
                "digits": digits,  # [digit0 (rightmost), digit1, digit2, digit3 (leftmost)], active-low 7-bit
                "cycles": self.total_cycles,
            }

    def close(self) -> None:
        with self.lock:
            if self.proc is not None:
                try:
                    if self.proc.stdin:
                        self.proc.stdin.close()
                    self.proc.terminate()
                    self.proc.wait(timeout=1)
                except Exception:
                    try:
                        self.proc.kill()
                    except Exception:
                        pass
                self.proc = None
            shutil.rmtree(self.tmpdir, ignore_errors=True)


class BoardManager:
    """Manages active live board sessions, keeping only the most recent few alive."""

    def __init__(self, max_sessions: int = 4):
        self._lock = threading.Lock()
        self._sessions: Dict[str, BoardSession] = {}
        self._order: list[str] = []
        self._max_sessions = max_sessions

    def create(self, verilog_code: str) -> Dict[str, Any]:
        session_id = uuid.uuid4().hex[:12]
        session = BoardSession(session_id, verilog_code)
        # Initial evaluation at sw=0, btn=0, cycles=0
        initial_state = session.step(sw=0, btn=0, cycles=0)

        with self._lock:
            self._sessions[session_id] = session
            self._order.append(session_id)
            while len(self._order) > self._max_sessions:
                old_id = self._order.pop(0)
                old = self._sessions.pop(old_id, None)
                if old:
                    old.close()

        return initial_state

    def step(self, session_id: str, sw: int, btn: int, cycles: int = 0) -> Dict[str, Any]:
        with self._lock:
            session = self._sessions.get(session_id)
        if not session:
            raise KeyError(f"Unknown or expired board session: {session_id}")
        return session.step(sw=sw, btn=btn, cycles=cycles)

    def close_all(self) -> None:
        with self._lock:
            for session in self._sessions.values():
                session.close()
            self._sessions.clear()
            self._order.clear()


board_manager = BoardManager()
