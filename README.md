# Aether

**Sketch to silicon:** draw a circuit on paper, watch it become verified hardware running on a virtual FPGA board.

## Built During the Hackathon

Everything in this repository was built on **21 November 2026** at the **Gemini 4 NYC Hackathon**:

- Live camera schematic recognition with persistent ink extraction and frame gating
- Reusable module hierarchy (save verified circuits as sub-modules and compose them)
- Synthesizable Verilog generation, independent testbenches, iterative fix loop, and lint/issue flags
- Yosys synthesis report and 10,500-cycle differential-simulation + DSP/RAM optimization gate
- Interactive 3D virtual FPGA board (live Icarus Verilog simulation) and Vivado `.zip` export
- Benchmarks and evaluations (VerilogEval pilot, 20-problem CVDP loop study, hand-drawn circuit eval)

## How It Works

1. **Frame & readability gate (`gemini-decision-1`, `v1beta` Decisions API):** Filters live camera frames and selects the best frame from the last ~5s before generation.
2. **Live schematic reader (`gemini-4-hydrogen`):** Extracts components, ports, and connections into a structured schematic as you draw.
3. **RTL generation (`gemini-4-neon`):** Generates synthesizable Verilog mapped to the virtual FPGA pinout (reusing saved sub-modules from the library).
4. **Independent verification & fix loop (`gemini-4-hydrogen` + Icarus Verilog):** Writes an independent testbench from the schematic without seeing Neon's RTL, runs `iverilog`/`vvp`, and repairs failures across up to 5 rounds.
5. **Lint & explanations (`gemini-4-neon`):** Flags static RTL issues and explains them in plain English.
6. **Synthesis & optimization gate (Yosys + `gemini-4-hydrogen`):** Synthesizes with `synth_xilinx` (LUT/FF/DSP/BRAM) and gates area optimizations with 10,500-cycle differential simulation plus a DSP/RAM resource-shift guard before running on the 3D FPGA board or exporting to Vivado.

## Results

### CVDP Benchmark (20 problems, `cid003` non-agentic)

Area numbers are **fair-intersection averages only** (computed over the exact same 15 passing problems; ungated opt shown on its 13-problem intersection).

| Method | Pass Rate | Fair-Intersection Area (15 shared) | Breakages |
| --- | ---: | --- | ---: |
| `gemini-4-hydrogen` (single-shot) | 13 / 20 (65.0%) | — *(only 13/15 passed)* | — |
| `gemini-4-carbon` (single-shot) | 15 / 20 (75.0%) | 124.1 LUTs · 189.1 FFs | — |
| `gemini-4-neon` (single-shot) | 15 / 20 (75.0%) | 49.1 LUTs · 50.9 FFs · 4.73 DSPs | — |
| `gemini-4-neon` + retries (no tools) | 15 / 20 (75.0%) | 60.2 LUTs · 56.3 FFs | — |
| Aether — pre-optimization | 15 / 20 (75.0%) | 57.5 LUTs · 56.4 FFs · 5.13 DSPs | 0 |
| Aether — ungated optimization | 14 / 20 (70.0%) | *13-prob:* 33.4 LUTs · 35.1 FFs · 6.08 DSPs | 2 |
| Aether + Yosys formal equiv gate | 15 / 20 (75.0%) | 56.2 LUTs · 56.0 FFs · 5.13 DSPs | 0 |
| **Aether + diff-sim & DSP/RAM gate** | **16 / 20 (80.0%)** | **46.3 LUTs · 45.7 FFs · 5.07 DSPs** | **0** |

Ungated optimization broke `restoring_division` and `sync_lifo` (and shifted `hill_cipher` from 9 → 12 DSPs). The 10,500-cycle differential-simulation + DSP/RAM gate caught `restoring_division` (mismatch at cycle 167), `sync_lifo` (`DistRAM 0 → 1`), and `hill_cipher` (`DSP 9 → 12`), while keeping 10 passing optimizations (including `axi_register`, reaching 16/20) and beating single-shot Neon on both pass rate and fair-intersection LUTs/FFs.

### Hand-Drawn Circuit Evaluation (`eval_drawings/`, 11 live sessions)

| Circuit | Sessions | Baseline (`gemini-4-neon`) | Aether (All Runs) | Aether (Post-Gate-Fix) |
| --- | ---: | ---: | ---: | ---: |
| `half_adder` *(pre-fix gate blocks)* | 6 | 6 / 6 (100%) | 0 / 6 (0%) | — |
| `half_adder` *(post-fix)* | 2 | 2 / 2 (100%) | 2 / 2 (100%) | 2 / 2 (100%) |
| `full_adder` | 1 | 1 / 1 (100%) | 1 / 1 (100%) | 1 / 1 (100%) |
| `adder_4bit` | 1 | 0 / 1 (0%) | 1 / 1 (100%) | 1 / 1 (100%) |
| `counter_4bit` | 1 | 1 / 1 (100%) | 1 / 1 (100%) | 1 / 1 (100%) |
| **Total** | **11** | **10 / 11 (90.9%)** | **5 / 11 (45.5%)** | **5 / 5 (100%)** |

The original `<60%` readability gate hard-blocked 6 early `half_adder` runs (25%–53% readable) that single-shot Neon solved. After switching the gate to warn-and-continue (hard-blocking only `<15%`), Aether passed 5/5 — including hierarchical `adder_4bit`, where single-shot Neon failed by emitting a 1-bit `full_adder` top module.

## Limitations

- **Small CVDP sample:** 20 problems (1 problem = 5 percentage points).
- **Formal equivalence gate too strict:** Yosys `equiv_induct` kept only 2 of 13 optimisations, so the practical gate uses 10,500-cycle differential simulation rather than formal proof.
- **Small, single-author drawing eval:** 11 sessions total (1 each for `full_adder`, `adder_4bit`, `counter_4bit`; `adder_4bit_7seg` untested), all drawn by the author.
- **Untested Vivado export:** Generated `.zip` bundles (RTL, `.xdc`, Tcl) have not been built on physical FPGA hardware.

## How to Run

Requires Python 3.10+ (`google-genai`, `python-dotenv`, `pydantic`), Icarus Verilog (`iverilog`/`vvp`), and Yosys (`yosys`).
Put `GEMINI_API_KEY=...` in `.env` at the repo root.
Run `./app/start.sh` to start the app at `http://127.0.0.1:8000`.

## Credits

- **VerilogEval:** [NVlabs/verilog-eval](https://github.com/NVlabs/verilog-eval) — MIT License.
- **CVDP:** [NVlabs/cvdp_benchmark](https://github.com/NVlabs/cvdp_benchmark) — Apache License 2.0 (code) / CC BY 4.0 (non-code dataset).
