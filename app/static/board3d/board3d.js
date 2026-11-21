/**
 * Standalone 3D Virtual FPGA Board Component (Three.js)
 *
 * Exports:
 *   init(containerElement, optionsOrOnInput)
 *   update(state)   // state = { sw[16], btn[5], led[16], seg[7], an[4], digits?[4] }
 *
 * Clicking a 3D switch toggles it and calls onInput("sw0".."sw15", 0|1).
 * Pressing/releasing a 3D pushbutton calls onInput("btn0".."btn4", 1|0).
 */

import * as THREE from "https://esm.sh/three@0.170.0";
import { OrbitControls } from "https://esm.sh/three@0.170.0/examples/jsm/controls/OrbitControls.js";
import { RoomEnvironment } from "https://esm.sh/three@0.170.0/examples/jsm/environments/RoomEnvironment.js";
import { EffectComposer } from "https://esm.sh/three@0.170.0/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass } from "https://esm.sh/three@0.170.0/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "https://esm.sh/three@0.170.0/examples/jsm/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "https://esm.sh/three@0.170.0/examples/jsm/postprocessing/OutputPass.js";

// Board geometry constants (3:2 aspect ratio matching Basys 3 class dev board)
const BOARD_W = 12.0;
const BOARD_D = 8.0;
const BOARD_H = 0.18;
const TOP_Y = BOARD_H / 2;

const IDLE_ROTATE_DELAY_MS = 4000;

let activeInstance = null;

// --- Helpers for normalizing array or bitmask signals ---
function readBit(src, index, defaultVal = 0) {
  if (src == null) return defaultVal;
  if (Array.isArray(src) || ArrayBuffer.isView(src)) {
    return src[index] ? 1 : 0;
  }
  if (typeof src === "number") {
    return (src >> index) & 1;
  }
  return defaultVal;
}

function makeCanvasTexture(width, height, drawFn) {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  drawFn(ctx, width, height);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 8;
  tex.needsUpdate = true;
  return tex;
}

// Create a small crisp white silkscreen decal mesh flush on the PCB
function createSilkscreenLabel(text, width, height, fontSize = 36, align = "center") {
  const tex = makeCanvasTexture(256, 96, (ctx, w, h) => {
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = "rgba(240, 248, 242, 0.92)";
    ctx.font = `700 ${fontSize}px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace`;
    ctx.textAlign = align;
    ctx.textBaseline = "middle";
    const x = align === "left" ? 8 : align === "right" ? w - 8 : w / 2;
    ctx.fillText(text, x, h / 2);
  });
  const mat = new THREE.MeshBasicMaterial({
    map: tex,
    transparent: true,
    depthWrite: false,
    polygonOffset: true,
    polygonOffsetFactor: -2,
  });
  const geo = new THREE.PlaneGeometry(width, height);
  const mesh = new THREE.Mesh(geo, mat);
  mesh.rotation.x = -Math.PI / 2;
  return mesh;
}

// Build the FPGA IC chip top laser-etched texture (generic, unbranded)
function createFpgaChipTexture() {
  return makeCanvasTexture(512, 512, (ctx, w, h) => {
    ctx.fillStyle = "#1a1d22";
    ctx.fillRect(0, 0, w, h);

    // Subtle matte grain
    ctx.fillStyle = "rgba(255,255,255,0.025)";
    for (let i = 0; i < 600; i++) {
      ctx.fillRect(Math.random() * w, Math.random() * h, 2, 2);
    }

    // Fine border line
    ctx.strokeStyle = "rgba(180, 195, 210, 0.14)";
    ctx.lineWidth = 4;
    ctx.strokeRect(20, 20, w - 40, h - 40);

    // Pin-1 orientation dot (bottom-left)
    ctx.fillStyle = "rgba(220, 228, 236, 0.72)";
    ctx.beginPath();
    ctx.arc(62, h - 62, 16, 0, Math.PI * 2);
    ctx.fill();

    // Generic laser-etched markings (no vendor names/logos)
    ctx.fillStyle = "rgba(205, 215, 224, 0.72)";
    ctx.textAlign = "center";
    ctx.font = "700 44px ui-monospace, SFMono-Regular, Menlo, monospace";
    ctx.fillText("FPGA-7A35T", w / 2, 175);

    ctx.fillStyle = "rgba(175, 188, 200, 0.60)";
    ctx.font = "600 28px ui-monospace, SFMono-Regular, Menlo, monospace";
    ctx.fillText("CSG324-1C", w / 2, 235);
    ctx.fillText("LOT 2642A88", w / 2, 290);

    ctx.fillStyle = "rgba(155, 170, 185, 0.48)";
    ctx.font = "500 22px ui-monospace, SFMono-Regular, Menlo, monospace";
    ctx.fillText("33,280 LOGIC CELLS", w / 2, 360);
    ctx.fillText("1.0V CORE / 3.3V IO", w / 2, 398);
  });
}

// Create a crisp procedural fallback PCB texture if image fails or while loading
function createFallbackPcbTexture() {
  return makeCanvasTexture(1536, 1024, (ctx, w, h) => {
    ctx.fillStyle = "#0b3d24";
    ctx.fillRect(0, 0, w, h);

    // Subtle trace grid
    ctx.strokeStyle = "#145c36";
    ctx.lineWidth = 2;
    for (let x = 32; x < w; x += 28) {
      ctx.beginPath();
      ctx.moveTo(x, 24);
      ctx.lineTo(x, h - 24);
      ctx.stroke();
    }
    for (let y = 32; y < h; y += 28) {
      ctx.beginPath();
      ctx.moveTo(24, y);
      ctx.lineTo(w - 24, y);
      ctx.stroke();
    }
    // Outer silkscreen border
    ctx.strokeStyle = "rgba(235, 245, 238, 0.65)";
    ctx.lineWidth = 4;
    ctx.strokeRect(18, 18, w - 36, h - 36);
  });
}

// Build a single 7-segment bar geometry (elongated hexagon)
function createSegmentGeometry(length, thickness, height) {
  const halfL = length / 2;
  const halfT = thickness / 2;
  const bevel = halfT * 0.95;

  const shape = new THREE.Shape();
  shape.moveTo(-halfL + bevel, -halfT);
  shape.lineTo(halfL - bevel, -halfT);
  shape.lineTo(halfL, 0);
  shape.lineTo(halfL - bevel, halfT);
  shape.lineTo(-halfL + bevel, halfT);
  shape.lineTo(-halfL, 0);
  shape.closePath();

  const geo = new THREE.ExtrudeGeometry(shape, {
    depth: height,
    bevelEnabled: false,
  });
  geo.rotateX(-Math.PI / 2);
  return geo;
}

class VirtualFPGABoard3D {
  constructor(container, options = {}) {
    this.container = container;
    this.onInput = typeof options === "function" ? options : options.onInput || null;
    this.textureUrl =
      (typeof options === "object" && options.textureUrl) ||
      new URL("./pcb_texture.jpg", import.meta.url).href;
    this.autoRotateEnabled =
      typeof options === "object" && options.autoRotate !== undefined ? options.autoRotate : true;

    // Internal hardware state
    this.swState = new Uint8Array(16);
    this.btnState = new Uint8Array(5);
    this.ledState = new Uint8Array(16);
    // Active-low per-digit 7-bit segment masks: bit s == 0 means lit, 0x7f = all off
    this.digitMasks = [0x7f, 0x7f, 0x7f, 0x7f];

    // Interactive references
    this.switches = []; // { index, knob, targetZ, hitMesh }
    this.leds = []; // { index, lensMat, haloMesh }
    this.buttons = []; // { index, cap, restY, targetY, hitMesh, label }
    this.digitSegments = [[], [], [], []]; // [d][s] -> MeshStandardMaterial
    this.interactiveMeshes = [];

    // Interaction tracking
    this.raycaster = new THREE.Raycaster();
    this.pointer = new THREE.Vector2();
    this.pointerDownPos = null;
    this.pressedButton = null;
    this.hoveredItem = null;
    this.lastInteractionTime = performance.now();
    this.isUserOrbiting = false;
    this.disposed = false;
    this.animFrameId = null;
    this.clock = new THREE.Clock();

    this._initDOM();
    this._initScene();
    this._buildBoard();
    this._bindEvents();
    this._resize();
    this._animate();
  }

  _initDOM() {
    const style = window.getComputedStyle(this.container);
    if (style.position === "static") {
      this.container.style.position = "relative";
    }
    this.container.style.overflow = "hidden";
    this.container.style.userSelect = "none";
    this.container.style.touchAction = "none";

    // Subtle floating hover tooltip
    this.tooltip = document.createElement("div");
    Object.assign(this.tooltip.style, {
      position: "absolute",
      pointerEvents: "none",
      padding: "4px 9px",
      borderRadius: "6px",
      background: "rgba(10, 15, 24, 0.88)",
      border: "1px solid rgba(110, 231, 183, 0.38)",
      color: "#e2f8ec",
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
      fontSize: "12px",
      fontWeight: "600",
      letterSpacing: "0.03em",
      boxShadow: "0 4px 14px rgba(0,0,0,0.45)",
      opacity: "0",
      transition: "opacity 0.12s ease",
      zIndex: "10",
      transform: "translate(-50%, -135%)",
      whiteSpace: "nowrap",
    });
    this.container.appendChild(this.tooltip);
  }

  _initScene() {
    const w = this.container.clientWidth || 640;
    const h = this.container.clientHeight || 420;

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color("#0b1018");

    this.camera = new THREE.PerspectiveCamera(36, w / h, 0.1, 100);
    this.camera.position.set(0.0, 9.8, 10.6);

    this.renderer = new THREE.WebGLRenderer({
      antialias: true,
      powerPreference: "high-performance",
    });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.renderer.setSize(w, h);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.06;
    this.renderer.domElement.style.display = "block";
    this.renderer.domElement.style.width = "100%";
    this.renderer.domElement.style.height = "100%";
    this.container.appendChild(this.renderer.domElement);

    // Environment reflections (subtle satin sheen on metal shields & pins)
    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.envRT = pmrem.fromScene(new RoomEnvironment(), 0.04);
    this.scene.environment = this.envRT.texture;
    this.scene.environmentIntensity = 0.28;
    pmrem.dispose();

    // Studio lighting rig
    const hemi = new THREE.HemisphereLight(0xdbeafe, 0x16241c, 0.62);
    this.scene.add(hemi);

    const keyLight = new THREE.DirectionalLight(0xfffaf0, 1.35);
    keyLight.position.set(6.5, 13.0, 7.5);
    keyLight.castShadow = true;
    keyLight.shadow.mapSize.width = 2048;
    keyLight.shadow.mapSize.height = 2048;
    keyLight.shadow.camera.near = 2;
    keyLight.shadow.camera.far = 32;
    keyLight.shadow.camera.left = -9;
    keyLight.shadow.camera.right = 9;
    keyLight.shadow.camera.top = 7;
    keyLight.shadow.camera.bottom = -7;
    keyLight.shadow.bias = -0.0004;
    keyLight.shadow.normalBias = 0.02;
    keyLight.shadow.radius = 3.5;
    this.scene.add(keyLight);

    const fillLight = new THREE.DirectionalLight(0x93c5fd, 0.55);
    fillLight.position.set(-8.0, 6.0, -5.0);
    this.scene.add(fillLight);

    const rimLight = new THREE.DirectionalLight(0x6ee7b7, 0.32);
    rimLight.position.set(0.0, 4.0, -10.0);
    this.scene.add(rimLight);

    // Subtle dark studio ground plane to catch soft board shadow
    const shadowFloorGeo = new THREE.PlaneGeometry(40, 40);
    const shadowFloorMat = new THREE.ShadowMaterial({ opacity: 0.42 });
    const shadowFloor = new THREE.Mesh(shadowFloorGeo, shadowFloorMat);
    shadowFloor.rotation.x = -Math.PI / 2;
    shadowFloor.position.y = -0.52;
    shadowFloor.receiveShadow = true;
    this.scene.add(shadowFloor);

    // OrbitControls
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.065;
    this.controls.rotateSpeed = 0.78;
    this.controls.zoomSpeed = 0.9;
    this.controls.panSpeed = 0.6;
    this.controls.minDistance = 6.2;
    this.controls.maxDistance = 26.0;
    this.controls.maxPolarAngle = Math.PI * 0.82;
    this.controls.target.set(0, 0, 0.15);
    this.controls.autoRotate = this.autoRotateEnabled;
    this.controls.autoRotateSpeed = 0.65;

    this.controls.addEventListener("start", () => {
      this.isUserOrbiting = true;
      this.lastInteractionTime = performance.now();
      this.controls.autoRotate = false;
    });
    this.controls.addEventListener("end", () => {
      this.isUserOrbiting = false;
      this.lastInteractionTime = performance.now();
    });

    // Post-processing with selective UnrealBloomPass for glowing LEDs & 7-seg
    this.composer = new EffectComposer(this.renderer);
    this.renderPass = new RenderPass(this.scene, this.camera);
    this.composer.addPass(this.renderPass);

    this.bloomPass = new UnrealBloomPass(
      new THREE.Vector2(w, h),
      0.56, // strength
      0.44, // radius
      1.25  // threshold: strictly selective so only emissive LEDs & 7-seg digits bloom
    );
    this.composer.addPass(this.bloomPass);

    this.outputPass = new OutputPass();
    this.composer.addPass(this.outputPass);
  }

  _buildBoard() {
    this.boardGroup = new THREE.Group();
    this.scene.add(this.boardGroup);

    // Shared materials (satin/matte realistic hardware finishes)
    this.matMetalSilver = new THREE.MeshStandardMaterial({
      color: 0xaeb6bf,
      metalness: 0.58,
      roughness: 0.52,
    });
    this.matMetalGold = new THREE.MeshStandardMaterial({
      color: 0xc89b44,
      metalness: 0.65,
      roughness: 0.44,
    });
    this.matDarkPlastic = new THREE.MeshStandardMaterial({
      color: 0x1b1e24,
      metalness: 0.05,
      roughness: 0.64,
    });
    this.matCharcoal = new THREE.MeshStandardMaterial({
      color: 0x2a2f38,
      metalness: 0.08,
      roughness: 0.58,
    });
    this.matCeramicWhite = new THREE.MeshStandardMaterial({
      color: 0xdce0e5,
      metalness: 0.04,
      roughness: 0.55,
    });
    this.matCapTan = new THREE.MeshStandardMaterial({
      color: 0xb68a52,
      metalness: 0.08,
      roughness: 0.48,
    });

    this._buildPCB();
    this._buildMountingStandoffs();
    this._buildFpgaAndICs();
    this._buildSevenSegmentDisplay();
    this._buildPushbuttons();
    this._buildLedsAndSwitches();
    this._buildEdgeConnectors();
  }

  _buildPCB() {
    const fallbackTex = createFallbackPcbTexture();

    const pcbTopMat = new THREE.MeshStandardMaterial({
      map: fallbackTex,
      roughness: 0.58,
      metalness: 0.06,
    });

    // Load the Gemini-generated PCB surface texture
    const loader = new THREE.TextureLoader();
    loader.load(
      this.textureUrl,
      (tex) => {
        tex.colorSpace = THREE.SRGBColorSpace;
        tex.anisotropy = Math.min(16, this.renderer.capabilities.getMaxAnisotropy());
        pcbTopMat.map = tex;
        pcbTopMat.needsUpdate = true;
      },
      undefined,
      () => {
        // Keep procedural fallback if texture is unavailable
      }
    );

    const pcbEdgeMat = new THREE.MeshStandardMaterial({
      color: 0x2c4a35,
      roughness: 0.72,
      metalness: 0.05,
    });
    const pcbBottomMat = new THREE.MeshStandardMaterial({
      color: 0x0a331e,
      roughness: 0.48,
      metalness: 0.16,
    });

    // BoxGeometry material order: +x, -x, +y (top), -y (bottom), +z, -z
    const pcbGeo = new THREE.BoxGeometry(BOARD_W, BOARD_H, BOARD_D);
    const pcbMesh = new THREE.Mesh(pcbGeo, [
      pcbEdgeMat,
      pcbEdgeMat,
      pcbTopMat,
      pcbBottomMat,
      pcbEdgeMat,
      pcbEdgeMat,
    ]);
    pcbMesh.castShadow = true;
    pcbMesh.receiveShadow = true;
    this.boardGroup.add(pcbMesh);
  }

  _buildMountingStandoffs() {
    const corners = [
      [-BOARD_W / 2 + 0.38, -BOARD_D / 2 + 0.40],
      [BOARD_W / 2 - 0.38, -BOARD_D / 2 + 0.40],
      [-BOARD_W / 2 + 0.38, BOARD_D / 2 - 0.40],
      [BOARD_W / 2 - 0.38, BOARD_D / 2 - 0.40],
    ];

    const ringGeo = new THREE.CylinderGeometry(0.24, 0.24, 0.025, 24);
    const screwGeo = new THREE.CylinderGeometry(0.14, 0.14, 0.07, 16);
    const footGeo = new THREE.CylinderGeometry(0.16, 0.19, 0.36, 16);

    for (const [x, z] of corners) {
      const ring = new THREE.Mesh(ringGeo, this.matMetalGold);
      ring.position.set(x, TOP_Y + 0.012, z);
      this.boardGroup.add(ring);

      const screw = new THREE.Mesh(screwGeo, this.matMetalSilver);
      screw.position.set(x, TOP_Y + 0.045, z);
      screw.castShadow = true;
      this.boardGroup.add(screw);

      // Rubber/brass standoff foot underneath the board
      const foot = new THREE.Mesh(footGeo, this.matDarkPlastic);
      foot.position.set(x, -BOARD_H / 2 - 0.18, z);
      foot.castShadow = true;
      this.boardGroup.add(foot);
    }
  }

  _buildFpgaAndICs() {
    // Centered directly over U1 BGA footprint in pcb_texture.jpg
    const cx = 0.0;
    const cz = 0.0;

    // BGA interposer substrate
    const subGeo = new THREE.BoxGeometry(2.26, 0.08, 2.26);
    const subMat = new THREE.MeshStandardMaterial({
      color: 0x104529,
      roughness: 0.45,
      metalness: 0.15,
    });
    const sub = new THREE.Mesh(subGeo, subMat);
    sub.position.set(cx, TOP_Y + 0.04, cz);
    sub.castShadow = true;
    sub.receiveShadow = true;
    this.boardGroup.add(sub);

    // Main FPGA epoxy package with laser-etched markings
    const chipTopTex = createFpgaChipTexture();
    const chipTopMat = new THREE.MeshStandardMaterial({
      map: chipTopTex,
      roughness: 0.48,
      metalness: 0.12,
    });
    const chipSideMat = new THREE.MeshStandardMaterial({
      color: 0x15181d,
      roughness: 0.55,
      metalness: 0.1,
    });
    const chipGeo = new THREE.BoxGeometry(2.04, 0.16, 2.04);
    const chip = new THREE.Mesh(chipGeo, [
      chipSideMat,
      chipSideMat,
      chipTopMat,
      chipSideMat,
      chipSideMat,
      chipSideMat,
    ]);
    chip.position.set(cx, TOP_Y + 0.16, cz);
    chip.castShadow = true;
    chip.receiveShadow = true;
    this.boardGroup.add(chip);

    // Decoupling SMD capacitors around the FPGA perimeter
    const capBodyGeo = new THREE.BoxGeometry(0.12, 0.06, 0.08);
    const capEndGeo = new THREE.BoxGeometry(0.03, 0.064, 0.084);
    const addCap = (x, z, rotY = 0) => {
      const g = new THREE.Group();
      const body = new THREE.Mesh(capBodyGeo, this.matCapTan);
      const endL = new THREE.Mesh(capEndGeo, this.matMetalSilver);
      const endR = new THREE.Mesh(capEndGeo, this.matMetalSilver);
      endL.position.x = -0.055;
      endR.position.x = 0.055;
      g.add(body, endL, endR);
      g.position.set(x, TOP_Y + 0.032, z);
      g.rotation.y = rotY;
      this.boardGroup.add(g);
    };

    for (let i = -3; i <= 3; i++) {
      if (i === 0) continue;
      addCap(cx + i * 0.3, cz - 1.32, Math.PI / 2);
      addCap(cx + i * 0.3, cz + 1.32, Math.PI / 2);
    }
    for (let i = -2; i <= 2; i++) {
      addCap(cx - 1.32, cz + i * 0.36, 0);
      addCap(cx + 1.32, cz + i * 0.36, 0);
    }

    // 100 MHz Crystal Oscillator metal can (top-right of FPGA)
    const oscGeo = new THREE.BoxGeometry(0.46, 0.12, 0.34);
    const osc = new THREE.Mesh(oscGeo, this.matMetalSilver);
    osc.position.set(cx + 1.55, TOP_Y + 0.06, cz - 1.45);
    osc.castShadow = true;
    this.boardGroup.add(osc);

    // SPI Flash IC (above-left of FPGA)
    const flashGeo = new THREE.BoxGeometry(0.55, 0.1, 0.42);
    const flash = new THREE.Mesh(flashGeo, this.matDarkPlastic);
    flash.position.set(cx - 0.95, TOP_Y + 0.05, cz - 1.85);
    flash.castShadow = true;
    this.boardGroup.add(flash);

    // Power inductor & regulator near top-right PWR block
    const indGeo = new THREE.BoxGeometry(0.44, 0.2, 0.44);
    const indMat = new THREE.MeshStandardMaterial({
      color: 0x2d323b,
      roughness: 0.65,
      metalness: 0.25,
    });
    const ind1 = new THREE.Mesh(indGeo, indMat);
    ind1.position.set(2.35, TOP_Y + 0.1, -2.35);
    ind1.castShadow = true;
    this.boardGroup.add(ind1);
  }

  _buildSevenSegmentDisplay() {
    // Aligned over the 7-SEG DISP region on the middle-left of pcb_texture.jpg
    const dispX = -3.35;
    const dispZ = -0.32;
    const dispW = 3.18;
    const dispH = 0.32;
    const dispD = 1.38;

    const group = new THREE.Group();
    group.position.set(dispX, TOP_Y, dispZ);
    this.boardGroup.add(group);

    // Outer dark housing
    const bodyGeo = new THREE.BoxGeometry(dispW, dispH, dispD);
    const bodyMat = new THREE.MeshStandardMaterial({
      color: 0x16191f,
      roughness: 0.38,
      metalness: 0.12,
    });
    const body = new THREE.Mesh(bodyGeo, bodyMat);
    body.position.y = dispH / 2;
    body.castShadow = true;
    body.receiveShadow = true;
    group.add(body);

    // Recessed satin dark-tinted acrylic face plate
    const faceGeo = new THREE.PlaneGeometry(dispW - 0.14, dispD - 0.14);
    const faceMat = new THREE.MeshPhysicalMaterial({
      color: 0x0c0a0d,
      roughness: 0.28,
      metalness: 0.04,
      clearcoat: 0.35,
      clearcoatRoughness: 0.25,
    });
    const face = new THREE.Mesh(faceGeo, faceMat);
    face.rotation.x = -Math.PI / 2;
    face.position.y = dispH + 0.002;
    group.add(face);

    // Segment geometries (horizontal: a, d, g; vertical: b, c, e, f)
    const segLen = 0.36;
    const segThick = 0.078;
    const segH = 0.018;
    const hGeo = createSegmentGeometry(segLen, segThick, segH);
    const vGeo = createSegmentGeometry(segLen, segThick, segH);
    vGeo.rotateY(Math.PI / 2);

    const dpGeo = new THREE.CylinderGeometry(0.042, 0.042, segH, 12);
    const dpOffMat = new THREE.MeshStandardMaterial({
      color: 0x2a1417,
      roughness: 0.4,
    });

    // 7 segment local offsets (x, z, isVertical)
    // 0:a(top), 1:b(top-right), 2:c(bot-right), 3:d(bot), 4:e(bot-left), 5:f(top-left), 6:g(mid)
    const halfX = 0.21;
    const halfZ = 0.21;
    const segLayout = [
      { x: 0, z: -halfZ * 2, vert: false }, // a (0)
      { x: halfX, z: -halfZ, vert: true },  // b (1)
      { x: halfX, z: halfZ, vert: true },   // c (2)
      { x: 0, z: halfZ * 2, vert: false },  // d (3)
      { x: -halfX, z: halfZ, vert: true },  // e (4)
      { x: -halfX, z: -halfZ, vert: true }, // f (5)
      { x: 0, z: 0, vert: false },          // g (6)
    ];

    // Left-to-right: Digit 3 (AN3), Digit 2 (AN2), Digit 1 (AN1), Digit 0 (AN0)
    const digitSpacing = 0.74;
    const startX = -1.5 * digitSpacing;

    for (let visualIdx = 0; visualIdx < 4; visualIdx++) {
      const digitIndex = 3 - visualIdx; // 3..0
      const dx = startX + visualIdx * digitSpacing;

      const digitGroup = new THREE.Group();
      digitGroup.position.set(dx, dispH + 0.004, 0);
      // Slight authentic italic slant on 7-seg digits
      digitGroup.rotation.y = 0;
      group.add(digitGroup);

      this.digitSegments[digitIndex] = [];

      for (let s = 0; s < 7; s++) {
        const cfg = segLayout[s];
        const segMat = new THREE.MeshStandardMaterial({
          color: 0x2b1316,
          emissive: new THREE.Color(0xff1e2d),
          emissiveIntensity: 0.0,
          roughness: 0.28,
          metalness: 0.05,
        });
        const mesh = new THREE.Mesh(cfg.vert ? vGeo : hGeo, segMat);
        // Subtle italic shear via x offset proportional to -z
        const shearX = -cfg.z * 0.08;
        mesh.position.set(cfg.x + shearX, 0, cfg.z);
        digitGroup.add(mesh);
        this.digitSegments[digitIndex].push(segMat);
      }

      // Decimal point (off)
      const dp = new THREE.Mesh(dpGeo, dpOffMat);
      dp.position.set(halfX + 0.11, segH / 2, halfZ * 2);
      digitGroup.add(dp);
    }
  }

  _buildPushbuttons() {
    // Aligned directly over BTNU, BTNL, BTNC, BTNR, BTND footprints in pcb_texture.jpg
    const cx = 3.54;
    const cz = 0.0;

    // Matches existing app.js: 0=Center, 1=Up, 2=Left, 3=Right, 4=Down
    const layout = [
      { index: 0, name: "BTNC", x: cx, z: cz },
      { index: 1, name: "BTNU", x: cx, z: cz - 0.78 },
      { index: 2, name: "BTNL", x: cx - 0.78, z: cz },
      { index: 3, name: "BTNR", x: cx + 0.80, z: cz },
      { index: 4, name: "BTND", x: cx, z: cz + 0.78 },
    ];

    const baseGeo = new THREE.BoxGeometry(0.46, 0.14, 0.46);
    const plateGeo = new THREE.BoxGeometry(0.42, 0.03, 0.42);
    const capGeo = new THREE.CylinderGeometry(0.145, 0.155, 0.16, 20);
    const pinGeo = new THREE.BoxGeometry(0.07, 0.03, 0.12);
    const hitGeo = new THREE.BoxGeometry(0.62, 0.38, 0.62);
    const hitMat = new THREE.MeshBasicMaterial({ visible: false });

    for (const b of layout) {
      const g = new THREE.Group();
      g.position.set(b.x, TOP_Y, b.z);
      this.boardGroup.add(g);

      // Tactile switch dark body
      const base = new THREE.Mesh(baseGeo, this.matDarkPlastic);
      base.position.y = 0.07;
      base.castShadow = true;
      base.receiveShadow = true;
      g.add(base);

      // Metallic top retaining plate
      const plate = new THREE.Mesh(plateGeo, this.matMetalSilver);
      plate.position.y = 0.145;
      g.add(plate);

      // 4 SMD solder pins
      for (const sx of [-0.16, 0.16]) {
        for (const sz of [-0.26, 0.26]) {
          const pin = new THREE.Mesh(pinGeo, this.matMetalSilver);
          pin.position.set(sx, 0.016, sz);
          g.add(pin);
        }
      }

      // Movable plunger cap
      const capMat = new THREE.MeshStandardMaterial({
        color: b.index === 0 ? 0x2b3340 : 0x1e2229,
        roughness: 0.4,
        metalness: 0.1,
      });
      const restY = 0.22;
      const cap = new THREE.Mesh(capGeo, capMat);
      cap.position.y = restY;
      cap.castShadow = true;
      g.add(cap);

      // Invisible hit target
      const hitMesh = new THREE.Mesh(hitGeo, hitMat);
      hitMesh.position.y = 0.18;
      hitMesh.userData = {
        kind: "btn",
        index: b.index,
        label: `${b.name} (btn[${b.index}])`,
        capMat,
      };
      g.add(hitMesh);
      this.interactiveMeshes.push(hitMesh);

      this.buttons.push({
        index: b.index,
        name: b.name,
        cap,
        capMat,
        restY,
        targetY: restY,
        hitMesh,
      });
    }
  }

  _buildLedsAndSwitches() {
    // Aligned directly over LD15..LD0 and SW15..SW0 footprints in pcb_texture.jpg
    const spacing = 0.648;
    const startX = -7.5 * spacing; // SW15 / LD15 on the left, SW0 / LD0 on the right
    const ledZ = 2.50;
    const swZ = 3.24;

    // Shared geometries
    const ledBaseGeo = new THREE.BoxGeometry(0.18, 0.05, 0.12);
    const ledPadGeo = new THREE.BoxGeometry(0.05, 0.02, 0.12);
    const ledLensGeo = new THREE.BoxGeometry(0.13, 0.065, 0.095);

    const swShellGeo = new THREE.BoxGeometry(0.32, 0.22, 0.72);
    const swSlotGeo = new THREE.BoxGeometry(0.18, 0.04, 0.50);
    const swKnobGeo = new THREE.BoxGeometry(0.17, 0.28, 0.21);
    const swHitGeo = new THREE.BoxGeometry(0.54, 0.52, 0.90);
    const hitMat = new THREE.MeshBasicMaterial({ visible: false });

    const swSlotMat = new THREE.MeshStandardMaterial({
      color: 0x0b0d10,
      roughness: 0.8,
    });

    // Index 15..0 from left to right
    for (let pos = 0; pos < 16; pos++) {
      const bit = 15 - pos;
      const x = startX + pos * spacing;

      // --- LED ---
      const ledGroup = new THREE.Group();
      ledGroup.position.set(x, TOP_Y, ledZ);
      this.boardGroup.add(ledGroup);

      const padL = new THREE.Mesh(ledPadGeo, this.matMetalSilver);
      padL.position.set(-0.1, 0.01, 0);
      const padR = new THREE.Mesh(ledPadGeo, this.matMetalSilver);
      padR.position.set(0.1, 0.01, 0);
      const ledBase = new THREE.Mesh(ledBaseGeo, this.matCeramicWhite);
      ledBase.position.y = 0.026;
      ledGroup.add(padL, padR, ledBase);

      const lensMat = new THREE.MeshStandardMaterial({
        color: 0x1e3a28,
        emissive: new THREE.Color(0x22ff66),
        emissiveIntensity: 0.0,
        roughness: 0.18,
        metalness: 0.05,
      });
      const lens = new THREE.Mesh(ledLensGeo, lensMat);
      lens.position.y = 0.072;
      ledGroup.add(lens);

      this.leds[bit] = { index: bit, lensMat };

      // --- Slide Switch ---
      const swGroup = new THREE.Group();
      swGroup.position.set(x, TOP_Y, swZ);
      this.boardGroup.add(swGroup);

      const shell = new THREE.Mesh(swShellGeo, this.matMetalSilver);
      shell.position.y = 0.11;
      shell.castShadow = true;
      shell.receiveShadow = true;
      swGroup.add(shell);

      const slot = new THREE.Mesh(swSlotGeo, swSlotMat);
      slot.position.y = 0.21;
      swGroup.add(slot);

      const knobMat = new THREE.MeshStandardMaterial({
        color: 0x1d2128,
        roughness: 0.42,
        metalness: 0.1,
      });
      const knob = new THREE.Mesh(swKnobGeo, knobMat);
      const offZ = 0.14; // DOWN / toward front edge
      const onZ = -0.14; // UP / toward center
      knob.position.set(0, 0.31, offZ);
      knob.castShadow = true;
      swGroup.add(knob);

      const hitMesh = new THREE.Mesh(swHitGeo, hitMat);
      hitMesh.position.y = 0.22;
      hitMesh.userData = {
        kind: "sw",
        index: bit,
        label: `SW${bit}`,
        knobMat,
      };
      swGroup.add(hitMesh);
      this.interactiveMeshes.push(hitMesh);

      this.switches[bit] = {
        index: bit,
        knob,
        knobMat,
        offZ,
        onZ,
        targetZ: offZ,
        hitMesh,
      };
    }
  }

  _buildEdgeConnectors() {
    // 1) Left edge: 3x PMOD 12-pin right-angle headers (JA, JB, JC) aligned to pcb_texture.jpg
    const addPmodLeft = (z) => {
      const g = new THREE.Group();
      g.position.set(-BOARD_W / 2 + 0.32, TOP_Y, z);
      this.boardGroup.add(g);

      const body = new THREE.Mesh(new THREE.BoxGeometry(0.56, 0.42, 1.56), this.matDarkPlastic);
      body.position.y = 0.21;
      body.castShadow = true;
      body.receiveShadow = true;
      g.add(body);

      const pinGeo = new THREE.BoxGeometry(0.06, 0.07, 0.07);
      for (let row = 0; row < 2; row++) {
        for (let col = 0; col < 6; col++) {
          const p = new THREE.Mesh(pinGeo, this.matMetalGold);
          p.position.set(-0.27, 0.13 + row * 0.16, -0.55 + col * 0.22);
          g.add(p);
        }
      }
    };

    addPmodLeft(-2.16); // JA
    addPmodLeft(0.0);   // JB
    addPmodLeft(2.0);   // JC

    // 2) Top edge: 6-pin header + 40-pin dual-row GPIO expansion header
    const addTopPinHeader = (cx, cols) => {
      const w = cols * 0.21;
      const base = new THREE.Mesh(new THREE.BoxGeometry(w, 0.14, 0.42), this.matDarkPlastic);
      base.position.set(cx, TOP_Y + 0.07, -3.65);
      base.castShadow = true;
      this.boardGroup.add(base);

      const pinGeo = new THREE.BoxGeometry(0.045, 0.34, 0.045);
      const startX = cx - ((cols - 1) * 0.20) / 2;
      for (let c = 0; c < cols; c++) {
        for (const dz of [-0.1, 0.1]) {
          const pin = new THREE.Mesh(pinGeo, this.matMetalGold);
          pin.position.set(startX + c * 0.20, TOP_Y + 0.19, -3.65 + dz);
          this.boardGroup.add(pin);
        }
      }
    };

    addTopPinHeader(-2.53, 3);  // Top JA 2x3
    addTopPinHeader(0.06, 20);  // Top JC 2x20

    // 3) Top-right: Power barrel jack / switch module (PWR) + always-on soft green PWR LED
    const pwrJack = new THREE.Mesh(new THREE.BoxGeometry(1.02, 0.56, 1.05), this.matDarkPlastic);
    pwrJack.position.set(3.50, TOP_Y + 0.28, -3.42);
    pwrJack.castShadow = true;
    this.boardGroup.add(pwrJack);

    const pwrSleeve = new THREE.Mesh(
      new THREE.CylinderGeometry(0.22, 0.22, 0.12, 20).rotateX(Math.PI / 2),
      this.matMetalSilver
    );
    pwrSleeve.position.set(3.50, TOP_Y + 0.30, -3.96);
    this.boardGroup.add(pwrSleeve);

    const pwrLedMat = new THREE.MeshStandardMaterial({
      color: 0x22ff88,
      emissive: new THREE.Color(0x10e070),
      emissiveIntensity: 2.3,
      roughness: 0.2,
    });
    const pwrLed = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.07, 0.09), pwrLedMat);
    pwrLed.position.set(5.28, TOP_Y + 0.04, 2.52);
    this.boardGroup.add(pwrLed);

    // 4) Right edge: 15-pin blue VGA connector (facing +X right edge)
    const vgaZ = -2.08;
    const vgaBlueMat = new THREE.MeshStandardMaterial({
      color: 0x1d4ed8,
      roughness: 0.42,
      metalness: 0.08,
    });
    const vgaBody = new THREE.Mesh(new THREE.BoxGeometry(0.95, 0.78, 1.92), vgaBlueMat);
    vgaBody.position.set(BOARD_W / 2 - 0.48, TOP_Y + 0.39, vgaZ);
    vgaBody.castShadow = true;
    this.boardGroup.add(vgaBody);

    const vgaFlange = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.84, 2.12), this.matMetalSilver);
    vgaFlange.position.set(BOARD_W / 2 + 0.02, TOP_Y + 0.42, vgaZ);
    vgaFlange.castShadow = true;
    this.boardGroup.add(vgaFlange);

    const vgaShroud = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.54, 1.28), this.matMetalSilver);
    vgaShroud.position.set(BOARD_W / 2 + 0.14, TOP_Y + 0.42, vgaZ);
    this.boardGroup.add(vgaShroud);

    const vgaInner = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.42, 1.14), vgaBlueMat);
    vgaInner.position.set(BOARD_W / 2 + 0.25, TOP_Y + 0.42, vgaZ);
    this.boardGroup.add(vgaInner);

    const nutGeo = new THREE.CylinderGeometry(0.10, 0.10, 0.22, 6);
    nutGeo.rotateZ(Math.PI / 2);
    for (const sz of [-0.86, 0.86]) {
      const nut = new THREE.Mesh(nutGeo, this.matMetalSilver);
      nut.position.set(BOARD_W / 2 + 0.13, TOP_Y + 0.42, vgaZ + sz);
      this.boardGroup.add(nut);
    }

    // 5) Right edge: Full-size USB-A HOST port (facing +X)
    const usbAZ = -0.06;
    const usbA = new THREE.Mesh(new THREE.BoxGeometry(0.92, 0.52, 1.48), this.matMetalSilver);
    usbA.position.set(BOARD_W / 2 - 0.44, TOP_Y + 0.26, usbAZ);
    usbA.castShadow = true;
    this.boardGroup.add(usbA);

    const usbACavity = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.34, 1.24), this.matDarkPlastic);
    usbACavity.position.set(BOARD_W / 2 + 0.03, TOP_Y + 0.27, usbAZ);
    this.boardGroup.add(usbACavity);

    const usbATongue = new THREE.Mesh(
      new THREE.BoxGeometry(0.10, 0.08, 1.12),
      new THREE.MeshStandardMaterial({ color: 0x2563eb, roughness: 0.4 })
    );
    usbATongue.position.set(BOARD_W / 2 + 0.01, TOP_Y + 0.33, usbAZ);
    this.boardGroup.add(usbATongue);

    // 6) Right edge: Micro-USB PROG port (facing +X)
    const microZ = 1.42;
    const microUsb = new THREE.Mesh(new THREE.BoxGeometry(0.58, 0.24, 0.72), this.matMetalSilver);
    microUsb.position.set(BOARD_W / 2 - 0.24, TOP_Y + 0.12, microZ);
    microUsb.castShadow = true;
    this.boardGroup.add(microUsb);

    const microCavity = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.12, 0.56), this.matDarkPlastic);
    microCavity.position.set(BOARD_W / 2 + 0.05, TOP_Y + 0.12, microZ);
    this.boardGroup.add(microCavity);
  }

  _getHit(clientX, clientY) {
    const rect = this.renderer.domElement.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return null;
    this.pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
    this.pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
    this.raycaster.setFromCamera(this.pointer, this.camera);
    const hits = this.raycaster.intersectObjects(this.interactiveMeshes, false);
    return hits.length > 0 ? hits[0].object : null;
  }

  _setHover(hitObj, clientX, clientY) {
    if (this.hoveredItem && this.hoveredItem !== hitObj) {
      const prev = this.hoveredItem.userData;
      if (prev.kind === "sw" && prev.knobMat) {
        prev.knobMat.emissive.setHex(0x000000);
        prev.knobMat.emissiveIntensity = 0;
      } else if (prev.kind === "btn" && prev.capMat) {
        prev.capMat.emissive.setHex(0x000000);
        prev.capMat.emissiveIntensity = 0;
      }
    }

    this.hoveredItem = hitObj;

    if (hitObj) {
      const d = hitObj.userData;
      this.renderer.domElement.style.cursor = "pointer";
      if (d.kind === "sw" && d.knobMat) {
        d.knobMat.emissive.setHex(0x22d3ee);
        d.knobMat.emissiveIntensity = 0.28;
      } else if (d.kind === "btn" && d.capMat) {
        d.capMat.emissive.setHex(0x38bdf8);
        d.capMat.emissiveIntensity = 0.32;
      }

      const rect = this.container.getBoundingClientRect();
      const stateSuffix =
        d.kind === "sw"
          ? ` = ${this.swState[d.index]}`
          : this.btnState[d.index]
          ? " [PRESSED]"
          : "";
      this.tooltip.textContent = `${d.label}${stateSuffix}`;
      this.tooltip.style.left = `${clientX - rect.left}px`;
      this.tooltip.style.top = `${clientY - rect.top}px`;
      this.tooltip.style.opacity = "1";
    } else {
      this.renderer.domElement.style.cursor = this.isUserOrbiting ? "grabbing" : "grab";
      this.tooltip.style.opacity = "0";
    }
  }

  _bindEvents() {
    const dom = this.renderer.domElement;

    this._onPointerMove = (e) => {
      if (this.pressedButton) return;
      const hit = this._getHit(e.clientX, e.clientY);
      this._setHover(hit, e.clientX, e.clientY);
    };

    this._onPointerDown = (e) => {
      if (e.button !== 0) return;
      this.lastInteractionTime = performance.now();
      this.controls.autoRotate = false;
      this.pointerDownPos = { x: e.clientX, y: e.clientY };

      const hit = this._getHit(e.clientX, e.clientY);
      if (hit && hit.userData.kind === "btn") {
        // Immediate tactile press on pushbutton; pause orbit while held
        const idx = hit.userData.index;
        this.pressedButton = this.buttons[idx];
        this.controls.enabled = false;
        this.btnState[idx] = 1;
        this.pressedButton.targetY = this.pressedButton.restY - 0.055;
        this._setHover(hit, e.clientX, e.clientY);
        if (this.onInput) {
          this.onInput(`btn${idx}`, 1);
        }
      }
    };

    this._onPointerUp = (e) => {
      this.lastInteractionTime = performance.now();

      // Release held pushbutton
      if (this.pressedButton) {
        const idx = this.pressedButton.index;
        this.btnState[idx] = 0;
        this.pressedButton.targetY = this.pressedButton.restY;
        this.pressedButton = null;
        this.controls.enabled = true;
        if (this.onInput) {
          this.onInput(`btn${idx}`, 0);
        }
        this.pointerDownPos = null;
        return;
      }

      // Check for crisp click on a slide switch (not an orbit drag)
      if (this.pointerDownPos) {
        const dx = e.clientX - this.pointerDownPos.x;
        const dy = e.clientY - this.pointerDownPos.y;
        this.pointerDownPos = null;
        if (Math.hypot(dx, dy) < 6) {
          const hit = this._getHit(e.clientX, e.clientY);
          if (hit && hit.userData.kind === "sw") {
            const idx = hit.userData.index;
            const nextVal = this.swState[idx] ? 0 : 1;
            this.swState[idx] = nextVal;
            const sw = this.switches[idx];
            if (sw) sw.targetZ = nextVal ? sw.onZ : sw.offZ;
            this._setHover(hit, e.clientX, e.clientY);
            if (this.onInput) {
              this.onInput(`sw${idx}`, nextVal);
            }
          }
        }
      }
    };

    this._onPointerLeave = () => {
      if (!this.pressedButton) {
        this._setHover(null, 0, 0);
      }
    };

    dom.addEventListener("pointermove", this._onPointerMove);
    dom.addEventListener("pointerdown", this._onPointerDown);
    dom.addEventListener("pointerleave", this._onPointerLeave);
    window.addEventListener("pointerup", this._onPointerUp);

    // Responsive resizing
    this.resizeObserver = new ResizeObserver(() => this._resize());
    this.resizeObserver.observe(this.container);
  }

  _resize() {
    if (this.disposed) return;
    const w = Math.max(1, this.container.clientWidth);
    const h = Math.max(1, this.container.clientHeight);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(w, h);
    this.composer.setSize(w, h);
    this.bloomPass.setSize(w, h);
  }

  update(state = {}) {
    if (!state || this.disposed) return;

    // 1) Slide switches: sw[16] or 16-bit int
    if (state.sw !== undefined) {
      for (let i = 0; i < 16; i++) {
        const v = readBit(state.sw, i, 0);
        this.swState[i] = v;
        const sw = this.switches[i];
        if (sw) sw.targetZ = v ? sw.onZ : sw.offZ;
      }
    }

    // 2) Pushbuttons: btn[5] or 5-bit int
    if (state.btn !== undefined) {
      for (let i = 0; i < 5; i++) {
        const v = readBit(state.btn, i, 0);
        this.btnState[i] = v;
        const b = this.buttons[i];
        if (b && this.pressedButton !== b) {
          b.targetY = v ? b.restY - 0.055 : b.restY;
        }
      }
    }

    // 3) 16 LEDs: led[16] or 16-bit int
    if (state.led !== undefined) {
      for (let i = 0; i < 16; i++) {
        const v = readBit(state.led, i, 0);
        this.ledState[i] = v;
        const led = this.leds[i];
        if (led) {
          if (v) {
            led.lensMat.color.setHex(0x86efac);
            led.lensMat.emissive.setHex(0x22ff66);
            led.lensMat.emissiveIntensity = 3.4;
          } else {
            led.lensMat.color.setHex(0x1e3a28);
            led.lensMat.emissiveIntensity = 0.0;
          }
        }
      }
    }

    // 4) 4-digit 7-segment display
    // Supports either state.digits = [d0, d1, d2, d3] (active-low 7-bit masks)
    // OR standard state.seg[7] + state.an[4] (active-low, matching Basys 3 / board_sim.py)
    if (Array.isArray(state.digits) && state.digits.length === 4) {
      for (let d = 0; d < 4; d++) {
        this.digitMasks[d] = typeof state.digits[d] === "number" ? state.digits[d] : 0x7f;
      }
      this._applySevenSegMaterials();
    } else if (state.seg !== undefined || state.an !== undefined) {
      let segMask = 0x7f;
      if (state.seg !== undefined) {
        segMask = 0;
        for (let s = 0; s < 7; s++) {
          if (readBit(state.seg, s, 1)) segMask |= 1 << s;
        }
      }
      for (let d = 0; d < 4; d++) {
        const anBit = state.an !== undefined ? readBit(state.an, d, 1) : 0;
        // Active-low anode: 0 means digit enabled
        this.digitMasks[d] = anBit === 0 ? segMask : 0x7f;
      }
      this._applySevenSegMaterials();
    }
  }

  _applySevenSegMaterials() {
    for (let d = 0; d < 4; d++) {
      const mask = this.digitMasks[d];
      const mats = this.digitSegments[d];
      if (!mats) continue;
      for (let s = 0; s < 7; s++) {
        const isLit = (mask & (1 << s)) === 0; // active-low
        const mat = mats[s];
        if (isLit) {
          mat.color.setHex(0xff3344);
          mat.emissive.setHex(0xff1428);
          mat.emissiveIntensity = 5.8;
        } else {
          mat.color.setHex(0x2b1316);
          mat.emissiveIntensity = 0.0;
        }
      }
    }
  }

  resetCamera() {
    this.camera.position.set(0.0, 9.8, 10.6);
    this.controls.target.set(0, 0, 0.15);
    this.controls.update();
  }

  _animate() {
    if (this.disposed) return;
    this.animFrameId = requestAnimationFrame(() => this._animate());

    const dt = Math.min(this.clock.getDelta(), 0.05);
    const lerpFactor = 1 - Math.exp(-18 * dt);

    // Smoothly animate slide switch actuators
    for (let i = 0; i < 16; i++) {
      const sw = this.switches[i];
      if (sw) {
        sw.knob.position.z += (sw.targetZ - sw.knob.position.z) * lerpFactor;
      }
    }

    // Smoothly animate pushbutton plungers
    for (let i = 0; i < 5; i++) {
      const b = this.buttons[i];
      if (b) {
        b.cap.position.y += (b.targetY - b.cap.position.y) * lerpFactor;
      }
    }

    // Resume gentle auto-rotate when idle
    if (
      this.autoRotateEnabled &&
      !this.isUserOrbiting &&
      !this.pressedButton &&
      performance.now() - this.lastInteractionTime > IDLE_ROTATE_DELAY_MS
    ) {
      this.controls.autoRotate = true;
    }

    this.controls.update();
    this.composer.render();
  }

  destroy() {
    this.disposed = true;
    if (this.animFrameId !== null) cancelAnimationFrame(this.animFrameId);
    if (this.resizeObserver) this.resizeObserver.disconnect();

    const dom = this.renderer.domElement;
    dom.removeEventListener("pointermove", this._onPointerMove);
    dom.removeEventListener("pointerdown", this._onPointerDown);
    dom.removeEventListener("pointerleave", this._onPointerLeave);
    window.removeEventListener("pointerup", this._onPointerUp);

    this.controls.dispose();
    if (this.envRT) this.envRT.dispose();
    this.composer.dispose();
    this.renderer.dispose();
    if (dom.parentNode === this.container) this.container.removeChild(dom);
    if (this.tooltip.parentNode === this.container) this.container.removeChild(this.tooltip);
  }
}

/**
 * Initialize the 3D virtual FPGA board inside containerElement.
 * @param {HTMLElement} containerElement
 * @param {Function|Object} [optionsOrOnInput] - onInput(name, value) callback or { onInput, textureUrl, autoRotate }
 */
export function init(containerElement, optionsOrOnInput) {
  if (!containerElement) {
    throw new Error("board3d.init requires a containerElement");
  }
  if (activeInstance) {
    activeInstance.destroy();
    activeInstance = null;
  }
  activeInstance = new VirtualFPGABoard3D(containerElement, optionsOrOnInput);
  return activeInstance;
}

/**
 * Update the 3D board visual state.
 * @param {{ sw?: number[]|number, btn?: number[]|number, led?: number[]|number, seg?: number[]|number, an?: number[]|number, digits?: number[] }} state
 */
export function update(state) {
  if (!activeInstance) return;
  activeInstance.update(state);
}
