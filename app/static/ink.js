/* Clean Persistent Digital Ink Canvas (25-30 fps, local no-AI).
 *
 * Turns live camera video of paper into a clean iPad-like drawing canvas:
 * - Plain background (#09090b), ONLY pen strokes (no camera image, shadows, or paper grain)
 * - Persistent accumulated canvas: pixels become ink only after staying dark
 *   for ~180-200 ms (5 consecutive frames), filtering out moving hands/pens
 * - Hand & shadow rejection: masks skin-coloured regions (YCbCr) and large dark blobs
 * - Noise & ruled-paper rejection: masks frame margins, non-paper areas, faint
 *   straight ruled lines, and isolated specks
 * - Stroke cleaning: thins committed ink and renders crisp smooth strokes of
 *   consistent thickness
 * - Supports 0/90/180/270-degree rotation and Clear Canvas
 */

window.FastInkEngine = (function () {
  const INK_W = 480;
  const INK_H = 300;
  const BG_W = 24;
  const BG_H = 15;
  const CELL = 10; // 10x10 px grid for fast hand/blob masking
  const GRID_W = INK_W / CELL; // 48
  const GRID_H = INK_H / CELL; // 30
  const MARGIN = 12; // Ignore outer 12px edge shadows
  const CONFIRM_FRAMES = 5; // ~200ms at 25fps

  function create({ videoEl, outCanvas, fpsEl, threshold = 28, targetFps = 25 }) {
    const outCtx = outCanvas.getContext("2d", { alpha: false });
    outCanvas.width = INK_W;
    outCanvas.height = INK_H;

    // Offscreen scratch canvases
    const frameCanvas = document.createElement("canvas");
    frameCanvas.width = INK_W;
    frameCanvas.height = INK_H;
    const frameCtx = frameCanvas.getContext("2d", { willReadFrequently: true });

    const tinyCanvas = document.createElement("canvas");
    tinyCanvas.width = BG_W;
    tinyCanvas.height = BG_H;
    const tinyCtx = tinyCanvas.getContext("2d");

    const bgCanvas = document.createElement("canvas");
    bgCanvas.width = INK_W;
    bgCanvas.height = INK_H;
    const bgCtx = bgCanvas.getContext("2d", { willReadFrequently: true });

    // Persistent buffers
    const N = INK_W * INK_H;
    const streak = new Uint8Array(N);      // Consecutive dark frames per pixel
    const committed = new Uint8Array(N);   // Persistent confirmed ink mask (0 or 1)
    const rawDark = new Uint8Array(N);     // Current-frame raw dark candidates
    const thinned = new Uint8Array(N);     // Thinned/cleaned stroke mask
    const tmpThin = new Uint8Array(N);

    // Coarse grid buffers for hand (skin) + large dark blob masking
    const G = GRID_W * GRID_H;
    const skinGrid = new Uint8Array(G);
    const darkGrid = new Uint8Array(G);
    const blockMask = new Uint8Array(G);
    const rowFaint = new Uint16Array(INK_H);
    const colFaint = new Uint16Array(INK_W);

    let running = false;
    let rafId = null;
    let lastDrawTs = 0;
    let currentThreshold = threshold;
    let rotationDeg = 0; // 0, 90, 180, 270
    let mirrorX = false;
    let fpsFrames = 0;
    let fpsWindowStart = performance.now();
    let hasCommittedAny = false;
    const minFrameMs = Math.round(1000 / targetFps);

    function clearBuffers() {
      streak.fill(0);
      committed.fill(0);
      thinned.fill(0);
      hasCommittedAny = false;
      renderCleanCanvas();
    }

    function drawIdleCanvas() {
      outCtx.fillStyle = "#09090b";
      outCtx.fillRect(0, 0, INK_W, INK_H);
      outCtx.fillStyle = "#52525b";
      outCtx.font = "13px Geist, -apple-system, sans-serif";
      outCtx.textAlign = "center";
      outCtx.fillText("Clean digital ink canvas — starts with camera", INK_W / 2, INK_H / 2);
    }

    // Draw rotated + optionally mirrored video frame onto frameCanvas
    function drawRotatedVideo() {
      frameCtx.save();
      frameCtx.fillStyle = "#000";
      frameCtx.fillRect(0, 0, INK_W, INK_H);
      frameCtx.translate(INK_W / 2, INK_H / 2);
      if (rotationDeg !== 0) {
        frameCtx.rotate((rotationDeg * Math.PI) / 180);
      }
      if (mirrorX) {
        frameCtx.scale(-1, 1);
      }
      const swap = rotationDeg === 90 || rotationDeg === 270;
      const drawW = swap ? INK_H : INK_W;
      const drawH = swap ? INK_W : INK_H;
      frameCtx.drawImage(videoEl, -drawW / 2, -drawH / 2, drawW, drawH);
      frameCtx.restore();
    }

    // Fast 2-pass morphological thinning (Zhang-Suen-lite) + speck cleanup
    function cleanAndThinStrokes() {
      // 1. Copy committed while removing isolated 1-2px specks
      thinned.fill(0);
      for (let y = 1; y < INK_H - 1; y++) {
        const row = y * INK_W;
        for (let x = 1; x < INK_W - 1; x++) {
          const i = row + x;
          if (!committed[i]) continue;
          const nb =
            committed[i - INK_W - 1] + committed[i - INK_W] + committed[i - INK_W + 1] +
            committed[i - 1] + committed[i + 1] +
            committed[i + INK_W - 1] + committed[i + INK_W] + committed[i + INK_W + 1];
          if (nb >= 2) thinned[i] = 1;
        }
      }

      // 2. Two gentle thinning passes to normalize thick/uneven pen strokes
      for (let pass = 0; pass < 2; pass++) {
        tmpThin.set(thinned);
        for (let y = 1; y < INK_H - 1; y++) {
          const row = y * INK_W;
          for (let x = 1; x < INK_W - 1; x++) {
            const i = row + x;
            if (!thinned[i]) continue;
            const p2 = thinned[i - INK_W];
            const p3 = thinned[i - INK_W + 1];
            const p4 = thinned[i + 1];
            const p5 = thinned[i + INK_W + 1];
            const p6 = thinned[i + INK_W];
            const p7 = thinned[i + INK_W - 1];
            const p8 = thinned[i - 1];
            const p9 = thinned[i - INK_W - 1];
            const B = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9;
            if (B < 3 || B > 6) continue;
            const A =
              (p2 === 0 && p3 === 1 ? 1 : 0) +
              (p3 === 0 && p4 === 1 ? 1 : 0) +
              (p4 === 0 && p5 === 1 ? 1 : 0) +
              (p5 === 0 && p6 === 1 ? 1 : 0) +
              (p6 === 0 && p7 === 1 ? 1 : 0) +
              (p7 === 0 && p8 === 1 ? 1 : 0) +
              (p8 === 0 && p9 === 1 ? 1 : 0) +
              (p9 === 0 && p2 === 1 ? 1 : 0);
            if (A !== 1) continue;
            if (pass === 0) {
              if (p2 * p4 * p6 === 0 && p4 * p6 * p8 === 0) tmpThin[i] = 0;
            } else {
              if (p2 * p4 * p8 === 0 && p2 * p6 * p8 === 0) tmpThin[i] = 0;
            }
          }
        }
        thinned.set(tmpThin);
      }
    }

    // Render ONLY clean smooth strokes of consistent thickness on plain #09090b background
    function renderCleanCanvas() {
      outCtx.fillStyle = "#09090b";
      outCtx.fillRect(0, 0, INK_W, INK_H);

      if (!hasCommittedAny) return;

      // Draw crisp anti-aliased uniform-thickness strokes (2.2px diameter)
      outCtx.fillStyle = "rgba(56, 189, 248, 0.22)";
      for (let y = 1; y < INK_H - 1; y++) {
        const row = y * INK_W;
        for (let x = 1; x < INK_W - 1; x++) {
          if (thinned[row + x]) {
            outCtx.fillRect(x - 1.5, y - 1.5, 3.2, 3.2);
          }
        }
      }

      outCtx.fillStyle = "#f4f4f5";
      for (let y = 1; y < INK_H - 1; y++) {
        const row = y * INK_W;
        for (let x = 1; x < INK_W - 1; x++) {
          if (thinned[row + x]) {
            outCtx.fillRect(x - 0.85, y - 0.85, 2.0, 2.0);
          }
        }
      }
    }

    function tick(now) {
      if (!running) return;
      rafId = requestAnimationFrame(tick);

      if (now - lastDrawTs < minFrameMs) return;
      if (!videoEl || videoEl.readyState < 2 || !videoEl.videoWidth) return;
      lastDrawTs = now;

      // 1. Grab rotated frame
      drawRotatedVideo();
      const src = frameCtx.getImageData(0, 0, INK_W, INK_H).data;

      // 2. Estimate smooth local paper brightness (downscale -> upscale)
      tinyCtx.drawImage(frameCanvas, 0, 0, BG_W, BG_H);
      bgCtx.imageSmoothingEnabled = true;
      bgCtx.drawImage(tinyCanvas, 0, 0, INK_W, INK_H);
      const bg = bgCtx.getImageData(0, 0, INK_W, INK_H).data;

      // Estimate overall paper brightness floor from center region
      let bgSum = 0;
      let bgCnt = 0;
      for (let y = 40; y < INK_H - 40; y += 8) {
        const row = y * INK_W;
        for (let x = 40; x < INK_W - 40; x += 8) {
          const p = (row + x) << 2;
          bgSum += (77 * bg[p] + 150 * bg[p + 1] + 29 * bg[p + 2]) >> 8;
          bgCnt++;
        }
      }
      const meanPaperLuma = bgCnt ? bgSum / bgCnt : 160;
      const paperMinLuma = Math.max(85, meanPaperLuma * 0.62);

      // 3. Pass 1: Detect skin pixels (hand), dark candidates, and ruled-paper line stats
      skinGrid.fill(0);
      darkGrid.fill(0);
      rawDark.fill(0);
      rowFaint.fill(0);
      colFaint.fill(0);

      const thresh = currentThreshold;
      const faintLo = Math.max(8, thresh * 0.45);
      const faintHi = thresh * 1.35;

      for (let y = MARGIN; y < INK_H - MARGIN; y++) {
        const row = y * INK_W;
        const gy = (y / CELL) | 0;
        const gRow = gy * GRID_W;
        for (let x = MARGIN; x < INK_W - MARGIN; x++) {
          const i = row + x;
          const p = i << 2;
          const r = src[p];
          const g = src[p + 1];
          const b = src[p + 2];

          const gx = (x / CELL) | 0;
          const gi = gRow + gx;

          // Skin-colour detection (YCbCr + RGB dominance) -> masks hand & fingers
          const maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
          const minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
          if (r > 70 && g > 35 && b > 18 && r > g && r > b && (maxC - minC) > 12) {
            const cb = 128 - 0.1687 * r - 0.3313 * g + 0.5 * b;
            const cr = 128 + 0.5 * r - 0.4187 * g - 0.0813 * b;
            if (cb >= 77 && cb <= 130 && cr >= 131 && cr <= 178) {
              skinGrid[gi]++;
              continue;
            }
          }

          const bgLuma = (77 * bg[p] + 150 * bg[p + 1] + 29 * bg[p + 2]) >> 8;
          // Ignore non-paper dark desk / edge shadows
          if (bgLuma < paperMinLuma) continue;

          const luma = (77 * r + 150 * g + 29 * b) >> 8;
          const diff = bgLuma - luma;

          // Track faint straight ruled-paper lines
          if (diff > faintLo && diff < faintHi) {
            rowFaint[y]++;
            colFaint[x]++;
          }

          if (diff > thresh && luma < 175) {
            rawDark[i] = 1;
            darkGrid[gi]++;
          }
        }
      }

      // 4. Build dilated hand + large-blob exclusion mask on coarse 48x30 grid
      blockMask.fill(0);
      for (let gy = 0; gy < GRID_H; gy++) {
        for (let gx = 0; gx < GRID_W; gx++) {
          const gi = gy * GRID_W + gx;
          // Skin cluster (>10% skin in 10x10 block) OR large dark blob (>52% dark in 10x10 block)
          const isHand = skinGrid[gi] >= 10;
          const isBlob = darkGrid[gi] >= 52;
          if (isHand || isBlob) {
            const rad = isHand ? 2 : 1; // Larger halo around hand to block its cast shadow
            for (let dy = -rad; dy <= rad; dy++) {
              const ny = gy + dy;
              if (ny < 0 || ny >= GRID_H) continue;
              for (let dx = -rad; dx <= rad; dx++) {
                const nx = gx + dx;
                if (nx < 0 || nx >= GRID_W) continue;
                blockMask[ny * GRID_W + nx] = 1;
              }
            }
          }
        }
      }

      // 5. Temporal confirmation (~200ms) + ruled-line & speck filtering
      const rowRuleLimit = Math.round((INK_W - MARGIN * 2) * 0.42);
      const colRuleLimit = Math.round((INK_H - MARGIN * 2) * 0.42);
      let newlyCommitted = false;

      for (let y = MARGIN + 1; y < INK_H - MARGIN - 1; y++) {
        const isRuledRow = rowFaint[y] > rowRuleLimit;
        const row = y * INK_W;
        const gy = (y / CELL) | 0;
        const gRow = gy * GRID_W;

        for (let x = MARGIN + 1; x < INK_W - MARGIN - 1; x++) {
          const i = row + x;
          if (committed[i]) continue; // Already permanent ink

          const gx = (x / CELL) | 0;
          if (blockMask[gRow + gx]) {
            // Hand/blob covering this area -> freeze streak, never commit
            streak[i] = 0;
            continue;
          }

          if (isRuledRow || colFaint[x] > colRuleLimit) {
            // Require extra-strong ink to punch through a ruled line
            const p = i << 2;
            const luma = (77 * src[p] + 150 * src[p + 1] + 29 * src[p + 2]) >> 8;
            const bgLuma = (77 * bg[p] + 150 * bg[p + 1] + 29 * bg[p + 2]) >> 8;
            if (bgLuma - luma < thresh + 18) {
              streak[i] = 0;
              continue;
            }
          }

          if (rawDark[i]) {
            // Speck filter: require >= 2 dark 8-neighbors
            const nb =
              rawDark[i - INK_W - 1] + rawDark[i - INK_W] + rawDark[i - INK_W + 1] +
              rawDark[i - 1] + rawDark[i + 1] +
              rawDark[i + INK_W - 1] + rawDark[i + INK_W] + rawDark[i + INK_W + 1];
            if (nb >= 2) {
              const s = streak[i] + 1;
              streak[i] = s > 250 ? 250 : s;
              if (s >= CONFIRM_FRAMES) {
                committed[i] = 1;
                hasCommittedAny = true;
                newlyCommitted = true;
              }
            } else {
              streak[i] = 0;
            }
          } else {
            streak[i] = 0;
          }
        }
      }

      if (newlyCommitted) {
        cleanAndThinStrokes();
        renderCleanCanvas();
      }

      // Live FPS counter
      fpsFrames += 1;
      if (now - fpsWindowStart >= 1000) {
        const fps = Math.round((fpsFrames * 1000) / (now - fpsWindowStart));
        if (fpsEl) fpsEl.textContent = `${fps} fps`;
        fpsFrames = 0;
        fpsWindowStart = now;
      }
    }

    drawIdleCanvas();

    return {
      start() {
        if (running) return;
        running = true;
        fpsFrames = 0;
        fpsWindowStart = performance.now();
        renderCleanCanvas();
        rafId = requestAnimationFrame(tick);
      },
      stop() {
        running = false;
        if (rafId !== null) {
          cancelAnimationFrame(rafId);
          rafId = null;
        }
        if (fpsEl) fpsEl.textContent = "Idle";
      },
      setThreshold(val) {
        currentThreshold = Math.max(10, Math.min(60, Number(val) || 28));
      },
      setRotation(deg) {
        rotationDeg = ((Number(deg) || 0) % 360 + 360) % 360;
        streak.fill(0);
      },
      getRotation() {
        return rotationDeg;
      },
      setMirror(flag) {
        mirrorX = Boolean(flag);
        streak.fill(0);
      },
      getMirror() {
        return mirrorX;
      },
      clear() {
        clearBuffers();
      },
      reset() {
        clearBuffers();
        if (!running) drawIdleCanvas();
      },
    };
  }

  return { create };
})();
