# AETHER

Draw a circuit on paper, watch it become verified hardware running on a virtual FPGA board.

## Built During the Hackathon

Everything in this repository was built on **21 November 2026** at the **Gemini 4 NYC Hackathon**.

Main components built from scratch during the event:

- **Live camera recognition** — Continuous overhead camera capture with persistent ink extraction, frame-quality gating, and structured schematic recognition.
- **Module hierarchy** — Save verified circuits as reusable sub-modules in a local library and compose them into larger designs.
- **Verilog generation** — Synthesizable RTL mapped to a virtual FPGA board pinout (switches, pushbuttons, LEDs, and 4-digit 7-segment display).
- **Independent testbench** — Testbench generated from the circuit specification/schematic without seeing the RTL implementation.
- **Iterative fix loop** — Automatic compile and simulation failure repair using Icarus Verilog (`iverilog` / `vvp`) feedback.
- **Lint & issue flags** — Static RTL checks (latches, width mismatches, undriven signals, blocking/non-blocking issues) paired with plain-English explanations.
- **Synthesis report** — Yosys (`synth_xilinx`) resource utilization reporting (LUTs, flip-flops, DSPs, BRAMs).
- **Differential-simulation optimization gate** — 10,500-cycle randomized differential simulation plus a DSP/RAM resource-shift guard to verify area optimizations before accepting them.
- **3D virtual FPGA board** — Interactive Three.js FPGA board (plus 2D PCB fallback) driven by live Icarus Verilog simulation.
- **Vivado export** — One-click `.zip` bundle containing Verilog sources, `.xdc` pin constraints, and a Vivado project Tcl script.
- **Evaluations** — VerilogEval pilot, 20-problem CVDP benchmark with baselines and gated optimization studies, and a hand-drawn circuit evaluation harness.

---

## How It Works

### Pipeline

1. **Capture (Live Camera or Upload)** — The browser captures frames from a camera every ~1.5s (with ink extraction and rotation/mirror controls) or accepts an uploaded sketch.
2. **Frame & Readability Gate** — `gemini-decision-1` scores frame usability during live capture (picking the highest-scoring frame from the last ~5s on **Done**) and checks whether the sketch is readable before spending generation tokens.
3. **Schematic Recognition** — `gemini-4-hydrogen` (`thinking_level=low`) extracts components, ports, and connections into a structured schematic representation.
4. **Verilog Generation** — `gemini-4-neon` generates synthesizable Verilog RTL targeting the virtual FPGA board (incorporating any referenced sub-modules from the module library).
5. **Independent Verification & Fix Loop** — `gemini-4-hydrogen` writes an independent testbench from the schematic alone (never seeing Neon's RTL), runs it in Icarus Verilog, and iteratively fixes compile or simulation failures (up to 5 rounds).
6. **Lint & Explanations** — Static lint checks flag potential hardware issues; `gemini-4-neon` explains flagged issues in plain English.
7. **Synthesis & Optimization Gate** — Yosys (`synth_xilinx`) measures LUT/FF/DSP/BRAM usage. In the Engineer Loop, area optimizations are gated by 10,500-cycle randomized differential simulation against the pre-optimization RTL plus a DSP/RAM guard so LUT reductions cannot hide behind extra DSPs or RAM blocks.
8. **Run & Export** — The verified design runs live on the 3D virtual FPGA board (interactive switches, buttons, LEDs, 7-segment display) and can be exported as a Vivado `.zip` project.

### Model Routing & Why We Chose Them

| Model | Role in AETHER | Why (from pilot data) |
| --- | --- | --- |
| `gemini-decision-1` | Live frame usability gate & pre-generation readability gate (`v1beta` Decisions API) | Returns calibrated pass/fail probabilities cheaply so blurry or hand-occluded frames are filtered before calling larger models. |
| `gemini-4-hydrogen` | Live schematic recognition, independent testbenches, and iterative fix/optimization rounds | Fast (~8.0s on VerilogEval, ~76.0s on CVDP — ~2x faster than Neon) with strong Verilog accuracy (95% VerilogEval, 65% CVDP), making it suited for latency-sensitive live updates and multi-round loops. |
| `gemini-4-neon` | First-pass Verilog RTL generation and plain-English issue explanations | Highest accuracy and cleanest hardware in our pilots: 20/20 (100%) on VerilogEval and tied-best 15/20 (75%) on CVDP, while ~1.5x faster than `gemini-4-carbon` and using ~2.5x fewer LUTs and ~3.7x fewer FFs than Carbon on the same 15 problems. |

---

## Results

### 1. VerilogEval Pilot (20 problems: 10 combinational, 10 sequential)

Easy RTL benchmarks are largely saturated for Gemini 4 models, which motivated moving to the harder CVDP benchmark for system evaluation.

| Model | Pass Rate | Combinational | Sequential | Compile Errors | Avg Time |
| --- | ---: | ---: | ---: | ---: | ---: |
| `gemini-4-neon` | **20 / 20 (100.0%)** | 10 / 10 | 10 / 10 | 0 | 18.9s |
| `gemini-4-hydrogen` | 19 / 20 (95.0%) | 10 / 10 | 9 / 10 | 1 | 8.0s |
| `gemini-4-carbon` | 16 / 20 (80.0%) | 10 / 10 | 6 / 10 | 4 | 9.8s |

### 2. CVDP Combined Results (20 problems, `cid003` non-agentic)

All area numbers below are **fair-intersection averages only** — computed strictly over the exact same set of passing problems so harder designs dropping out never make an average look artificially smaller.

| Method | Pass Rate | Breakages | Fair-Intersection Area (15 shared problems) | Avg Time / Problem |
| --- | ---: | ---: | --- | ---: |
| `gemini-4-hydrogen` (single-shot) | 13 / 20 (65.0%) | — | — *(only 13/15 passed)* | 76.0s |
| `gemini-4-carbon` (single-shot) | 15 / 20 (75.0%) | — | 124.1 LUTs · 189.1 FFs | 223.9s |
| `gemini-4-neon` (single-shot baseline) | 15 / 20 (75.0%) | — | 49.1 LUTs · 50.9 FFs · 4.73 DSPs | 154.2s |
| `gemini-4-neon` + retries (no tools) | 15 / 20 (75.0%) | — | 60.2 LUTs · 56.3 FFs | 526.6s |
| Engineer Loop — pre-optimization | 15 / 20 (75.0%) | 0 | 57.5 LUTs · 56.4 FFs · 5.13 DSPs | — |
| Engineer Loop — ungated optimization | 14 / 20 (70.0%) | **2** | *13-problem intersection:* 33.4 LUTs · 35.1 FFs · 6.08 DSPs *(vs baseline 51.4 / 50.6 / 5.46)* | 461.0s |
| Engineer Loop + Yosys formal equiv gate | 15 / 20 (75.0%) | **0** | 56.2 LUTs · 56.0 FFs · 5.13 DSPs *(2 opts kept)* | +36.2s/prob |
| **Engineer Loop + 10,500-cycle diff-sim & DSP/RAM gate** | **16 / 20 (80.0%)** | **0** | **46.3 LUTs · 45.7 FFs · 5.07 DSPs** *(10 passing opts kept)* | +2.0s/prob |

**What happened with optimization & what the gates caught:**

- **2 breakages without a gate:** Ungated optimization broke two previously passing designs (`cvdp_copilot_restoring_division_0001` and `cvdp_copilot_sync_lifo_0001`), dropping pass rate from 15/20 to 14/20. Its headline LUT drop on the 13-problem intersection was also partially inflated by `cvdp_copilot_hill_cipher_0001`, which reduced LUTs (203 → 16) by shifting math into extra DSP blocks (9 → 12; baseline used 3 DSPs).
- **Yosys formal equivalence gate (`equiv_induct`):** Caught both breakages (0 breakages), but was too strict for sequential state-encoding changes — it only accepted 2 of 15 optimizations (`16qam_mapper`, `thermostat`), barely moving area (57.5 → 56.2 LUTs).
- **10,500-cycle differential simulation + DSP/RAM resource guard:**
  - Caught `restoring_division` via randomized differential simulation (first mismatch at cycle 167 on `quotient`, 22 mismatches total).
  - Caught `sync_lifo` via the DSP/RAM resource guard (`DistRAM 0 → 1`).
  - Caught `hill_cipher` via the DSP/RAM resource guard (`DSP 9 → 12`), blocking fake LUT savings.
  - Kept 10 passing optimizations (including `cvdp_copilot_axi_register_0001`, which moved from fail to pass for **16/20 = 80.0%**), reducing fair-intersection area from 57.5 → **46.3 LUTs** and 56.4 → **45.7 FFs** (beating single-shot `gemini-4-neon`'s 49.1 LUTs / 50.9 FFs) in 39.3s total across all 20 problems.

### 3. Drawing Evaluation (Hand-Drawn Circuits, `eval_drawings/`)

We evaluated 11 completed live-camera drawing sessions captured over 1 hour against exhaustive Icarus Verilog answer keys (`eval_drawings/answer_keys.py`), comparing a **single-shot `gemini-4-neon` baseline** (given the session's best frame, no loop/tests/module library) against **AETHER**.

| Level | Circuit | Sessions | Baseline (`gemini-4-neon`) | AETHER (All Runs) | AETHER (Post-Gate-Fix) | Avg Time (Base / AETHER) |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 1 | `half_adder` *(pre-fix gate blocks)* | 6 | 6 / 6 (100%) | 0 / 6 (0%) | — | 31.0s / 0.9s *(blocked)* |
| 1 | `half_adder` *(post-fix)* | 2 | 2 / 2 (100%) | 2 / 2 (100%) | 2 / 2 (100%) | 15.3s / 55.9s |
| 2 | `full_adder` | 1 | 1 / 1 (100%) | 1 / 1 (100%) | 1 / 1 (100%) | 14.8s / 114.0s |
| 3 | `adder_4bit` | 1 | **0 / 1 (0%)** | **1 / 1 (100%)** | **1 / 1 (100%)** | 20.4s / 163.9s |
| 5 | `counter_4bit` | 1 | 1 / 1 (100%) | 1 / 1 (100%) | 1 / 1 (100%) | 12.1s / 174.7s |
| **Total** | **4 circuits tested** | **11** | **10 / 11 (90.9%)** | **5 / 11 (45.5%)** | **5 / 5 (100%)** | — |

**Key findings & honest caveats:**

- **Very small, single-author sample:** Aside from `half_adder`, each circuit has only **1 session**, all drawn by the author (`adder_4bit_7seg` was not tested). Treat this as an end-to-end smoke test rather than a statistical benchmark.
- **6 pre-fix readability-gate failures:** In the first 6 `half_adder` sessions, `gemini-decision-1` scored the hand-drawn frames between 25% and 53% readable and hard-blocked the pipeline under the original `<60%` threshold — even though single-shot `gemini-4-neon` solved **6/6** of those exact frames.
- **The fix & post-fix results:** After changing the Decision 1 gate to warn-and-continue on low confidence and only hard-block below 15% (with a "Build anyway" override), AETHER passed **5/5 (100%)** across all four circuits — including the first post-fix `half_adder` (47% warning) and the hierarchical `adder_4bit` (reusing the saved `FA` module), where single-shot `gemini-4-neon` failed (`ambiguous_ports`: emitted a 1-bit `full_adder` top module instead of a 4-bit adder).
- **Latency tradeoff:** Full AETHER runs take ~56–175s (live capture + generation + independent testbench + fix loop + Yosys synthesis) versus ~12–20s for a single unverified Neon call.

---

## Where It Fails (Honest Limitations)

- **Small evaluation sample:** Our CVDP evaluation covers 20 problems (1 problem = 5 percentage points), so pass-rate differences have wide uncertainty.
- **Formal equivalence gate is too strict:** Yosys `equiv_induct` struggles with sequential/FSM state re-encodings, rejecting most valid area optimizations; our practical gate therefore relies on 10,500-cycle randomized differential simulation, which is fast and catches real bugs but is not a formal proof.
- **Live recognition latency (~3s):** End-to-end camera frame gating and schematic extraction take roughly 3 seconds per update, so the digital overlay lags behind fast hand drawing.
- **Author-drawn sketches:** Most test drawings were created by the author on similar paper/lighting setups; generalization across diverse handwriting styles and lighting is not yet thoroughly tested.
- **Untested Vivado export:** The exported `.zip` bundle (RTL, `.xdc` constraints, and Tcl project script) is generated cleanly but has not yet been built and flashed onto a physical FPGA board in Vivado.

---

## How to Run

### Requirements

- **Python 3.10+** with:
  - `google-genai`
  - `python-dotenv`
  - `pydantic`
- **Icarus Verilog** (`iverilog` and `vvp`) — required for testbenches and live virtual FPGA simulation (`brew install icarus-verilog` on macOS).
- **Yosys** (`yosys`) — required for synthesis reports (`brew install yosys` on macOS).
- A Gemini API key in `.env` at the repository root:

```bash
echo "GEMINI_API_KEY=your_api_key_here" > .env
```

### Start the App

```bash
./app/start.sh
```

This starts the local server on `http://127.0.0.1:8000` (using `.venv/bin/python` if present, otherwise `python3`) and opens the browser automatically on macOS. To use a different port:

```bash
PORT=8080 ./app/start.sh
```

---

## Credits

- **VerilogEval** — NVIDIA Research ([NVlabs/verilog-eval](https://github.com/NVlabs/verilog-eval)), licensed under the **MIT License**.
- **CVDP (Comprehensive Verilog Design Problems)** — NVIDIA Research ([NVlabs/cvdp_benchmark](https://github.com/NVlabs/cvdp_benchmark)), code licensed under the **Apache License 2.0** and non-code dataset under **CC BY 4.0**.
