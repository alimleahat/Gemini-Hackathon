"""HTTP + SSE backend server for the Paper-to-FPGA hackathon app.

Zero third-party web framework dependencies: uses Python's built-in
ThreadingHTTPServer so it runs out of the box inside the existing .venv.
"""

import atexit
import json
import mimetypes
import os
import sys
import time
import traceback
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict
from urllib.parse import parse_qs, urlparse

# Ensure repo root is on sys.path so `from app...` works regardless of cwd
REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from app.config import (
    GATE_CONFIG,
    IMPROVE_CONFIG,
    LIVE_CONFIG,
    MODELS,
    SERVER_HOST,
    SERVER_PORT,
    STATIC_DIR,
)
from app.pipeline.board_sim import board_manager
from app.pipeline.gate import run_gate
from app.pipeline.generator import run_generate
from app.pipeline.improver import run_improve_loop
from app.pipeline.linter import run_lint_check
from app.pipeline.live_session import live_session_manager
from app.pipeline.logger import (
    list_recent_runs,
    make_run_id,
    save_input_image,
    save_run_log,
)
from app.pipeline.modules import module_library
from app.pipeline.synthesizer import run_synthesis
from app.pipeline.tester import generate_independent_testbench, run_test
from app.pipeline.vivado_export import build_vivado_zip


class AppHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args: Any) -> None:
        # Keep terminal output clean; hide noisy /api/board/step polling logs
        if args and isinstance(args[0], str) and "/api/board/step" in args[0]:
            return
        sys.stderr.write(f"[server] {self.address_string()} - {format % args}\n")

    def _send_json(self, payload: Any, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_json_body(self) -> Dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8"))

    def _send_sse(self, event_name: str, data: Any) -> None:
        msg = f"event: {event_name}\ndata: {json.dumps(data)}\n\n".encode("utf-8")
        self.wfile.write(msg)
        self.wfile.flush()

    def _serve_static(self, rel_path: str) -> None:
        safe_rel = rel_path.lstrip("/") or "index.html"
        target = (STATIC_DIR / safe_rel).resolve()
        if not str(target).startswith(str(STATIC_DIR.resolve())) or not target.is_file():
            self.send_error(HTTPStatus.NOT_FOUND, "File not found")
            return
        mime, _ = mimetypes.guess_type(str(target))
        content = target.read_bytes()
        content_type = mime or "application/octet-stream"
        if content_type.startswith("text/") or content_type in ("application/javascript", "application/json"):
            content_type = f"{content_type}; charset=utf-8"
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/" or path == "/index.html":
            self._serve_static("index.html")
            return
        if path.startswith("/static/"):
            self._serve_static(path[len("/static/"):])
            return
        if path == "/api/config":
            self._send_json(
                {
                    "models": MODELS,
                    "live": LIVE_CONFIG,
                    "gate": GATE_CONFIG,
                    "improve": IMPROVE_CONFIG,
                }
            )
            return
        if path == "/api/runs":
            self._send_json({"runs": list_recent_runs(20)})
            return
        if path == "/api/modules":
            self._send_json({"modules": module_library.list_modules()})
            return
        if path == "/api/health":
            self._send_json({"ok": True})
            return

        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/board/step":
            self._handle_board_step()
            return
        if path == "/api/pipeline/stream":
            self._handle_pipeline_stream()
            return
        if path == "/api/live/start":
            self._handle_live_start()
            return
        if path == "/api/live/frame":
            self._handle_live_frame()
            return
        if path == "/api/live/video":
            self._handle_live_video(parsed.query)
            return
        if path == "/api/live/finish":
            self._handle_live_finish()
            return
        if path == "/api/live/select_best":
            self._handle_live_select_best()
            return
        if path == "/api/modules/save":
            self._handle_module_save()
            return
        if path == "/api/modules/delete":
            self._handle_module_delete()
            return
        if path == "/api/modules/import":
            self._handle_module_import()
            return
        if path == "/api/export/vivado":
            self._handle_vivado_export()
            return

        self.send_error(HTTPStatus.NOT_FOUND, "Not found")

    def _handle_live_start(self) -> None:
        try:
            body = self._read_json_body()
            camera_label = str(body.get("camera_label", ""))
            res = live_session_manager.start_session(camera_label=camera_label)
            self._send_json(res)
        except Exception as e:
            self._send_json({"error": str(e)}, status=500)

    def _handle_live_frame(self) -> None:
        try:
            body = self._read_json_body()
            session_id = str(body.get("session_id", ""))
            image_b64 = body.get("image_b64")
            mime_type = body.get("mime_type") or "image/jpeg"
            # App is the source of truth for the module library
            saved_modules = module_library.list_modules()
            if not session_id or not image_b64:
                self._send_json({"error": "session_id and image_b64 are required"}, status=400)
                return
            res = live_session_manager.process_frame(
                session_id=session_id,
                image_b64=image_b64,
                mime_type=mime_type,
                saved_modules=saved_modules,
            )
            self._send_json(res)
        except Exception as e:
            traceback.print_exc()
            self._send_json({"error": str(e)}, status=500)

    def _handle_live_video(self, query_string: str) -> None:
        try:
            qs = parse_qs(query_string)
            session_id = (qs.get("session_id") or [""])[0]
            if not session_id:
                self._send_json({"error": "session_id query parameter required"}, status=400)
                return
            length = int(self.headers.get("Content-Length", "0"))
            video_bytes = self.rfile.read(length) if length > 0 else b""
            content_type = self.headers.get("Content-Type", "video/webm")
            res = live_session_manager.save_video(session_id, video_bytes, content_type)
            self._send_json(res)
        except Exception as e:
            self._send_json({"error": str(e)}, status=500)

    def _handle_live_finish(self) -> None:
        try:
            body = self._read_json_body()
            session_id = str(body.get("session_id", ""))
            res = live_session_manager.finish_session(session_id)
            self._send_json(res)
        except Exception as e:
            self._send_json({"error": str(e)}, status=500)

    def _handle_live_select_best(self) -> None:
        try:
            body = self._read_json_body()
            session_id = str(body.get("session_id", ""))
            window_sec = body.get("window_sec")
            res = live_session_manager.select_best_recent_frame(
                session_id=session_id,
                window_sec=float(window_sec) if window_sec is not None else None,
            )
            self._send_json(res)
        except Exception as e:
            self._send_json({"error": str(e)}, status=500)

    def _handle_module_save(self) -> None:
        try:
            body = self._read_json_body()
            name = str(body.get("name", "")).strip()
            if not name:
                self._send_json({"error": "Module name is required"}, status=400)
                return
            entry = module_library.create_and_save_module(
                name=name,
                image_b64=body.get("image_b64") or None,
                mime_type=body.get("mime_type") or "image/jpeg",
                schematic_json=body.get("schematic_json") or None,
                text_prompt=body.get("text_prompt") or None,
            )
            self._send_json({"module": entry, "modules": module_library.list_modules()})
        except Exception as e:
            traceback.print_exc()
            self._send_json({"error": str(e)}, status=500)

    def _handle_module_delete(self) -> None:
        try:
            body = self._read_json_body()
            name = str(body.get("name", ""))
            module_library.delete_module(name)
            self._send_json({"modules": module_library.list_modules()})
        except Exception as e:
            self._send_json({"error": str(e)}, status=500)

    def _handle_module_import(self) -> None:
        try:
            body = self._read_json_body()
            replace = bool(body.get("replace", False))
            modules = module_library.import_library(body.get("library", body), replace=replace)
            self._send_json({"modules": modules})
        except Exception as e:
            self._send_json({"error": str(e)}, status=400)

    def _handle_vivado_export(self) -> None:
        try:
            body = self._read_json_body()
            verilog_code = body.get("verilog_code") or ""
            if not verilog_code.strip():
                self._send_json({"error": "No Verilog code available to export."}, status=400)
                return
            filename, zip_bytes = build_vivado_zip(
                verilog_code=verilog_code,
                testbench_code=body.get("testbench_code") or None,
                circuit_name=str(body.get("circuit_name") or "fpga_design"),
            )
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Disposition", f'attachment; filename="{filename}"')
            self.send_header("Content-Length", str(len(zip_bytes)))
            self.end_headers()
            self.wfile.write(zip_bytes)
        except Exception as e:
            self._send_json({"error": str(e)}, status=500)

    def _handle_board_step(self) -> None:
        try:
            body = self._read_json_body()
            session_id = str(body.get("session_id", ""))
            sw = int(body.get("sw", 0))
            btn = int(body.get("btn", 0))
            cycles = int(body.get("cycles", 0))
            state = board_manager.step(session_id=session_id, sw=sw, btn=btn, cycles=cycles)
            self._send_json(state)
        except KeyError as e:
            self._send_json({"error": str(e)}, status=404)
        except Exception as e:
            self._send_json({"error": str(e)}, status=500)

    def _handle_pipeline_stream(self) -> None:
        try:
            body = self._read_json_body()
        except Exception as e:
            self._send_json({"error": f"Invalid JSON: {e}"}, status=400)
            return

        image_b64 = body.get("image_b64") or None
        mime_type = body.get("mime_type") or "image/jpeg"
        text_prompt = (body.get("text_prompt") or "").strip() or None
        schematic_json = body.get("schematic_json") or None
        live_session_id = body.get("live_session_id") or None
        chosen_frame = body.get("chosen_frame") or None
        saved_modules = module_library.list_modules() or None
        baseline_mode = bool(body.get("baseline_mode", False))
        enable_improve = bool(body.get("enable_improve", True)) and not baseline_mode
        enable_synthesis = bool(body.get("enable_synthesis", True))
        bypass_gate = bool(body.get("bypass_gate", False))

        if not image_b64 and not text_prompt:
            self._send_json({"error": "Please provide a circuit photo or a text description."}, status=400)
            return

        # Switch response to Server-Sent Events
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()

        t_start = time.perf_counter()
        run_id = make_run_id()
        saved_image_rel = None
        if image_b64:
            try:
                saved_image_rel = save_input_image(run_id, image_b64, mime_type)
            except Exception:
                saved_image_rel = None

        run_record: Dict[str, Any] = {
            "run_id": run_id,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "mode": "baseline" if baseline_mode else "full",
            "toggles": {
                "baseline_mode": baseline_mode,
                "enable_improve": enable_improve,
                "enable_synthesis": enable_synthesis,
            },
            "models": MODELS,
            "input": {
                "type": "live_camera" if live_session_id else ("image" if image_b64 else "text"),
                "image_file": saved_image_rel,
                "mime_type": mime_type if image_b64 else None,
                "text_prompt": text_prompt,
                "live_session_id": live_session_id,
                "chosen_frame": chosen_frame,
                "schematic_json": schematic_json,
            },
            "gate": None,
            "generate": None,
            "initial_test": None,
            "improve_rounds": [],
            "final_test": None,
            "lint": None,
            "synthesis": None,
            "board_loaded": False,
            "total_duration_ms": 0,
        }

        try:
            # --- STEP 2: DECISION GATE (gemini-decision-1) ---
            self._send_sse("stage", {"stage": "gate", "status": "running", "model": MODELS["gate"]})
            gate_res = run_gate(
                image_b64=image_b64,
                mime_type=mime_type,
                text_prompt=text_prompt,
            )
            gate_res["bypassed"] = bypass_gate
            run_record["gate"] = gate_res

            if gate_res.get("blocked") and not bypass_gate:
                self._send_sse("stage", {"stage": "gate", "status": "rejected", "data": gate_res})
                run_record["total_duration_ms"] = round((time.perf_counter() - t_start) * 1000)
                log_path = save_run_log(run_record)
                self._send_sse(
                    "complete",
                    {
                        "run_id": run_id,
                        "stopped_at": "gate",
                        "log_file": str(log_path.name),
                        "total_duration_ms": run_record["total_duration_ms"],
                    },
                )
                return

            gate_status = "warning" if (gate_res.get("warning") or gate_res.get("blocked")) else "done"
            self._send_sse("stage", {"stage": "gate", "status": gate_status, "data": gate_res})

            # --- STEP 3: GENERATE VERILOG + TESTBENCH (gemini-4-neon) ---
            self._send_sse("stage", {"stage": "generate", "status": "running", "model": MODELS["generate"]})
            gen_res = run_generate(
                image_b64=image_b64,
                mime_type=mime_type,
                text_prompt=text_prompt,
                circuit_type=gate_res.get("circuit_type_label"),
                schematic_json=schematic_json,
                saved_modules=saved_modules,
            )
            run_record["generate"] = gen_res
            self._send_sse("stage", {"stage": "generate", "status": "done", "data": gen_res})

            # --- STEP 4: INDEPENDENT TESTBENCH (gemini-4-hydrogen) + ICARUS VERILOG ---
            self._send_sse(
                "stage",
                {
                    "stage": "test",
                    "status": "running",
                    "substage": "generating_tb",
                    "model": MODELS["testbench"],
                },
            )
            tb_res = generate_independent_testbench(
                image_b64=image_b64,
                mime_type=mime_type,
                text_prompt=text_prompt,
                circuit_type=gate_res.get("circuit_type_label"),
                circuit_name=gen_res.get("circuit_name"),
                design_summary=gen_res.get("design_summary"),
                pin_mapping=gen_res.get("pin_mapping"),
                schematic_json=schematic_json,
            )
            self._send_sse(
                "stage",
                {
                    "stage": "test",
                    "status": "running",
                    "substage": "simulating",
                    "model": MODELS["testbench"],
                },
            )
            test_res = run_test(gen_res["verilog_code"], tb_res["testbench_code"])
            test_res["tb_model"] = tb_res["model"]
            test_res["tb_plan"] = tb_res["test_plan"]
            test_res["tb_duration_ms"] = tb_res["duration_ms"]
            test_res["testbench_code"] = tb_res["testbench_code"]
            run_record["initial_test"] = test_res
            self._send_sse("stage", {"stage": "test", "status": "done", "data": test_res})

            final_verilog = gen_res["verilog_code"]
            final_testbench = tb_res["testbench_code"]
            final_test = test_res

            # --- STEP 5: IMPROVE LOOP (gemini-4-hydrogen, swappable) ---
            if not enable_improve:
                skip_reason = (
                    "Skipped in Baseline (Single Call) mode."
                    if baseline_mode
                    else "Improve loop toggled OFF."
                )
                self._send_sse(
                    "stage",
                    {"stage": "improve", "status": "skipped", "data": {"reason": skip_reason}},
                )
            elif test_res["passed"]:
                self._send_sse(
                    "stage",
                    {
                        "stage": "improve",
                        "status": "skipped",
                        "data": {"reason": "Passed on first try — no fixes needed!"},
                    },
                )
            else:
                self._send_sse(
                    "stage",
                    {
                        "stage": "improve",
                        "status": "running",
                        "model": MODELS["improve"],
                        "max_rounds": IMPROVE_CONFIG["max_rounds"],
                    },
                )

                def _on_round(round_data: Dict[str, Any]) -> None:
                    self._send_sse("stage", {"stage": "improve", "status": "round", "data": round_data})

                improve_res = run_improve_loop(
                    verilog_code=final_verilog,
                    testbench_code=final_testbench,
                    initial_test=test_res,
                    circuit_name=gen_res.get("circuit_name", ""),
                    design_summary=gen_res.get("design_summary", ""),
                    on_round=_on_round,
                )
                run_record["improve_rounds"] = improve_res["rounds"]
                final_verilog = improve_res["final_verilog"]
                final_testbench = improve_res["final_testbench"]
                final_test = improve_res["final_test"]
                self._send_sse(
                    "stage",
                    {
                        "stage": "improve",
                        "status": "done",
                        "data": {
                            "reason": improve_res["reason"],
                            "rounds_used": len(improve_res["rounds"]),
                            "passed": final_test["passed"],
                            "final_verilog": final_verilog,
                            "final_testbench": final_testbench,
                            "final_test": final_test,
                        },
                    },
                )

            run_record["final_test"] = final_test

            # --- DESIGN ISSUE FLAGS (Yosys/Verilator lint + gemini-4-neon) ---
            if final_test.get("board_interface_ok"):
                self._send_sse("stage", {"stage": "lint", "status": "running"})
                lint_res = run_lint_check(final_verilog, schematic_json=schematic_json)
                run_record["lint"] = lint_res
                self._send_sse("stage", {"stage": "lint", "status": "done", "data": lint_res})
            else:
                self._send_sse(
                    "stage",
                    {
                        "stage": "lint",
                        "status": "skipped",
                        "data": {"reason": "Skipped because Verilog did not compile cleanly."},
                    },
                )

            # --- STEP 6: SYNTHESIS REPORT (Yosys synth_xilinx, swappable) ---
            if not enable_synthesis:
                self._send_sse(
                    "stage",
                    {"stage": "synthesis", "status": "skipped", "data": {"reason": "Synthesis toggled OFF."}},
                )
            elif not final_test.get("board_interface_ok"):
                self._send_sse(
                    "stage",
                    {
                        "stage": "synthesis",
                        "status": "skipped",
                        "data": {"reason": "Skipped because Verilog did not compile cleanly."},
                    },
                )
            else:
                self._send_sse("stage", {"stage": "synthesis", "status": "running"})
                synth_res = run_synthesis(final_verilog)
                run_record["synthesis"] = synth_res
                self._send_sse("stage", {"stage": "synthesis", "status": "done", "data": synth_res})

            # --- STEP 7: LAUNCH LIVE VIRTUAL FPGA BOARD ---
            if final_test.get("board_interface_ok"):
                self._send_sse("stage", {"stage": "board", "status": "running"})
                try:
                    board_state = board_manager.create(final_verilog)
                    run_record["board_loaded"] = True
                    self._send_sse(
                        "stage",
                        {
                            "stage": "board",
                            "status": "done",
                            "data": {
                                **board_state,
                                "is_clocked": gen_res.get("is_clocked", False),
                                "recommended_clock_hz": gen_res.get("recommended_clock_hz", 4),
                                "pin_mapping": gen_res.get("pin_mapping", []),
                                "circuit_name": gen_res.get("circuit_name", ""),
                            },
                        },
                    )
                except Exception as e:
                    self._send_sse("stage", {"stage": "board", "status": "error", "data": {"error": str(e)}})
            else:
                self._send_sse(
                    "stage",
                    {
                        "stage": "board",
                        "status": "error",
                        "data": {"error": "Cannot load virtual board because design.v failed to compile."},
                    },
                )

            run_record["total_duration_ms"] = round((time.perf_counter() - t_start) * 1000)
            log_path = save_run_log(run_record)
            self._send_sse(
                "complete",
                {
                    "run_id": run_id,
                    "log_file": str(log_path.name),
                    "total_duration_ms": run_record["total_duration_ms"],
                },
            )

        except Exception as e:
            traceback.print_exc()
            run_record["error"] = str(e)
            run_record["total_duration_ms"] = round((time.perf_counter() - t_start) * 1000)
            save_run_log(run_record)
            try:
                self._send_sse("error", {"message": str(e)})
            except Exception:
                pass


def main() -> None:
    port = int(os.environ.get("PORT", SERVER_PORT))
    host = os.environ.get("HOST", SERVER_HOST)
    atexit.register(board_manager.close_all)

    server = ThreadingHTTPServer((host, port), AppHandler)
    url = f"http://{host}:{port}"
    print(f"\n  Paper-to-FPGA Virtual Board is running at: {url}\n")
    print("  Press Ctrl+C to stop.\n", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        board_manager.close_all()
        server.server_close()


if __name__ == "__main__":
    main()
