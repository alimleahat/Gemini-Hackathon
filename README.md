# Aether: sketch to silicon

Draw a circuit on paper, watch it become verified hardware running on a virtual FPGA board.

## Built During the Hackathon

Everything in this repo was built on **21 November 2026** at the **Gemini 4 NYC Hackathon**:

- Live camera schematic recognition with persistent ink extraction and frame gating
- Reusable module library (save verified sub-modules like `HA`/`FA` and compose them)
- Synthesizable Verilog generation, independent testbenches, fix loop, and lint/issue flags
- Yosys synthesis report and 10,500-cycle differential-simulation + DSP/RAM optimization gate
- 3D virtual FPGA board (live Icarus Verilog simulation) and Vivado `.zip` export
- Evaluations: VerilogEval pilot, 20-problem CVDP study, and hand-drawn circuit eval

## How It Works

1. **Frame & readability gate (`gemini-decision-1`, `v1beta` Decisions API):** Filters live camera frames and picks the best frame from the last ~5s on **Done**.
2. **Live schematic reader (`gemini-4-hydrogen`):** Extracts components, ports, and connections into a structured schematic as you draw.
3. **RTL generation (`gemini-4-neon`):** Generates synthesizable Verilog mapped to the virtual FPGA board, reusing saved sub-modules from the library.
4. **Independent testbench & fix loop (`gemini-4-hydrogen` + Icarus Verilog):** Writes tests from the schematic alone (never seeing Neon's RTL) and repairs compile/simulation failures across up to 5 rounds.
5. **Lint & explanations (`gemini-4-neon`):** Flags static RTL issues and explains them in plain English.
6. **Synthesis & optimization gate (Yosys + `gemini-4-hydrogen`):** Reports `synth_xilinx` LUT/FF/DSP/BRAM usage and gates area optimizations with 10,500-cycle differential simulation plus a DSP/RAM guard before running on the 3D board or exporting to Vivado.

## Results

### CVDP Benchmark (20 problems, `cid003` non-agentic)

Area numbers are **fair-intersection averages only** (15 shared passing problems; ungated opt on its 13-problem intersection).

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

Ungated optimization broke `restoring_division` and `sync_lifo` and shifted `hill_cipher` from 9 → 12 DSPs. The 10,500-cycle diff-sim + DSP/RAM gate caught all three (`restoring_division` at cycle 167, `sync_lifo` `DistRAM 0 → 1`, `hill_cipher` `DSP 9 → 12`), kept 10 passing optimizations (including `axi_register`, reaching 16/20), and beat single-shot Neon on both pass rate and fair-intersection LUTs/FFs.

### Hand-Drawn Circuit Evaluation (`eval_drawings/`, post-fix 5/5)

| Circuit | Post-Fix Sessions | Single-Call `gemini-4-neon` | Aether | Avg Time (Base / Aether) |
| --- | ---: | ---: | ---: | --- |
| `half_adder` | 2 | 2 / 2 (100%) | 2 / 2 (100%) | 15.3s / 55.9s |
| `full_adder` | 1 | 1 / 1 (100%) | 1 / 1 (100%) | 14.8s / 114.0s |
| `adder_4bit` | 1 | **0 / 1 (0%)** | **1 / 1 (100%)** | 20.4s / 163.9s |
| `counter_4bit` | 1 | 1 / 1 (100%) | 1 / 1 (100%) | 12.1s / 174.7s |
| **Total (post-fix)** | **5** | **4 / 5 (80%)** | **5 / 5 (100%)** | **15.6s / 112.9s** |

On `adder_4bit`, single-call `gemini-4-neon` failed (`ambiguous_ports`: emitted a 1-bit `full_adder` top module) because it lacked the saved `HA`/`FA` modules, while Aether composed the saved `FA` module into a verified 4-bit adder. Prior to fixing the readability gate, 6 earlier `half_adder` runs (25%–53% readable) were hard-blocked under the original `<60%` threshold (all 6 passed by single-call Neon); switching the gate to warn-and-continue (hard-blocking only `<15%`) resolved this (5/11 across all runs, 5/5 post-fix).

## Limitations

- **Small samples:** 20-problem CVDP benchmark (1 problem = 5 percentage points) and 5 post-fix drawing runs (1 session each for `full_adder`, `adder_4bit`, `counter_4bit`; `adder_4bit_7seg` untested).
- **Author-drawn sketches:** All 11 drawing sessions were drawn by the author on one camera/lighting setup.
- **Formal equivalence gate too strict:** Yosys `equiv_induct` kept only 2 of 13 optimisations, so the practical gate relies on 10,500-cycle differential simulation rather than formal proof.
- **Build latency:** Verified Aether builds take ~1–3 min (53.5s–174.7s across post-fix runs) vs ~15s (12.1s–20.4s) for a single unverified Neon call.

## How to Run

Requires Python 3.10+ (`google-genai`, `python-dotenv`, `pydantic`), Icarus Verilog (`iverilog`/`vvp`), and Yosys (`yosys`).
Set `GEMINI_API_KEY=...` in `.env` at the repo root.
Run `./app/start.sh` to launch at `http://127.0.0.1:8000`.

## Credits

- **VerilogEval:** [NVlabs/verilog-eval](https://github.com/NVlabs/verilog-eval) (MIT License).
- **CVDP:** [NVlabs/cvdp_benchmark](https://github.com/NVlabs/cvdp_benchmark) (Apache 2.0 code / CC BY 4.0 non-code dataset).
