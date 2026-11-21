"""Central configuration for the Paper-to-FPGA hackathon app.

All Gemini model IDs and pipeline thresholds live here so they can be
changed in one place.
"""

from pathlib import Path

# Paths
APP_DIR = Path(__file__).resolve().parent
REPO_ROOT = APP_DIR.parent
ENV_FILE = REPO_ROOT / ".env"
RUNS_DIR = APP_DIR / "runs"
RUN_IMAGES_DIR = RUNS_DIR / "images"
STATIC_DIR = APP_DIR / "static"

# Model IDs (single source of truth)
MODELS = {
    "gate": "gemini-decision-1",       # Step 2: Decisions API (v1beta)
    "generate": "gemini-4-neon",       # Step 3: Multimodal Verilog + testbench generation
    "improve": "gemini-4-hydrogen",    # Step 5: Iterative fix / optimization loop
}

# Step 2 (Decision Gate) thresholds
GATE_CONFIG = {
    "min_readable_prob": 0.60,         # Minimum P(yes) to accept input as a readable circuit
    "min_confidence": 0.60,            # Minimum Decision 1 confidence to proceed
}

# Step 4 (Icarus Verilog simulation)
TEST_CONFIG = {
    "compile_timeout_sec": 10,
    "sim_timeout_sec": 8,
}

# Step 5 (Improve loop)
IMPROVE_CONFIG = {
    "max_rounds": 5,
    "mode": "fix_errors",              # Swappable: "fix_errors" (can later add "optimize_area" / "both")
}

# Step 6 (Yosys synthesis)
SYNTHESIS_CONFIG = {
    "timeout_sec": 30,
    "target_cmd": "synth_xilinx",
    "top_module": "top",
}

# Server defaults
SERVER_HOST = "127.0.0.1"
SERVER_PORT = 8000
