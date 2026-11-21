/* Clean Persistent Digital Ink Canvas + Raw Ink Mode + Filter Debug Overlay (25-30 fps, local no-AI).
 *
 * Modes:
 * - "clean": Persistent accumulated clean strokes on plain #09090b background (~80ms confirm,
 *            gentle hand/blob/ruled-line/speck filtering, smooth uniform stroke rendering).
 * - "raw":   Direct real-time filtered camera ink view (instant fallback).
 * - debug:   Color-coded overlay showing exactly which filter removes which pixels + live counts.
 */

window.FastInkEngine = (function () {
  const INK_W = 480;
  const INK_H = 300;
  const BG_W = 24;
  const BG_H = 15;
  const CELL = 10;
  const GRID_W = INK_W / CELL; // 48
  const GRID_H = INK_H / CELL; // 30
  const MARGIN = 8;
  const CONFIRM_FRAMES = 2; // ~80ms at 25fps

  function create({ videoEl, outCanvas, fpsEl, threshold = 16, targetFps = 25 }) {
    const outCtx = outCanvas.getContext("2d", { alpha: false });
    outCanvas.width = INK_W;
    outCanvas.height = INK_H;

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

    const outImg = outCtx.createImageData(INK_W, INK_H);
    const outBuf = outImg.data;

    const N = INK_W * INK_H;
    const streak = new Uint8Array(N);
    const committed = new Uint8Array(N);
    const rawDark = new Uint8Array(N);
    const cleaned = new Uint8Array(N);

    const G = GRID_W * GRID_H;
    const skinGrid = new Uint8Array(G);
    const darkGrid = new Uint8Array(G);
    const handMask = new Uint8Array(G);
    const blobMask = new Uint8Array(G);
    const rowFaint = new Uint16Array(INK_H);
    const colFaint = new Uint16Array(INK_W);

    let running = false;
    let rafId = null;
    let lastDrawTs = 0;
    let currentThreshold = threshold;
    let rotationDeg = 0;
    let mirrorX = false;
    let mode = "clean"; // "clean" | "raw"
    let debugEnabled = false;
    let fpsFrames = 0;
    let fpsWindowStart = performance.now();
    let hasCommittedAny = false;
    let committedCount = 0;
    const minFrameMs = Math.round(1000 / targetFps);

    function clearBuffers() {
      streak.fill(0);
      committed.fill(0);
      cleaned.fill(0);
      hasCommittedAny = false;
      committedCount = 0;
      if (mode === "clean") renderCleanCanvas();
    }

    function drawIdleCanvas() {
      outCtx.fillStyle = "#09090b";
      outCtx.fillRect(0, 0, INK_W, INK_H);
      outCtx.fillStyle = "#52525b";
      outCtx.font = "13px Geist, -apple-system, sans-serif";
      outCtx.textAlign = "center";
      outCtx.fillText("Clean digital ink canvas — starts with camera", INK_W / 2, INK_H / 2);
    }

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

    // Gentle cleanup: remove isolated 1px specks only (preserve thin pen strokes!)
    function cleanCommittedStrokes() {
      cleaned.fill(0);
      let count = 0;
      for (let y = 1; y < INK_H - 1; y++) {
        const row = y * INK_W;
        for (let x = 1; x < INK_W - 1; x++) {
          const i = row + x;
          if (!committed[i]) continue;
          const nb =
            committed[i - INK_W - 1] + committed[i - INK_W] + committed[i - INK_W + 1] +
            committed[i - 1] + committed[i + 1] +
            committed[i + INK_W - 1] + committed[i + INK_W] + committed[i + INK_W + 1];
          if (nb >= 1) {
            cleaned[i] = 1;
            count++;
          }
        }
      }
      committedCount = count;
    }

    function renderCleanCanvas() {
      outCtx.fillStyle = "#09090b";
      outCtx.fillRect(0, 0, INK_W, INK_H);
      if (!hasCommittedAny) return;

      // Subtle anti-aliased halo
      outCtx.fillStyle = "rgba(56, 189, 248, 0.25)";
      for (let y = 1; y < INK_H - 1; y++) {
        const row = y * INK_W;
        for (let x = 1; x < INK_W - 1; x++) {
          if (cleaned[row + x]) {
            outCtx.fillRect(x - 1.2, y - 1.2, 2.8, 2.8);
          }
        }
      }

      // Crisp consistent-thickness core ink
      outCtx.fillStyle = "#f4f4f5";
      for (let y = 1; y < INK_H - 1; y++) {
        const row = y * INK_W;
        for (let x = 1; x < INK_W - 1; x++) {
          if (cleaned[row + x]) {
            outCtx.fillRect(x - 0.7, y - 0.7, 1.8, 1.8);
          }
        }
      }
    }

    function renderRawInk(src, bg) {
      const thresh = currentThreshold;
      const ramp = 24;
      for (let i = 0; i < N; i++) {
        const p = i << 2;
        const luma = (77 * src[p] + 150 * src[p + 1] + 29 * src[p + 2]) >> 8;
        const bgLuma = (77 * bg[p] + 150 * bg[p + 1] + 29 * bg[p + 2]) >> 8;
        const diff = bgLuma - luma;
        if (diff > thresh && luma < 215) {
          let strength = (diff - thresh) / ramp;
          if (strength > 1) strength = 1;
          outBuf[p] = 9 + ((230 * strength) | 0);
          outBuf[p + 1] = 9 + ((238 * strength) | 0);
          outBuf[p + 2] = 11 + ((238 * strength) | 0);
          outBuf[p + 3] = 255;
        } else {
          outBuf[p] = 9;
          outBuf[p + 1] = 9;
          outBuf[p + 2] = 11;
          outBuf[p + 3] = 255;
        }
      }
      outCtx.putImageData(outImg, 0, 0);
    }

    function renderDebugView(stats, rowRuleLimit, colRuleLimit) {
      // Base dark background + color-coded filter masks
      for (let y = 0; y < INK_H; y++) {
        const row = y * INK_W;
        const gy = (y / CELL) | 0;
        const gRow = gy * GRID_W;
        const isRuledRow = y >= MARGIN && y < INK_H - MARGIN && rowFaint[y] > rowRuleLimit;

        for (let x = 0; x < INK_W; x++) {
          const i = row + x;
          const p = i << 2;
          const gi = gRow + ((x / CELL) | 0);

          if (cleaned[i]) {
            // Bright white-cyan = confirmed clean ink
            outBuf[p] = 244; outBuf[p + 1] = 250; outBuf[p + 2] = 255; outBuf[p + 3] = 255;
          } else if (handMask[gi]) {
            // Red tint = masked by hand/skin filter
            outBuf[p] = rawDark[i] ? 239 : 90; outBuf[p + 1] = 25; outBuf[p + 2] = 25; outBuf[p + 3] = 255;
          } else if (blobMask[gi]) {
            // Orange tint = masked by large-blob filter
            outBuf[p] = 217; outBuf[p + 1] = 119; outBuf[p + 2] = 6; outBuf[p + 3] = 255;
          } else if (isRuledRow || (x >= MARGIN && x < INK_W - MARGIN && colFaint[x] > colRuleLimit)) {
            // Purple = suppressed as ruled paper line
            outBuf[p] = 126; outBuf[p + 1] = 34; outBuf[p + 2] = 206; outBuf[p + 3] = 255;
          } else if (rawDark[i]) {
            // Yellow = dark candidate building temporal persistence
            outBuf[p] = 250; outBuf[p + 1] = 204; outBuf[p + 2] = 21; outBuf[p + 3] = 255;
          } else {
            outBuf[p] = 9; outBuf[p + 1] = 9; outBuf[p + 2] = 11; outBuf[p + 3] = 255;
          }
        }
      }
      outCtx.putImageData(outImg, 0, 0);

      // Draw compact HUD showing exact filter counts
      outCtx.fillStyle = "rgba(9, 9, 11, 0.82)";
      outCtx.fillRect(6, 6, INK_W - 12, 34);
      outCtx.font = "10.5px ui-monospace, monospace";
      outCtx.textAlign = "left";
      outCtx.fillStyle = "#f4f4f5";
      outCtx.fillText(
        `DEBUG  Ink:${committedCount}  Dark:${stats.darkPx}  HandBlks:${stats.handBlocks}  BlobBlks:${stats.blobBlocks}  Ruled:${stats.ruledRows}`,
        12,
        20
      );
      outCtx.fillStyle = "#94a3b8";
      outCtx.fillText(
        `White=Ink  Yellow=Dark  Red=Hand  Orange=Blob  Purple=RuledLine  PaperMin:${Math.round(stats.paperMinLuma)}`,
        12,
        34
      );
    }

    function tick(now) {
      if (!running) return;
      rafId = requestAnimationFrame(tick);

      if (now - lastDrawTs < minFrameMs) return;
      if (!videoEl || videoEl.readyState < 2 || !videoEl.videoWidth) return;
      lastDrawTs = now;

      drawRotatedVideo();
      const src = frameCtx.getImageData(0, 0, INK_W, INK_H).data;

      tinyCtx.drawImage(frameCanvas, 0, 0, BG_W, BG_H);
      bgCtx.imageSmoothingEnabled = true;
      bgCtx.drawImage(tinyCanvas, 0, 0, INK_W, INK_H);
      const bg = bgCtx.getImageData(0, 0, INK_W, INK_H).data;

      if (mode === "raw") {
        renderRawInk(src, bg);
        updateFps(now);
        return;
      }

      // Gentle paper brightness floor (only rejects very dark desk/black background)
      let bgSum = 0;
      let bgCnt = 0;
      for (let y = 30; y < INK_H - 30; y += 10) {
        const row = y * INK_W;
        for (let x = 30; x < INK_W - 30; x += 10) {
          const p = (row + x) << 2;
          bgSum += (77 * bg[p] + 150 * bg[p + 1] + 29 * bg[p + 2]) >> 8;
          bgCnt++;
        }
      }
      const meanPaperLuma = bgCnt ? bgSum / bgCnt : 150;
      const paperMinLuma = Math.max(45, meanPaperLuma * 0.42);

      skinGrid.fill(0);
      darkGrid.fill(0);
      rawDark.fill(0);
      rowFaint.fill(0);
      colFaint.fill(0);

      const thresh = currentThreshold;
      const faintLo = Math.max(6, thresh * 0.4);
      const faintHi = thresh * 1.1;
      let darkPx = 0;

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
          const gi = gRow + ((x / CELL) | 0);

          // Strict skin-tone detector (won't falsely trigger on warm-lit white paper!)
          if (r > 95 && g > 40 && b > 20 && (r - b) > 35 && (r - g) > 14 && r > g && g > b) {
            const cb = 128 - 0.1687 * r - 0.3313 * g + 0.5 * b;
            const cr = 128 + 0.5 * r - 0.4187 * g - 0.0813 * b;
            if (cb >= 80 && cb <= 122 && cr >= 140 && cr <= 173) {
              skinGrid[gi]++;
              continue;
            }
          }

          const bgLuma = (77 * bg[p] + 150 * bg[p + 1] + 29 * bg[p + 2]) >> 8;
          if (bgLuma < paperMinLuma) continue;

          const luma = (77 * r + 150 * g + 29 * b) >> 8;
          const diff = bgLuma - luma;

          if (diff > faintLo && diff < faintHi) {
            rowFaint[y]++;
            colFaint[x]++;
          }

          if (diff > thresh && luma < 215) {
            rawDark[i] = 1;
            darkGrid[gi]++;
            darkPx++;
          }
        }
      }

      // Gentler hand & large-blob masks
      handMask.fill(0);
      blobMask.fill(0);
      let handBlocks = 0;
      let blobBlocks = 0;

      for (let gy = 0; gy < GRID_H; gy++) {
        for (let gx = 0; gx < GRID_W; gx++) {
          const gi = gy * GRID_W + gx;
          if (skinGrid[gi] >= 35) {
            handBlocks++;
            for (let dy = -1; dy <= 1; dy++) {
              const ny = gy + dy;
              if (ny < 0 || ny >= GRID_H) continue;
              for (let dx = -1; dx <= 1; dx++) {
                const nx = gx + dx;
                if (nx < 0 || nx >= GRID_W) continue;
                handMask[ny * GRID_W + nx] = 1;
              }
            }
          }
          if (darkGrid[gi] >= 82) {
            blobBlocks++;
            blobMask[gi] = 1;
          }
        }
      }

      // Gentler ruled-line suppression (only if >72% of entire line is uniformly faint)
      const rowRuleLimit = Math.round((INK_W - MARGIN * 2) * 0.72);
      const colRuleLimit = Math.round((INK_H - MARGIN * 2) * 0.72);
      let ruledRows = 0;
      let newlyCommitted = false;

      for (let y = MARGIN + 1; y < INK_H - MARGIN - 1; y++) {
        const isRuledRow = rowFaint[y] > rowRuleLimit;
        if (isRuledRow) ruledRows++;
        const row = y * INK_W;
        const gy = (y / CELL) | 0;
        const gRow = gy * GRID_W;

        for (let x = MARGIN + 1; x < INK_W - MARGIN - 1; x++) {
          const i = row + x;
          if (committed[i]) continue;

          const gi = gRow + ((x / CELL) | 0);
          if (handMask[gi] || blobMask[gi]) {
            streak[i] = 0;
            continue;
          }

          if (isRuledRow || colFaint[x] > colRuleLimit) {
            const p = i << 2;
            const luma = (77 * src[p] + 150 * src[p + 1] + 29 * src[p + 2]) >> 8;
            const bgLuma = (77 * bg[p] + 150 * bg[p + 1] + 29 * bg[p + 2]) >> 8;
            if (bgLuma - luma < thresh + 10) {
              if (streak[i] > 0) streak[i]--;
              continue;
            }
          }

          if (rawDark[i]) {
            // Gentle speck filter: >= 1 dark neighbor
            const nb =
              rawDark[i - INK_W - 1] + rawDark[i - INK_W] + rawDark[i - INK_W + 1] +
              rawDark[i - 1] + rawDark[i + 1] +
              rawDark[i + INK_W - 1] + rawDark[i + INK_W] + rawDark[i + INK_W + 1];
            if (nb >= 1) {
              const s = streak[i] + 1;
              streak[i] = s > 250 ? 250 : s;
              if (s >= CONFIRM_FRAMES) {
                committed[i] = 1;
                hasCommittedAny = true;
                newlyCommitted = true;
              }
            } else if (streak[i] > 0) {
              streak[i]--;
            }
          } else if (streak[i] > 0) {
            streak[i]--;
          }
        }
      }

      if (newlyCommitted) {
        cleanCommittedStrokes();
      }

      if (debugEnabled) {
        renderDebugView({ darkPx, handBlocks, blobBlocks, ruledRows, paperMinLuma }, rowRuleLimit, colRuleLimit);
      } else if (newlyCommitted) {
        renderCleanCanvas();
      }

      updateFps(now);
    }

    function updateFps(now) {
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
        if (mode === "clean") renderCleanCanvas();
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
        currentThreshold = Math.max(6, Math.min(55, Number(val) || 16));
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
      setMode(m) {
        mode = m === "raw" ? "raw" : "clean";
        if (mode === "clean") renderCleanCanvas();
      },
      getMode() {
        return mode;
      },
      setDebug(flag) {
        debugEnabled = Boolean(flag);
        if (!debugEnabled && mode === "clean") renderCleanCanvas();
      },
      getDebug() {
        return debugEnabled;
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
