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
    "gate": "gemini-decision-1",        # Step 2 & Live frame usability: Decisions API (v1beta)
    "live_reader": "gemini-4-hydrogen", # Live Camera mode: fast structured schematic extraction
    "generate": "gemini-4-neon",        # Step 3 & issue explanations: Verilog design generation ONLY
    "testbench": "gemini-4-hydrogen",   # Step 4: Independent testbench generation (never sees Neon's code)
    "improve": "gemini-4-hydrogen",     # Step 5: Iterative fix / optimization loop
}

# Live Camera Mirroring settings
LIVE_CONFIG = {
    "frame_interval_ms": 1500,          # Grab a frame every ~1.5 seconds
    "min_usable_prob": 0.55,            # Minimum P(usable) from gemini-decision-1 to keep frame
    "best_frame_window_sec": 5.0,       # Pick highest-scoring frame from last ~5s on Done
    "live_thinking_level": "low",       # Fast per-frame recognition during live mirroring
    "live_max_frame_px": 768,           # Resize live frames to max ~768px before sending
}

# Step 2 (Decision Gate) thresholds
GATE_CONFIG = {
    "min_readable_prob": 0.60,          # Below this: show warning but continue automatically
    "min_confidence": 0.60,             # Below this: show warning but continue automatically
    "hard_block_prob": 0.15,            # Only stop if readable < 15% (very unlikely to be a circuit)
}

# Step 4 (Icarus Verilog simulation)
TEST_CONFIG = {
    "compile_timeout_sec": 10,
    "sim_timeout_sec": 8,
}

# Step 5 (Improve loop)
IMPROVE_CONFIG = {
    "max_rounds": 5,
    "mode": "fix_errors",               # Swappable: "fix_errors" (can later add "optimize_area" / "both")
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
