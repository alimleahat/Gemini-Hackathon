"""Step 2: Decision Gate powered by gemini-decision-1 (Decisions API).

Checks in a single calibrated pass:
1. Is the input a readable digital circuit diagram (or clear circuit description)?
2. What type of circuit is it (combinational, sequential/FSM, datapath, other)?

If confidence or readability is too low, the pipeline stops and asks the user
to retake the photo (or clarify the description).
"""

import time
from typing import Any, Dict, Optional

from app.config import GATE_CONFIG, MODELS
from app.pipeline.client import get_beta_client

CIRCUIT_TYPE_LABELS = {
    "combinational": "Combinational Logic",
    "sequential_fsm": "Sequential / FSM",
    "datapath": "Datapath / Arithmetic",
    "other": "Other Digital Circuit",
}


def run_gate(
    *,
    image_b64: Optional[str] = None,
    mime_type: Optional[str] = None,
    text_prompt: Optional[str] = None,
) -> Dict[str, Any]:
    """Run the Decisions API gate on an uploaded photo or text description."""
    t0 = time.perf_counter()
    client = get_beta_client()

    has_image = bool(image_b64)
    input_blocks = []
    if has_image:
        input_blocks.append(
            {
                "type": "image",
                "data": image_b64,
                "mime_type": mime_type or "image/jpeg",
            }
        )
    if text_prompt and text_prompt.strip():
        input_blocks.append(
            {
                "type": "text",
                "text": text_prompt.strip(),
            }
        )

    if not input_blocks:
        raise ValueError("Gate requires either an image or a text description.")

    if has_image:
        readable_instructions = (
            "Is this image a readable digital logic circuit diagram, schematic, state machine "
            "(FSM) diagram, truth table, or block diagram drawn on paper/whiteboard/screen "
            "that has enough clarity to be translated into Verilog hardware? "
            "Answer NO if the image is blurry, blank, upside-down/illegible, or not a digital circuit."
        )
    else:
        readable_instructions = (
            "Does this text clearly describe a digital logic circuit or FPGA hardware design "
            "(e.g. logic gates, adder, multiplexer, counter, FSM, ALU, display driver, timer) "
            "that can be implemented in Verilog? "
            "Answer NO if it is unrelated, nonsensical, or not a digital hardware circuit."
        )

    questions = {
        "is_readable_circuit": {
            "type": "noul",
            "instructions": readable_instructions,
        },
        "circuit_type": {
            "type": "choice",
            "instructions": (
                "Classify the primary category of this digital circuit."
            ),
            "criteria": {
                "combinational": (
                    "Purely combinational logic with no clock or memory state "
                    "(e.g. logic gates, MUX, decoder, encoder, comparator, half/full adder, 7-seg decoder)."
                ),
                "sequential_fsm": (
                    "Clocked sequential circuit or finite state machine with flip-flops/state "
                    "(e.g. counter, shift register, traffic light controller, sequence detector, debounce, timer)."
                ),
                "datapath": (
                    "Multi-bit arithmetic or data processing block "
                    "(e.g. ALU, multi-bit adder/subtractor, multiplier, register file, accumulator, datapath)."
                ),
                "other": (
                    "Another kind of digital circuit or not a recognizable circuit."
                ),
            },
        },
    }

    result = client.decisions.create(
        model=MODELS["gate"],
        input=input_blocks,
        questions=questions,
    )

    readable_ans = result.answers["is_readable_circuit"]
    type_ans = result.answers["circuit_type"]

    readable_prob = float(readable_ans.noul)
    readable_conf = float(readable_ans.confidence)
    circuit_type = str(type_ans.choice)
    type_conf = float(type_ans.confidence)
    type_probs = {k: round(float(v), 4) for k, v in type_ans.probabilities.items()}

    min_prob = GATE_CONFIG["min_readable_prob"]
    min_conf = GATE_CONFIG["min_confidence"]
    passed = (readable_prob >= min_prob) and (readable_conf >= min_conf)

    if passed:
        reason = (
            f"Readable {CIRCUIT_TYPE_LABELS.get(circuit_type, circuit_type)} detected "
            f"({readable_prob * 100:.0f}% yes, {readable_conf * 100:.0f}% confidence)."
        )
    else:
        if has_image:
            reason = (
                f"Low confidence ({readable_prob * 100:.0f}% readable, "
                f"{readable_conf * 100:.0f}% confidence). "
                "Please retake the photo with better lighting, sharper focus, "
                "and a clear view of the circuit diagram."
            )
        else:
            reason = (
                f"Input does not clearly describe a digital circuit "
                f"({readable_prob * 100:.0f}% valid, {readable_conf * 100:.0f}% confidence). "
                "Please describe the inputs, outputs, and behavior of the circuit."
            )

    duration_ms = round((time.perf_counter() - t0) * 1000)

    return {
        "model": MODELS["gate"],
        "passed": passed,
        "readable_prob": round(readable_prob, 4),
        "readable_confidence": round(readable_conf, 4),
        "circuit_type": circuit_type,
        "circuit_type_label": CIRCUIT_TYPE_LABELS.get(circuit_type, circuit_type),
        "type_confidence": round(type_conf, 4),
        "type_probabilities": type_probs,
        "reason": reason,
        "duration_ms": duration_ms,
    }
