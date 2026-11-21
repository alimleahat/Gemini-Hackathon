/* Fast Local Digital Ink Layer (20-30 fps, zero AI, pure browser Canvas2D).
 * Detects dark pen/marker strokes against an adaptive local paper-brightness
 * estimate so shadows and uneven desk lighting don't create blotches, and
 * renders crisp glowing digital ink in real time — like drawing on an iPad.
 */

window.FastInkEngine = (function () {
  const INK_W = 480;
  const INK_H = 300;
  const BG_W = 30;
  const BG_H = 19;

  function create({ videoEl, outCanvas, fpsEl, threshold = 24, targetFps = 25 }) {
    const outCtx = outCanvas.getContext("2d", { alpha: false });
    outCanvas.width = INK_W;
    outCanvas.height = INK_H;

    // Offscreen scratch canvases for fast adaptive thresholding
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

    let running = false;
    let rafId = null;
    let lastDrawTs = 0;
    let currentThreshold = threshold;
    let fpsFrames = 0;
    let fpsWindowStart = performance.now();
    const minFrameMs = Math.round(1000 / targetFps);

    function drawIdleGrid() {
      outCtx.fillStyle = "#090912";
      outCtx.fillRect(0, 0, INK_W, INK_H);
      outCtx.strokeStyle = "rgba(167, 139, 250, 0.08)";
      outCtx.lineWidth = 1;
      for (let x = 0; x < INK_W; x += 24) {
        outCtx.beginPath();
        outCtx.moveTo(x, 0);
        outCtx.lineTo(x, INK_H);
        outCtx.stroke();
      }
      for (let y = 0; y < INK_H; y += 24) {
        outCtx.beginPath();
        outCtx.moveTo(0, y);
        outCtx.lineTo(INK_W, y);
        outCtx.stroke();
      }
      outCtx.fillStyle = "#7c7e94";
      outCtx.font = "13px Inter, -apple-system, sans-serif";
      outCtx.textAlign = "center";
      outCtx.fillText("Live digital ink starts with camera", INK_W / 2, INK_H / 2);
    }

    function tick(now) {
      if (!running) return;
      rafId = requestAnimationFrame(tick);

      if (now - lastDrawTs < minFrameMs) return;
      if (!videoEl || videoEl.readyState < 2 || !videoEl.videoWidth) return;
      lastDrawTs = now;

      // 1. Grab current camera frame
      frameCtx.drawImage(videoEl, 0, 0, INK_W, INK_H);
      const src = frameCtx.getImageData(0, 0, INK_W, INK_H).data;

      // 2. Fast local paper-background estimation (downscale -> smooth upscale)
      tinyCtx.drawImage(frameCanvas, 0, 0, BG_W, BG_H);
      bgCtx.imageSmoothingEnabled = true;
      bgCtx.drawImage(tinyCanvas, 0, 0, INK_W, INK_H);
      const bg = bgCtx.getImageData(0, 0, INK_W, INK_H).data;

      // 3. Adaptive dark-ink extraction -> crisp glowing digital ink on dark tablet canvas
      const thresh = currentThreshold;
      const ramp = 26;
      const n = INK_W * INK_H;

      for (let i = 0; i < n; i++) {
        const p = i << 2;
        // Fast integer luma approximation: (77*R + 150*G + 29*B) >> 8
        const luma = (77 * src[p] + 150 * src[p + 1] + 29 * src[p + 2]) >> 8;
        const bgLuma = (77 * bg[p] + 150 * bg[p + 1] + 29 * bg[p + 2]) >> 8;
        const diff = bgLuma - luma;

        if (diff > thresh && luma < 185) {
          let strength = (diff - thresh) / ramp;
          if (strength > 1) strength = 1;
          // Crisp iPad-style cyan-white ink on #060b14 canvas
          outBuf[p] = 6 + ((220 * strength) | 0);       // R
          outBuf[p + 1] = 11 + ((238 * strength) | 0);  // G
          outBuf[p + 2] = 20 + ((235 * strength) | 0);  // B
          outBuf[p + 3] = 255;
        } else {
          // Subtle dark dot-grid background
          const x = i % INK_W;
          const y = (i / INK_W) | 0;
          const isGrid = (x % 24 === 0 && y % 24 === 0);
          outBuf[p] = isGrid ? 24 : 6;
          outBuf[p + 1] = isGrid ? 42 : 11;
          outBuf[p + 2] = isGrid ? 62 : 20;
          outBuf[p + 3] = 255;
        }
      }

      outCtx.putImageData(outImg, 0, 0);

      // Update live FPS readout once per second
      fpsFrames += 1;
      if (now - fpsWindowStart >= 1000) {
        const fps = Math.round((fpsFrames * 1000) / (now - fpsWindowStart));
        if (fpsEl) fpsEl.textContent = `${fps} fps`;
        fpsFrames = 0;
        fpsWindowStart = now;
      }
    }

    drawIdleGrid();

    return {
      start() {
        if (running) return;
        running = true;
        fpsFrames = 0;
        fpsWindowStart = performance.now();
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
        currentThreshold = Math.max(8, Math.min(60, Number(val) || 24));
      },
      reset() {
        drawIdleGrid();
      },
    };
  }

  return { create };
})();
