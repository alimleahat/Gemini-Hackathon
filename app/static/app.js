/* Paper -> FPGA Frontend Controller
 * Handles photo/camera/text input, live SSE pipeline streaming,
 * and real-time interactive virtual FPGA board simulation.
 */

const state = {
  inputMode: "live", // "live" | "photo" | "text"
  imageB64: null,
  mimeType: "image/jpeg",
  cameraStream: null,
  running: false,

  // Live Camera Mirroring state
  liveStream: null,
  liveMirroring: false,
  liveSessionId: null,
  liveIntervalMs: 1500,
  liveLoopTimer: null,
  liveFrameInFlight: false,
  liveFrameCount: 0,
  liveUsableCount: 0,
  liveLastImageB64: null,
  liveSchematic: null,
  liveRecorder: null,
  liveRecordedChunks: [],
  inkEngine: null,
  showFullRawCam: false,

  // Saved Module Library (used by live frames + generation)
  savedModules: [],

  // Latest generated design (for Vivado export)
  latestVerilog: null,
  latestTestbench: null,
  latestCircuitName: null,

  // Virtual FPGA Board state
  boardSessionId: null,
  sw: 0,           // 16-bit integer
  btn: 0,          // 5-bit integer
  led: 0,          // 16-bit integer
  digits: [0x7f, 0x7f, 0x7f, 0x7f], // active-low 7-bit per digit [d0..d3]
  clockRunning: false,
  clockHz: 4,
  clockTimer: null,
  stepInFlight: false,
  pendingSync: false,
};

// DOM refs
const $ = (id) => document.getElementById(id);

// --- Initialization ---
async function init() {
  buildVirtualBoardDOM();
  bindInputEvents();
  bindLiveCameraEvents();
  bindModulesEvents();
  bindToggleEvents();
  bindBoardEvents();
  bindHistoryModal();

  // Render empty placeholder digital schematic
  if (window.SchematicRenderer) {
    window.SchematicRenderer.render($("live-schematic-canvas"), null);
  }
  syncRunBarVisibility();
  populateCameraList(false);
  fetchSavedModules();

  // Fetch active model IDs & live interval from single config file on backend
  try {
    const res = await fetch("/api/config");
    if (res.ok) {
      const cfg = await res.json();
      if (cfg.models) {
        $("tag-model-gate").textContent = cfg.models.gate;
        $("tag-model-generate").textContent = cfg.models.generate;
        $("tag-model-improve").textContent = cfg.models.improve;
        if (cfg.models.live_reader) {
          $("live-reader-pill").textContent = cfg.models.live_reader;
        }
      }
      if (cfg.live?.frame_interval_ms) {
        state.liveIntervalMs = cfg.live.frame_interval_ms;
      }
    }
  } catch (_) {}
}

// --- Build 2D Virtual FPGA Board DOM ---
function buildVirtualBoardDOM() {
  // 4-Digit 7-Segment Display: left-to-right is Digit 3, Digit 2, Digit 1, Digit 0
  const digitsWrap = $("sevenseg-digits");
  digitsWrap.innerHTML = "";
  for (let d = 3; d >= 0; d--) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 60 100");
    svg.classList.add("digit-svg");
    svg.dataset.digit = String(d);
    // Standard segment polygons: 0=a(top), 1=b(tr), 2=c(br), 3=d(bot), 4=e(bl), 5=f(tl), 6=g(mid)
    const segPolys = [
      "12,6 48,6 42,14 18,14",       // a (0)
      "50,8 55,14 52,46 46,42 48,15",// b (1)
      "46,54 51,50 48,86 43,92 41,84 44,58", // c (2)
      "16,86 42,86 46,94 10,94",     // d (3)
      "9,50 14,54 12,84 6,90 8,54",  // e (4)
      "12,8 17,15 15,42 9,46 7,14",  // f (5)
      "16,46 44,46 48,50 44,54 16,54 12,50", // g (6)
    ];
    segPolys.forEach((pts, idx) => {
      const poly = document.createElementNS("http://www.w3.org/2000/svg", "polygon");
      poly.setAttribute("points", pts);
      poly.classList.add("seg-path");
      poly.dataset.seg = String(idx);
      svg.appendChild(poly);
    });
    digitsWrap.appendChild(svg);
  }

  // 16 LEDs (LED15 left -> LED0 right)
  const ledRow = $("led-row");
  ledRow.innerHTML = "";
  for (let i = 15; i >= 0; i--) {
    const cell = document.createElement("div");
    cell.className = "led-cell";
    cell.innerHTML = `<div class="led-bulb" id="led-${i}" title="led[${i}]"></div><span class="io-idx">${i}</span>`;
    ledRow.appendChild(cell);
  }

  // 16 Switches (SW15 left -> SW0 right)
  const swRow = $("sw-row");
  swRow.innerHTML = "";
  for (let i = 15; i >= 0; i--) {
    const cell = document.createElement("div");
    cell.className = "sw-cell";
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "sw-toggle";
    btn.id = `sw-${i}`;
    btn.title = `Toggle sw[${i}]`;
    btn.dataset.bit = String(i);
    btn.innerHTML = `<div class="sw-knob"></div>`;
    btn.addEventListener("click", () => toggleSwitch(i));
    const lbl = document.createElement("span");
    lbl.className = "io-idx";
    lbl.textContent = `S${i}`;
    cell.appendChild(btn);
    cell.appendChild(lbl);
    swRow.appendChild(cell);
  }
}

// --- Input Events (Live Camera, Upload, Drag-Drop, Camera, Text) ---
function syncRunBarVisibility() {
  const backupBar = $("backup-run-bar");
  if (backupBar) {
    backupBar.classList.toggle("hidden", state.inputMode === "live");
  }
}

function bindInputEvents() {
  document.querySelectorAll(".tab-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      const tab = btn.dataset.tab;
      state.inputMode = tab;
      document.querySelectorAll(".tab-btn").forEach((b) => b.classList.toggle("active", b === btn));
      $("panel-live").classList.toggle("active", tab === "live");
      $("panel-photo").classList.toggle("active", tab === "photo");
      $("panel-text").classList.toggle("active", tab === "text");
      if (tab !== "photo") stopCamera();
      syncRunBarVisibility();
    });
  });

  const fileInput = $("file-input");
  const dropzone = $("dropzone");

  $("btn-choose-file").addEventListener("click", () => fileInput.click());
  fileInput.addEventListener("change", (e) => {
    const file = e.target.files?.[0];
    if (file) loadImageFile(file);
  });

  dropzone.addEventListener("dragover", (e) => {
    e.preventDefault();
    dropzone.classList.add("dragover");
  });
  dropzone.addEventListener("dragleave", () => dropzone.classList.remove("dragover"));
  dropzone.addEventListener("drop", (e) => {
    e.preventDefault();
    dropzone.classList.remove("dragover");
    const file = e.dataTransfer?.files?.[0];
    if (file && file.type.startsWith("image/")) loadImageFile(file);
  });

  $("btn-open-camera").addEventListener("click", openCamera);
  $("btn-close-camera").addEventListener("click", stopCamera);
  $("btn-capture").addEventListener("click", captureCameraFrame);
  $("btn-clear-image").addEventListener("click", clearImage);

  $("btn-run").addEventListener("click", () => startPipeline());
}

// --- Live Camera Mirroring (Continuity Camera / Webcam) ---
function bindLiveCameraEvents() {
  if (window.FastInkEngine) {
    state.inkEngine = window.FastInkEngine.create({
      videoEl: $("live-video"),
      outCanvas: $("live-ink-canvas"),
      fpsEl: $("live-ink-fps"),
      threshold: Number($("ink-thresh-slider").value) || 24,
      targetFps: 25,
    });
  }
  $("ink-thresh-slider").addEventListener("input", (e) => {
    const v = Number(e.target.value);
    $("ink-thresh-val").textContent = String(v);
    if (state.inkEngine) state.inkEngine.setThreshold(v);
  });
  const toggleRaw = () => {
    state.showFullRawCam = !state.showFullRawCam;
    $("live-video").classList.toggle("full-raw", state.showFullRawCam);
    $("btn-toggle-raw-cam").textContent = state.showFullRawCam ? "Show Digital Ink" : "Show Raw Cam";
  };
  $("btn-toggle-raw-cam").addEventListener("click", toggleRaw);
  $("live-video").addEventListener("click", toggleRaw);

  $("btn-refresh-cameras").addEventListener("click", () => populateCameraList(true));
  $("camera-select").addEventListener("change", async () => {
    if (state.liveMirroring) {
      await openLiveVideoStream($("camera-select").value);
    }
  });
  $("btn-live-toggle").addEventListener("click", () => {
    if (state.liveMirroring) pauseLiveMirror();
    else startLiveMirror();
  });
  $("btn-live-done").addEventListener("click", finishLiveAndBuild);
}

async function populateCameraList(requestPermFirst = false) {
  if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return;
  const select = $("camera-select");
  const prevVal = select.value;

  if (requestPermFirst) {
    try {
      const tmp = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
      tmp.getTracks().forEach((t) => t.stop());
    } catch (_) {}
  }

  try {
    const devices = await navigator.mediaDevices.enumerateDevices();
    const cams = devices.filter((d) => d.kind === "videoinput");
    select.innerHTML = "";
    if (!cams.length) {
      select.innerHTML = `<option value="">No cameras detected</option>`;
      return;
    }
    cams.forEach((cam, idx) => {
      const opt = document.createElement("option");
      opt.value = cam.deviceId;
      opt.textContent = cam.label || `Camera ${idx + 1}`;
      select.appendChild(opt);
    });
    if (prevVal && cams.some((c) => c.deviceId === prevVal)) {
      select.value = prevVal;
    } else {
      // Prefer iPhone / Continuity Camera automatically if present
      const iphone = cams.find((c) => /iphone|continuity/i.test(c.label || ""));
      if (iphone) select.value = iphone.deviceId;
    }
  } catch (_) {}
}

async function openLiveVideoStream(deviceId) {
  stopLiveVideoStream();
  const constraints = {
    video: deviceId
      ? { deviceId: { exact: deviceId }, width: { ideal: 1280 }, height: { ideal: 720 } }
      : { width: { ideal: 1280 }, height: { ideal: 720 } },
    audio: false,
  };
  const stream = await navigator.mediaDevices.getUserMedia(constraints);
  state.liveStream = stream;
  const video = $("live-video");
  video.srcObject = stream;
  await video.play();
  video.classList.remove("hidden");
  $("live-video-placeholder").classList.add("hidden");
  if (state.inkEngine) state.inkEngine.start();

  // Refresh camera list now that permission is granted so real labels (e.g. iPhone) appear
  await populateCameraList(false);
  const activeTrack = stream.getVideoTracks()[0];
  const activeId = activeTrack?.getSettings?.().deviceId;
  if (activeId) $("camera-select").value = activeId;
  return activeTrack?.label || "";
}

function stopLiveVideoStream() {
  if (state.inkEngine) state.inkEngine.stop();
  $("live-video").classList.add("hidden");
  if (state.liveStream) {
    state.liveStream.getTracks().forEach((t) => t.stop());
    state.liveStream = null;
  }
}

function startMediaRecording() {
  if (!state.liveStream || typeof MediaRecorder === "undefined") return;
  state.liveRecordedChunks = [];
  const mimeCandidates = ["video/webm;codecs=vp9", "video/webm;codecs=vp8", "video/webm", "video/mp4"];
  const chosenMime = mimeCandidates.find((m) => MediaRecorder.isTypeSupported(m)) || "";
  try {
    const rec = chosenMime
      ? new MediaRecorder(state.liveStream, { mimeType: chosenMime })
      : new MediaRecorder(state.liveStream);
    rec.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) state.liveRecordedChunks.push(e.data);
    };
    rec.start(1000);
    state.liveRecorder = rec;
    $("live-rec-badge").classList.remove("hidden");
  } catch (_) {
    state.liveRecorder = null;
  }
}

async function stopAndUploadRecording() {
  $("live-rec-badge").classList.add("hidden");
  const rec = state.liveRecorder;
  const sessionId = state.liveSessionId;
  state.liveRecorder = null;
  if (!rec || !sessionId) return;

  await new Promise((resolve) => {
    rec.onstop = resolve;
    try {
      if (rec.state !== "inactive") rec.stop();
      else resolve();
    } catch (_) {
      resolve();
    }
  });

  if (!state.liveRecordedChunks.length) return;
  const mime = rec.mimeType || "video/webm";
  const blob = new Blob(state.liveRecordedChunks, { type: mime });
  state.liveRecordedChunks = [];
  try {
    await fetch(`/api/live/video?session_id=${encodeURIComponent(sessionId)}`, {
      method: "POST",
      headers: { "Content-Type": mime },
      body: blob,
    });
  } catch (_) {}
}

async function startLiveMirror() {
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    alert("Camera API is not available in this browser.");
    return;
  }
  try {
    const camLabel = await openLiveVideoStream($("camera-select").value);
    if (!state.liveSessionId) {
      const res = await fetch("/api/live/start", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ camera_label: camLabel }),
      });
      const data = await res.json();
      state.liveSessionId = data.session_id;
      state.liveFrameCount = 0;
      state.liveUsableCount = 0;
      startMediaRecording();
    }

    state.liveMirroring = true;
    $("btn-live-toggle").textContent = "⏸ Pause Mirror";
    $("btn-live-done").disabled = false;
    $("live-status-text").textContent = "Live mirroring active — grabbing a frame every 1.5s...";
    setStepper("input", "running");

    // Grab first frame immediately, then every ~1.5s
    grabAndSendLiveFrame();
    state.liveLoopTimer = setInterval(grabAndSendLiveFrame, state.liveIntervalMs);
  } catch (err) {
    alert("Could not start live camera: " + err.message);
  }
}

function pauseLiveMirror() {
  state.liveMirroring = false;
  if (state.liveLoopTimer) {
    clearInterval(state.liveLoopTimer);
    state.liveLoopTimer = null;
  }
  $("btn-live-toggle").textContent = "▶ Resume Mirror";
  $("live-status-text").textContent = "Mirroring paused. Click Resume or click Done to build hardware.";
}

function captureCurrentLiveFrameB64() {
  const video = $("live-video");
  if (!video || !video.videoWidth) return null;
  const canvas = $("capture-canvas");
  // Downscale slightly if huge so 1.5s frames upload & process fast
  const maxW = 1024;
  const scale = Math.min(1, maxW / video.videoWidth);
  canvas.width = Math.round(video.videoWidth * scale);
  canvas.height = Math.round(video.videoHeight * scale);
  const ctx = canvas.getContext("2d");
  ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
  const dataUrl = canvas.toDataURL("image/jpeg", 0.85);
  const match = dataUrl.match(/^data:([^;]+);base64,(.+)$/);
  return match ? { mimeType: match[1], b64: match[2] } : null;
}

async function grabAndSendLiveFrame() {
  if (!state.liveMirroring || state.liveFrameInFlight || !state.liveSessionId) return;
  const frame = captureCurrentLiveFrameB64();
  if (!frame) return;

  state.liveFrameInFlight = true;
  try {
    const res = await fetch("/api/live/frame", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        session_id: state.liveSessionId,
        image_b64: frame.b64,
        mime_type: frame.mimeType,
        saved_modules: state.savedModules.map((m) => ({
          name: m.name,
          inputs: m.inputs || [],
          outputs: m.outputs || [],
        })),
      }),
    });
    if (!res.ok) return;
    const data = await res.json();
    state.liveFrameCount = data.frame_index || state.liveFrameCount + 1;

    const gatePill = $("live-gate-pill");
    if (!data.usable) {
      gatePill.textContent = `Skipped (${Math.round((data.gate?.usable_prob || 0) * 100)}%)`;
      gatePill.className = "mini-pill warn";
      $("live-status-text").textContent = data.gate?.reason || "Skipped blurry or blocked frame.";
    } else {
      state.liveUsableCount += 1;
      state.liveLastImageB64 = frame.b64;
      state.liveSchematic = data.schematic;

      gatePill.textContent = `Clear (${Math.round((data.gate?.usable_prob || 0) * 100)}%)`;
      gatePill.className = "mini-pill ok";

      if (window.SchematicRenderer) {
        window.SchematicRenderer.render($("live-schematic-canvas"), data.schematic);
      }

      const nEl = (data.schematic?.elements || []).length;
      const nWires = (data.schematic?.wires || []).length;
      const nUnc = (data.schematic?.elements || []).filter((e) => e.uncertain).length;
      $("live-status-text").textContent =
        `${data.schematic?.circuit_title || "Circuit"}: ${nEl} parts, ${nWires} wires` +
        (nUnc ? ` (${nUnc} uncertain)` : "") +
        (data.schematic?.notes ? ` — ${data.schematic.notes}` : "");

      // Hook for Step 2 (Module definition box detection)
      if (typeof onLiveSchematicUpdated === "function") {
        onLiveSchematicUpdated(data.schematic);
      }
    }

    $("live-frame-stats").textContent = `${state.liveUsableCount}/${state.liveFrameCount} usable`;
  } catch (_) {
    // Keep mirroring alive on transient error
  } finally {
    state.liveFrameInFlight = false;
  }
}

async function finishLiveAndBuild() {
  // Capture one crisp final frame if camera is still open and we don't have one yet
  const fresh = captureCurrentLiveFrameB64();
  const finalB64 = fresh?.b64 || state.liveLastImageB64;
  if (!finalB64) {
    alert("No camera frame captured yet. Start Live Mirror and show your circuit first.");
    return;
  }

  pauseLiveMirror();
  await stopAndUploadRecording();
  const finishedSessionId = state.liveSessionId;
  if (finishedSessionId) {
    fetch("/api/live/finish", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ session_id: finishedSessionId }),
    }).catch(() => {});
  }
  stopLiveVideoStream();
  $("live-video-placeholder").classList.remove("hidden");
  $("btn-live-toggle").textContent = "▶ Start Live Mirror";
  state.liveSessionId = null;

  const note = $("live-note").value.trim();
  await startPipeline({
    image_b64: finalB64,
    mime_type: "image/jpeg",
    text_prompt: note || undefined,
    schematic_json: state.liveSchematic || undefined,
    live_session_id: finishedSessionId || undefined,
  });
}

function loadImageFile(file) {
  const reader = new FileReader();
  reader.onload = () => {
    const dataUrl = String(reader.result || "");
    const match = dataUrl.match(/^data:([^;]+);base64,(.+)$/);
    if (!match) return;
    state.mimeType = match[1];
    state.imageB64 = match[2];
    showImagePreview(dataUrl);
  };
  reader.readAsDataURL(file);
}

function showImagePreview(dataUrl) {
  stopCamera();
  $("image-preview").src = dataUrl;
  $("dropzone-empty").classList.add("hidden");
  $("image-preview-wrap").classList.remove("hidden");
}

function clearImage() {
  state.imageB64 = null;
  $("file-input").value = "";
  $("image-preview").src = "";
  $("image-preview-wrap").classList.add("hidden");
  $("dropzone-empty").classList.remove("hidden");
}

async function openCamera() {
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    alert("Camera API is not available in this browser. Please use Upload Photo instead.");
    return;
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: "environment", width: { ideal: 1280 }, height: { ideal: 720 } },
      audio: false,
    });
    state.cameraStream = stream;
    $("camera-video").srcObject = stream;
    $("dropzone-empty").classList.add("hidden");
    $("image-preview-wrap").classList.add("hidden");
    $("camera-view").classList.remove("hidden");
  } catch (err) {
    alert("Could not access camera: " + err.message);
  }
}

function stopCamera() {
  if (state.cameraStream) {
    state.cameraStream.getTracks().forEach((t) => t.stop());
    state.cameraStream = null;
  }
  $("camera-view").classList.add("hidden");
  if (!state.imageB64) {
    $("dropzone-empty").classList.remove("hidden");
  }
}

function captureCameraFrame() {
  const video = $("camera-video");
  const canvas = $("capture-canvas");
  canvas.width = video.videoWidth || 1280;
  canvas.height = video.videoHeight || 720;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
  const dataUrl = canvas.toDataURL("image/jpeg", 0.9);
  const match = dataUrl.match(/^data:([^;]+);base64,(.+)$/);
  if (match) {
    state.mimeType = match[1];
    state.imageB64 = match[2];
    showImagePreview(dataUrl);
  }
}

// --- Toggles ---
function bindToggleEvents() {
  const baseline = $("toggle-baseline");
  const improve = $("toggle-improve");
  const improvePill = improve.closest(".toggle-pill");

  const syncBaselineUI = () => {
    if (baseline.checked) {
      improve.checked = false;
      improvePill.classList.add("disabled");
    } else {
      improvePill.classList.remove("disabled");
    }
  };
  baseline.addEventListener("change", syncBaselineUI);
  syncBaselineUI();
}

// --- Stepper & Stage Card Helpers ---
function setStepper(stepName, status) {
  const pill = document.querySelector(`.step-pill[data-step="${stepName}"]`);
  if (!pill) return;
  pill.classList.remove("running", "done", "error", "rejected", "skipped");
  if (status) pill.classList.add(status);
}

function setCardStatus(stage, status, label) {
  const card = $(`card-${stage}`);
  if (card) card.classList.remove("hidden");
  const badge = $(`status-${stage}`);
  if (badge) {
    badge.className = `status-badge ${status}`;
    badge.textContent = label;
  }
  setStepper(stage, status);
}

function resetPipelineUI() {
  ["gate", "generate", "test", "improve", "lint", "synthesis"].forEach((s) => {
    const c = $(`card-${s}`);
    if (c) c.classList.add("hidden");
    const b = $(`body-${s}`);
    if (b) b.innerHTML = "";
    setStepper(s, "");
  });
  setStepper("input", "done");
  setStepper("board", "");
  stopClock();
}

// --- Run Pipeline (SSE Stream) ---
async function startPipeline(liveOverride = null) {
  if (state.running) return;

  const payload = {
    baseline_mode: $("toggle-baseline").checked,
    enable_improve: $("toggle-improve").checked,
    enable_synthesis: $("toggle-synthesis").checked,
    saved_modules: state.savedModules.length ? state.savedModules : undefined,
  };

  if (liveOverride) {
    Object.assign(payload, liveOverride);
  } else if (state.inputMode === "photo") {
    if (!state.imageB64) {
      alert("Please upload or capture a photo of a circuit diagram first (or switch tabs).");
      return;
    }
    payload.image_b64 = state.imageB64;
    payload.mime_type = state.mimeType;
    const note = $("photo-note").value.trim();
    if (note) payload.text_prompt = note;
  } else if (state.inputMode === "text") {
    const desc = $("text-prompt").value.trim();
    if (!desc) {
      alert("Please type a circuit description first.");
      return;
    }
    payload.text_prompt = desc;
  } else {
    alert("Click 'Done — Build Virtual Hardware' in Live Camera mode, or switch to Photo Upload / Typed Description.");
    return;
  }

  state.running = true;
  $("btn-run").disabled = true;
  $("btn-run-label").textContent = "Running Pipeline...";
  resetPipelineUI();

  const t0 = performance.now();
  const timerInterval = setInterval(() => {
    $("run-timer").textContent = `${((performance.now() - t0) / 1000).toFixed(1)}s`;
  }, 100);

  try {
    const response = await fetch("/api/pipeline/stream", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const err = await response.json().catch(() => ({ error: response.statusText }));
      throw new Error(err.error || "Pipeline request failed");
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });

      const chunks = buffer.split("\n\n");
      buffer = chunks.pop() || "";

      for (const chunk of chunks) {
        const lines = chunk.split("\n");
        let eventName = "message";
        let dataStr = "";
        for (const line of lines) {
          if (line.startsWith("event:")) eventName = line.slice(6).trim();
          else if (line.startsWith("data:")) dataStr += line.slice(5).trim();
        }
        if (!dataStr) continue;
        const data = JSON.parse(dataStr);
        handleSSEEvent(eventName, data);
      }
    }
  } catch (err) {
    alert("Pipeline error: " + err.message);
  } finally {
    clearInterval(timerInterval);
    state.running = false;
    $("btn-run").disabled = false;
    $("btn-run-label").textContent = "Build Virtual Hardware";
  }
}

function handleSSEEvent(eventName, payload) {
  if (eventName === "error") {
    alert("Backend error: " + payload.message);
    return;
  }
  if (eventName === "complete") {
    $("run-timer").textContent = `${(payload.total_duration_ms / 1000).toFixed(1)}s • Saved ${payload.log_file}`;
    return;
  }
  if (eventName !== "stage") return;

  const { stage, status, data } = payload;

  if (stage === "gate") renderGateStage(status, data);
  else if (stage === "generate") renderGenerateStage(status, data);
  else if (stage === "test") renderTestStage(status, data);
  else if (stage === "improve") renderImproveStage(status, data);
  else if (stage === "lint") renderLintStage(status, data);
  else if (stage === "synthesis") renderSynthesisStage(status, data);
  else if (stage === "board") renderBoardStage(status, data);
}

// --- Stage Renderers ---
function renderGateStage(status, data) {
  if (status === "running") {
    setCardStatus("gate", "running", "Evaluating...");
    $("body-gate").innerHTML = `<p class="muted">Checking readability and classifying circuit type with Decision 1...</p>`;
    return;
  }

  const passed = status === "done";
  setCardStatus("gate", passed ? "done" : "rejected", passed ? "Passed" : "Retake Needed");

  const readPct = Math.round((data.readable_prob || 0) * 100);
  const confPct = Math.round((data.readable_confidence || 0) * 100);
  const typeConfPct = Math.round((data.type_confidence || 0) * 100);

  let probsHtml = "";
  if (data.type_probabilities) {
    probsHtml = Object.entries(data.type_probabilities)
      .sort((a, b) => b[1] - a[1])
      .map(([k, v]) => {
        const pct = Math.round(v * 100);
        return `
          <div class="conf-row">
            <span class="conf-row-label">${escapeHtml(k)}</span>
            <div class="conf-track"><div class="conf-fill" style="width:${pct}%"></div></div>
            <span class="conf-pct">${pct}%</span>
          </div>`;
      })
      .join("");
  }

  $("body-gate").innerHTML = `
    <div class="metric-grid">
      <div class="metric-tile">
        <div class="metric-label">Readable Circuit</div>
        <div class="metric-value ${passed ? "green" : "red"}">${readPct}%</div>
      </div>
      <div class="metric-tile">
        <div class="metric-label">Gate Confidence</div>
        <div class="metric-value cyan">${confPct}%</div>
      </div>
      <div class="metric-tile">
        <div class="metric-label">Circuit Type</div>
        <div class="metric-value" style="font-size:1.08rem;font-family:var(--font-sans)">${escapeHtml(data.circuit_type_label)} <small style="color:var(--muted)">(${typeConfPct}%)</small></div>
      </div>
    </div>
    <div class="conf-bar-wrap">${probsHtml}</div>
    <div class="alert-box ${passed ? "success" : "danger"}">${escapeHtml(data.reason)}</div>
  `;
}

function renderGenerateStage(status, data) {
  if (status === "running") {
    setCardStatus("generate", "running", "Generating Verilog...");
    $("body-generate").innerHTML = `<p class="muted">Reading diagram, mapping virtual board pins, and writing synthesizable Verilog + testbench...</p>`;
    return;
  }

  setCardStatus("generate", "done", `Done (${(data.duration_ms / 1000).toFixed(1)}s)`);
  state.latestVerilog = data.verilog_code;
  state.latestTestbench = data.testbench_code;
  state.latestCircuitName = data.circuit_name;
  $("btn-export-vivado").disabled = false;
  $("body-generate").innerHTML = `
    <h3 style="margin:0 0 6px;font-size:1.15rem">${escapeHtml(data.circuit_name)}</h3>
    <p class="muted" style="margin-bottom:10px">${escapeHtml(data.design_summary)}</p>
    <details class="code-details">
      <summary>View Verilog Design (design.v)</summary>
      <pre id="code-verilog">${escapeHtml(data.verilog_code)}</pre>
    </details>
    <details class="code-details">
      <summary>View Self-Checking Testbench (tb.v)</summary>
      <pre id="code-tb">${escapeHtml(data.testbench_code)}</pre>
    </details>
  `;
  renderPinMapping(data.pin_mapping || []);
}

function renderTestStage(status, data) {
  if (status === "running") {
    setCardStatus("test", "running", "Compiling & Simulating...");
    $("body-test").innerHTML = `<p class="muted">Running Icarus Verilog (iverilog + vvp)...</p>`;
    return;
  }

  const ok = !!data.passed;
  setCardStatus("test", ok ? "done" : "error", ok ? "PASS" : "FAIL");
  const logOutput = [data.stdout, data.stderr].filter(Boolean).join("\n\n") || "(no output)";

  $("body-test").innerHTML = `
    <div class="metric-grid">
      <div class="metric-tile">
        <div class="metric-label">Result</div>
        <div class="metric-value ${ok ? "green" : "red"}">${ok ? "PASS" : "FAIL"}</div>
      </div>
      <div class="metric-tile">
        <div class="metric-label">Board Ports</div>
        <div class="metric-value ${data.board_interface_ok ? "green" : "red"}">${data.board_interface_ok ? "OK" : "ERR"}</div>
      </div>
      <div class="metric-tile">
        <div class="metric-label">Sim Time</div>
        <div class="metric-value cyan">${data.duration_ms}ms</div>
      </div>
    </div>
    <p class="muted">${escapeHtml(data.summary)}</p>
    <details class="code-details" ${ok ? "" : "open"}>
      <summary>Compiler &amp; Simulation Output</summary>
      <pre>${escapeHtml(logOutput)}</pre>
    </details>
  `;
}

function renderImproveStage(status, data) {
  if (status === "skipped") {
    setCardStatus("improve", "skipped", "Skipped");
    $("body-improve").innerHTML = `<p class="muted">${escapeHtml(data.reason)}</p>`;
    return;
  }
  if (status === "running") {
    setCardStatus("improve", "running", "Fixing Errors...");
    $("body-improve").innerHTML = `<div id="improve-rounds-list"></div><p class="muted" id="improve-working">Sending errors back to model (up to 5 rounds)...</p>`;
    return;
  }
  if (status === "round") {
    const list = $("improve-rounds-list") || $("body-improve");
    const item = document.createElement("div");
    item.className = "round-item";
    const ok = !!data.passed;
    item.innerHTML = `
      <div class="round-head">
        <span>Round ${data.round}</span>
        <span class="status-badge ${ok ? "done" : "error"}">${ok ? "PASS" : "FAIL"} (${(data.duration_ms / 1000).toFixed(1)}s)</span>
      </div>
      <p class="muted">${escapeHtml(data.fix_summary)}</p>
    `;
    list.appendChild(item);
    return;
  }
  if (status === "done") {
    const working = $("improve-working");
    if (working) working.remove();
    const ok = !!data.passed;
    setCardStatus("improve", ok ? "done" : "error", ok ? `Fixed (${data.rounds_used}r)` : `Failed (${data.rounds_used}r)`);
    if (data.final_verilog) {
      state.latestVerilog = data.final_verilog;
      if ($("code-verilog")) $("code-verilog").textContent = data.final_verilog;
    }
    if (data.final_testbench) {
      state.latestTestbench = data.final_testbench;
      if ($("code-tb")) $("code-tb").textContent = data.final_testbench;
    }
  }
}

function renderLintStage(status, data) {
  if (status === "skipped") {
    setCardStatus("lint", "skipped", "Skipped");
    $("body-lint").innerHTML = `<p class="muted">${escapeHtml(data.reason)}</p>`;
    return;
  }
  if (status === "running") {
    setCardStatus("lint", "running", "Linting...");
    $("body-lint").innerHTML = `<p class="muted">Checking for floating inputs, unconnected outputs, combinational loops, accidental latches, and width mismatches...</p>`;
    return;
  }

  const issues = data.issues || [];
  if (data.clean || !issues.length) {
    setCardStatus("lint", "done", "Clean (0 Issues)");
    $("body-lint").innerHTML = `
      <div class="alert-box success">${escapeHtml(data.summary || "No design issues found.")}</div>
      <p class="muted" style="margin-top:8px;font-size:0.82rem">Checked with: ${escapeHtml((data.tools_used || []).join(", "))}</p>
    `;
    return;
  }

  setCardStatus("lint", "error", `${issues.length} Issue${issues.length > 1 ? "s" : ""}`);
  const body = $("body-lint");
  body.innerHTML = `<p class="muted" style="margin-bottom:10px">${escapeHtml(data.summary || "")}</p>`;

  // Highlight all flagged elements on the drawn schematic
  const allIds = [];
  const allLabels = [];
  issues.forEach((iss) => {
    (iss.schematic_element_ids || []).forEach((id) => allIds.push(id));
    (iss.schematic_labels || []).forEach((lb) => allLabels.push(lb));
    if (iss.signal_name) allLabels.push(iss.signal_name);

    const card = document.createElement("div");
    card.className = `issue-card ${iss.severity === "error" ? "error" : ""}`;
    card.innerHTML = `
      <div class="issue-head">
        <strong>${escapeHtml(iss.title)}</strong>
        <span class="issue-cat">${escapeHtml((iss.category || "issue").replace(/_/g, " "))}</span>
      </div>
      <p style="margin:0;font-size:0.92rem">${escapeHtml(iss.plain_explanation)}</p>
      <div class="issue-fix">💡 Fix: ${escapeHtml(iss.how_to_fix)}</div>
    `;
    card.addEventListener("click", () => {
      if (state.liveSchematic && window.SchematicRenderer) {
        window.SchematicRenderer.render($("live-schematic-canvas"), state.liveSchematic, {
          highlightedIds: iss.schematic_element_ids || [],
          highlightedLabels: [...(iss.schematic_labels || []), iss.signal_name].filter(Boolean),
        });
      }
    });
    body.appendChild(card);
  });

  if (state.liveSchematic && window.SchematicRenderer) {
    window.SchematicRenderer.render($("live-schematic-canvas"), state.liveSchematic, {
      highlightedIds: allIds,
      highlightedLabels: allLabels,
    });
  }
}

function renderSynthesisStage(status, data) {
  if (status === "skipped") {
    setCardStatus("synthesis", "skipped", "Skipped");
    $("body-synthesis").innerHTML = `<p class="muted">${escapeHtml(data.reason)}</p>`;
    return;
  }
  if (status === "running") {
    setCardStatus("synthesis", "running", "Synthesizing...");
    $("body-synthesis").innerHTML = `<p class="muted">Running Yosys synth_xilinx on module top...</p>`;
    return;
  }

  if (!data.ok) {
    setCardStatus("synthesis", "error", "Failed");
    $("body-synthesis").innerHTML = `<div class="alert-box danger">${escapeHtml(data.error || "Synthesis failed")}</div>`;
    return;
  }

  setCardStatus("synthesis", "done", `Done (${(data.duration_ms / 1000).toFixed(1)}s)`);
  const logicTotal = data.logic_total ?? ((data.luts || 0) + (data.ffs || 0) + (data.carries || 0));
  const boardIo = data.board_io ?? data.ios ?? 0;
  const co = data.circuit_only || {};

  const pills = Object.entries(data.cells_by_type || {})
    .sort((a, b) => b[1] - a[1])
    .map(([k, v]) => `<span class="cell-pill">${escapeHtml(k)}: <strong>${v}</strong></span>`)
    .join("");

  const circuitOnlyHtml = co.ok
    ? `
      <div class="synth-subbox">
        <div class="synth-subbox-title">${escapeHtml(co.label || "User Circuit Only (no board wrapper)")}</div>
        <div class="metric-grid" style="margin-bottom:0">
          <div class="metric-tile">
            <div class="metric-label">Circuit LUTs</div>
            <div class="metric-value cyan">${co.luts}</div>
          </div>
          <div class="metric-tile">
            <div class="metric-label">Circuit FFs</div>
            <div class="metric-value green">${co.ffs}</div>
          </div>
          <div class="metric-tile">
            <div class="metric-label">Circuit Logic</div>
            <div class="metric-value">${co.logic_total}</div>
          </div>
        </div>
      </div>`
    : "";

  $("body-synthesis").innerHTML = `
    <div class="metric-grid">
      <div class="metric-tile" style="border-color:rgba(56,189,248,0.45)">
        <div class="metric-label">Logic (LUT+FF+Carry)</div>
        <div class="metric-value cyan">${logicTotal}</div>
      </div>
      <div class="metric-tile">
        <div class="metric-label">LUTs</div>
        <div class="metric-value">${data.luts}</div>
      </div>
      <div class="metric-tile">
        <div class="metric-label">Flip-Flops</div>
        <div class="metric-value green">${data.ffs}</div>
      </div>
      <div class="metric-tile">
        <div class="metric-label">Carry Chains</div>
        <div class="metric-value amber">${data.carries}</div>
      </div>
      <div class="metric-tile" style="opacity:0.82">
        <div class="metric-label">Board I/O (fixed cost)</div>
        <div class="metric-value" style="color:var(--muted)">${boardIo}</div>
      </div>
    </div>
    ${circuitOnlyHtml}
    <div class="cell-pills">${pills}</div>
  `;
}

function renderBoardStage(status, data) {
  if (status === "running") {
    setStepper("board", "running");
    $("status-board").className = "status-badge running";
    $("status-board").textContent = "Loading...";
    return;
  }
  if (status === "error") {
    setStepper("board", "error");
    $("status-board").className = "status-badge error";
    $("status-board").textContent = "Unavailable";
    $("led-sim-live").classList.remove("on");
    return;
  }

  // Board is LIVE!
  state.boardSessionId = data.session_id;
  state.sw = 0;
  state.btn = 0;
  syncSwitchDOM();

  setStepper("board", "done");
  $("status-board").className = "status-badge done";
  $("status-board").textContent = "LIVE";
  $("board-title").textContent = data.circuit_name ? `Virtual Board — ${data.circuit_name}` : "Virtual FPGA Board";
  $("led-sim-live").classList.add("on");

  $("btn-clk-toggle").disabled = false;
  $("btn-clk-step").disabled = false;
  $("btn-reset-sw").disabled = false;

  applyBoardOutputs(data);
  if (data.pin_mapping) renderPinMapping(data.pin_mapping);

  // Auto-start clock for clocked designs so judges immediately see counters/FSMs running!
  const hz = Math.max(1, Math.min(15, data.recommended_clock_hz || 4));
  state.clockHz = hz;
  $("clk-hz-slider").value = String(hz);
  $("clk-hz-label").textContent = `${hz} Hz`;

  if (data.is_clocked) {
    startClock();
  } else {
    stopClock();
  }
}

function renderPinMapping(items) {
  const box = $("pin-map-box");
  if (!items || !items.length) {
    box.innerHTML = `<h3>Board Pin Mapping</h3><p class="muted">No pin mapping provided.</p>`;
    return;
  }
  const rows = items
    .map(
      (p) => `
      <tr>
        <td><span class="pin-chip">${escapeHtml(p.board_pin)}</span></td>
        <td><strong>${escapeHtml(p.signal_name)}</strong></td>
        <td class="${p.direction === "input" ? "dir-in" : "dir-out"}">${escapeHtml(p.direction)}</td>
        <td>${escapeHtml(p.description)}</td>
      </tr>`
    )
    .join("");

  box.innerHTML = `
    <h3>Board Pin Mapping</h3>
    <table class="pin-table">
      <thead><tr><th>Board Pin</th><th>Signal</th><th>Dir</th><th>Behavior</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>
  `;
}

// --- Interactive Virtual FPGA Board Controls ---
function bindBoardEvents() {
  // 5 Pushbuttons: press & release
  document.querySelectorAll(".fpga-btn").forEach((el) => {
    const bit = Number(el.dataset.btn);
    const press = (e) => {
      e.preventDefault();
      el.classList.add("pressed");
      state.btn |= 1 << bit;
      // If clock is paused, advance 1 cycle on button press for synchronous resets/inputs?
      // Better: evaluate immediately (0 cycles) so combinational & held-button work,
      // and if clock is running it naturally clocks while held!
      sendBoardStep(0);
    };
    const release = () => {
      if (!el.classList.contains("pressed")) return;
      el.classList.remove("pressed");
      state.btn &= ~(1 << bit);
      sendBoardStep(0);
    };
    el.addEventListener("pointerdown", press);
    el.addEventListener("pointerup", release);
    el.addEventListener("pointerleave", release);
    el.addEventListener("pointercancel", release);
  });

  $("btn-clk-toggle").addEventListener("click", () => {
    if (state.clockRunning) stopClock();
    else startClock();
  });

  $("btn-clk-step").addEventListener("click", () => sendBoardStep(1));

  $("clk-hz-slider").addEventListener("input", (e) => {
    state.clockHz = Number(e.target.value);
    $("clk-hz-label").textContent = `${state.clockHz} Hz`;
    if (state.clockRunning) {
      stopClock();
      startClock();
    }
  });

  $("btn-reset-sw").addEventListener("click", () => {
    state.sw = 0;
    syncSwitchDOM();
    sendBoardStep(0);
  });

  $("btn-export-vivado").addEventListener("click", exportVivadoZip);
}

async function exportVivadoZip() {
  if (!state.latestVerilog) {
    alert("Build a circuit first to export a Vivado project.");
    return;
  }
  const btn = $("btn-export-vivado");
  btn.disabled = true;
  try {
    const res = await fetch("/api/export/vivado", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        verilog_code: state.latestVerilog,
        testbench_code: state.latestTestbench,
        circuit_name: state.latestCircuitName || "fpga_design",
      }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: res.statusText }));
      throw new Error(err.error || "Export failed");
    }
    const blob = await res.blob();
    const disp = res.headers.get("Content-Disposition") || "";
    const match = disp.match(/filename="([^"]+)"/);
    const filename = match ? match[1] : "vivado_project_untested.zip";
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  } catch (err) {
    alert("Vivado export error: " + err.message);
  } finally {
    btn.disabled = false;
  }
}

function toggleSwitch(bit) {
  state.sw ^= 1 << bit;
  syncSwitchDOM();
  sendBoardStep(0);
}

function syncSwitchDOM() {
  for (let i = 0; i < 16; i++) {
    const el = $(`sw-${i}`);
    if (el) el.classList.toggle("on", Boolean(state.sw & (1 << i)));
  }
}

function startClock() {
  if (!state.boardSessionId) return;
  stopClock();
  state.clockRunning = true;
  $("btn-clk-toggle").textContent = "⏸ Pause Clock";
  $("btn-clk-toggle").classList.add("running");

  const intervalMs = Math.max(60, Math.round(1000 / state.clockHz));
  state.clockTimer = setInterval(() => {
    if (!state.stepInFlight) {
      sendBoardStep(1);
    }
  }, intervalMs);
}

function stopClock() {
  if (state.clockTimer) {
    clearInterval(state.clockTimer);
    state.clockTimer = null;
  }
  state.clockRunning = false;
  $("btn-clk-toggle").textContent = "▶ Run Clock";
  $("btn-clk-toggle").classList.remove("running");
  $("led-clk-pulse").classList.remove("pulse");
}

async function sendBoardStep(cycles) {
  if (!state.boardSessionId) return;
  if (state.stepInFlight) {
    state.pendingSync = true;
    return;
  }

  state.stepInFlight = true;
  if (cycles > 0) {
    $("led-clk-pulse").classList.toggle("pulse");
  }

  try {
    const res = await fetch("/api/board/step", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        session_id: state.boardSessionId,
        sw: state.sw,
        btn: state.btn,
        cycles,
      }),
    });
    if (res.ok) {
      const data = await res.json();
      applyBoardOutputs(data);
    }
  } catch (_) {
    // Ignore transient network errors during rapid clicking
  } finally {
    state.stepInFlight = false;
    if (state.pendingSync) {
      state.pendingSync = false;
      sendBoardStep(0);
    }
  }
}

function applyBoardOutputs(data) {
  state.led = data.led || 0;
  for (let i = 0; i < 16; i++) {
    const bulb = $(`led-${i}`);
    if (bulb) bulb.classList.toggle("on", Boolean(state.led & (1 << i)));
  }

  const digits = data.digits || [0x7f, 0x7f, 0x7f, 0x7f];
  state.digits = digits;
  for (let d = 0; d < 4; d++) {
    const svg = document.querySelector(`.digit-svg[data-digit="${d}"]`);
    if (!svg) continue;
    const segMask = digits[d]; // active-low: bit s == 0 means segment s is ON
    svg.querySelectorAll(".seg-path").forEach((poly) => {
      const s = Number(poly.dataset.seg);
      const isLit = (segMask & (1 << s)) === 0;
      poly.classList.toggle("lit", isLit);
    });
  }

  if (typeof data.cycles === "number") {
    $("cycle-count").textContent = String(data.cycles);
  }
}

// --- Module Library Side Panel & Hierarchy ---
function bindModulesEvents() {
  $("btn-modules-drawer").addEventListener("click", () => {
    $("modules-drawer").classList.toggle("hidden");
    renderModulesDrawer();
  });
  $("btn-close-modules").addEventListener("click", () => {
    $("modules-drawer").classList.add("hidden");
  });
  $("btn-save-mod").addEventListener("click", () => {
    const name = $("input-mod-name").value.trim();
    saveCurrentAsModule(name);
  });
  $("btn-export-lib").addEventListener("click", exportModuleLibrary);
  $("btn-import-lib").addEventListener("click", () => $("import-lib-file").click());
  $("import-lib-file").addEventListener("change", (e) => {
    const file = e.target.files?.[0];
    if (file) importModuleLibraryFile(file);
    e.target.value = "";
  });
}

async function fetchSavedModules() {
  try {
    const res = await fetch("/api/modules");
    if (!res.ok) return;
    const data = await res.json();
    state.savedModules = data.modules || [];
    $("modules-count").textContent = String(state.savedModules.length);
    renderModulesDrawer();
  } catch (_) {}
}

function onLiveSchematicUpdated(schematic) {
  const bar = $("live-detected-box-bar");
  if (!bar) return;
  const defBox = (schematic?.boxes || []).find((b) => b.is_definition && b.name);
  if (!defBox) {
    bar.classList.add("hidden");
    return;
  }
  bar.classList.remove("hidden");
  bar.innerHTML = `
    <span>Detected module box <strong>${escapeHtml(defBox.name)}</strong> with gates inside.</span>
    <button type="button" class="btn-primary" style="padding:6px 14px;font-size:0.86rem" id="btn-quick-save-box">
      Save "${escapeHtml(defBox.name)}" to Library
    </button>
  `;
  $("btn-quick-save-box").addEventListener("click", () => {
    $("modules-drawer").classList.remove("hidden");
    $("input-mod-name").value = defBox.name;
    saveCurrentAsModule(defBox.name);
  });
}

async function saveCurrentAsModule(name) {
  if (!name) {
    alert("Please enter a module name (e.g. HALF_ADDER).");
    return;
  }
  const payload = { name };

  if (state.inputMode === "live") {
    const fresh = captureCurrentLiveFrameB64();
    const b64 = fresh?.b64 || state.liveLastImageB64;
    if (!b64 && !state.liveSchematic) {
      alert("Show your drawn module on the live camera first.");
      return;
    }
    if (b64) {
      payload.image_b64 = b64;
      payload.mime_type = "image/jpeg";
    }
    if (state.liveSchematic) payload.schematic_json = state.liveSchematic;
    const note = $("live-note").value.trim();
    if (note) payload.text_prompt = note;
  } else if (state.inputMode === "photo") {
    if (!state.imageB64) {
      alert("Upload or capture a photo first.");
      return;
    }
    payload.image_b64 = state.imageB64;
    payload.mime_type = state.mimeType;
    const note = $("photo-note").value.trim();
    if (note) payload.text_prompt = note;
  } else {
    const desc = $("text-prompt").value.trim();
    if (!desc) {
      alert("Type a circuit description first.");
      return;
    }
    payload.text_prompt = desc;
  }

  $("btn-save-mod").disabled = true;
  $("mod-save-status").textContent = `Generating & testing standalone Verilog module "${name}"...`;

  try {
    const res = await fetch("/api/modules/save", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || "Failed to save module");

    state.savedModules = data.modules || [];
    $("modules-count").textContent = String(state.savedModules.length);
    $("input-mod-name").value = "";
    const mod = data.module;
    $("mod-save-status").textContent = mod.test_passed
      ? `Saved "${mod.name}" (${mod.verilog_module_name}) — standalone test PASSED!`
      : `Saved "${mod.name}" — warning: standalone test failed.`;
    renderModulesDrawer();
  } catch (err) {
    $("mod-save-status").textContent = `Error: ${err.message}`;
  } finally {
    $("btn-save-mod").disabled = false;
  }
}

function renderModulesDrawer() {
  const list = $("modules-list");
  if (!list) return;
  if (!state.savedModules.length) {
    list.innerHTML = `<p class="muted">No saved modules yet. Draw a circuit inside a box with a corner name (or type one above) to save a reusable Verilog module.</p>`;
    return;
  }

  list.innerHTML = "";
  state.savedModules.forEach((mod, idx) => {
    const card = document.createElement("div");
    card.className = "mod-card";

    const inChips = (mod.inputs || [])
      .map((p) => `<span class="pin-chip">IN ${escapeHtml(p.name)}${p.width > 1 ? `[${p.width - 1}:0]` : ""}</span>`)
      .join("");
    const outChips = (mod.outputs || [])
      .map((p) => `<span class="pin-chip" style="color:#4ade80">OUT ${escapeHtml(p.name)}${p.width > 1 ? `[${p.width - 1}:0]` : ""}</span>`)
      .join("");

    card.innerHTML = `
      <div class="mod-card-head">
        <div>
          <strong>${escapeHtml(mod.name)}</strong>
          <span class="model-tag">${escapeHtml(mod.verilog_module_name)}</span>
        </div>
        <div style="display:flex;align-items:center;gap:6px">
          <span class="status-badge ${mod.test_passed ? "done" : "error"}">${mod.test_passed ? "PASS" : "FAIL"}</span>
          <button type="button" class="btn-ghost" style="padding:3px 8px;font-size:0.78rem" data-del-mod="${escapeHtml(mod.name)}">✕</button>
        </div>
      </div>
      <div class="mod-mini-schematic" id="mod-thumb-${idx}"></div>
      <div class="mod-ports">${inChips}${outChips}</div>
      <p class="muted" style="font-size:0.82rem">${escapeHtml(mod.description || "")}</p>
      <details class="code-details">
        <summary>Module Verilog</summary>
        <pre>${escapeHtml(mod.verilog_code || "")}</pre>
      </details>
    `;

    list.appendChild(card);

    // Render mini SVG schematic thumbnail
    const thumb = card.querySelector(`#mod-thumb-${idx}`);
    if (thumb && window.SchematicRenderer) {
      const miniSchematic = mod.schematic_json || buildFallbackModuleSchematic(mod);
      window.SchematicRenderer.render(thumb, miniSchematic, { compact: true });
    }

    card.querySelector("[data-del-mod]").addEventListener("click", async () => {
      const res = await fetch("/api/modules/delete", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: mod.name }),
      });
      if (res.ok) {
        const data = await res.json();
        state.savedModules = data.modules || [];
        $("modules-count").textContent = String(state.savedModules.length);
        renderModulesDrawer();
      }
    });
  });
}

function buildFallbackModuleSchematic(mod) {
  const elements = [
    { id: "m", type: "module_instance", label: mod.name, module_name: mod.name, x: 50, y: 50, confidence: 1, uncertain: false },
  ];
  const wires = [];
  (mod.inputs || []).forEach((p, i, arr) => {
    const y = ((i + 1) / (arr.length + 1)) * 84 + 8;
    elements.push({ id: `in_${i}`, type: "input", label: p.name, x: 14, y, confidence: 1, uncertain: false });
    wires.push({ from_id: `in_${i}`, to_id: "m" });
  });
  (mod.outputs || []).forEach((p, i, arr) => {
    const y = ((i + 1) / (arr.length + 1)) * 84 + 8;
    elements.push({ id: `out_${i}`, type: "output", label: p.name, x: 86, y, confidence: 1, uncertain: false });
    wires.push({ from_id: "m", to_id: `out_${i}` });
  });
  return { circuit_title: mod.name, elements, boxes: [], wires, notes: "" };
}

function exportModuleLibrary() {
  const payload = { version: 1, modules: state.savedModules };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "fpga_module_library.json";
  a.click();
  URL.revokeObjectURL(url);
}

function importModuleLibraryFile(file) {
  const reader = new FileReader();
  reader.onload = async () => {
    try {
      const parsed = JSON.parse(String(reader.result || "{}"));
      const res = await fetch("/api/modules/import", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ library: parsed, replace: false }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Import failed");
      state.savedModules = data.modules || [];
      $("modules-count").textContent = String(state.savedModules.length);
      $("mod-save-status").textContent = `Loaded ${state.savedModules.length} module(s) from ${file.name}.`;
      renderModulesDrawer();
    } catch (err) {
      alert("Could not load library file: " + err.message);
    }
  };
  reader.readAsText(file);
}

// --- Saved Runs Modal ---
function bindHistoryModal() {
  $("btn-history").addEventListener("click", async () => {
    $("history-modal").classList.remove("hidden");
    $("history-list").innerHTML = `<p class="muted">Loading saved runs...</p>`;
    try {
      const res = await fetch("/api/runs");
      const data = await res.json();
      const runs = data.runs || [];
      if (!runs.length) {
        $("history-list").innerHTML = `<p class="muted">No saved runs yet. Run a circuit to log it to <code>app/runs/</code>.</p>`;
        return;
      }
      $("history-list").innerHTML = runs
        .map((r) => {
          const testBadge =
            r.test_passed === true
              ? `<span class="status-badge done">PASS</span>`
              : r.test_passed === false
              ? `<span class="status-badge error">FAIL</span>`
              : `<span class="status-badge rejected">GATE</span>`;
          const synthTxt =
            r.luts != null ? `${r.luts} LUTs / ${r.ffs} FFs` : "—";
          return `
            <div class="history-row">
              <div>
                <strong>${escapeHtml(r.circuit_name || r.run_id)}</strong>
                <div class="muted" style="font-size:0.82rem">
                  ${escapeHtml(r.run_id)} • Mode: <strong>${escapeHtml(r.mode)}</strong> • Rounds: ${r.improve_rounds} • Synth: ${synthTxt}
                </div>
              </div>
              <div style="display:flex;align-items:center;gap:10px">
                <span class="muted" style="font-family:var(--font-mono);font-size:0.85rem">${((r.total_duration_ms || 0) / 1000).toFixed(1)}s</span>
                ${testBadge}
              </div>
            </div>`;
        })
        .join("");
    } catch (err) {
      $("history-list").innerHTML = `<div class="alert-box danger">Failed to load runs: ${escapeHtml(err.message)}</div>`;
    }
  });

  $("btn-close-history").addEventListener("click", () => {
    $("history-modal").classList.add("hidden");
  });
  $("history-modal").addEventListener("click", (e) => {
    if (e.target === $("history-modal")) $("history-modal").classList.add("hidden");
  });
}

function escapeHtml(str) {
  return String(str ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

document.addEventListener("DOMContentLoaded", init);
