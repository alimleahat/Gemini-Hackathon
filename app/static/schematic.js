/* Clean Left-to-Right SVG Digital Schematic Renderer powered by elkjs.
 * - Automatic layered layout: inputs on the left, gates in the middle, outputs on the right.
 * - Clean orthogonal wire routing using elkjs bend points (never overlaps labels or parts).
 * - Preserves IEEE/ANSI gate shapes, uncertain amber dashed styling, module boxes,
 *   compact thumbnail mode, and design-issue red highlights.
 */

window.SchematicRenderer = (function () {
  const SVG_NS = "http://www.w3.org/2000/svg";
  const elk = typeof window.ELK === "function" ? new window.ELK() : null;
  const renderSeq = new WeakMap();

  function el(tag, attrs = {}, text = null) {
    const node = document.createElementNS(SVG_NS, tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v !== null && v !== undefined) node.setAttribute(k, String(v));
    }
    if (text !== null && text !== undefined) node.textContent = String(text);
    return node;
  }

  function nodeSize(item, compact) {
    const t = (item.type || "box").toLowerCase();
    const labelLen = String(item.module_name || item.label || "").length;
    if (compact) {
      if (t === "module_instance") return { w: Math.max(66, labelLen * 6 + 22), h: 36 };
      if (t === "input" || t === "output" || t === "clock") return { w: Math.max(46, labelLen * 6 + 18), h: 24 };
      return { w: 48, h: 36 };
    }
    if (t === "module_instance") return { w: Math.max(104, labelLen * 8.5 + 34), h: 58 };
    if (t === "input" || t === "output" || t === "clock") return { w: Math.max(72, labelLen * 8 + 28), h: 34 };
    if (t === "dff") return { w: Math.max(72, labelLen * 7.5 + 24), h: 66 };
    if (t === "mux") return { w: 68, h: 66 };
    // Gates: leave room underneath for label text so labels never collide with adjacent nodes
    return { w: Math.max(74, labelLen * 7.5 + 22), h: 64 };
  }

  function fallbackLayout(elements, wires, compact) {
    // Deterministic left-to-right layered fallback if ELK is unavailable
    const inputs = [];
    const outputs = [];
    const mids = [];
    for (const item of elements) {
      const t = (item.type || "").toLowerCase();
      if (t === "input" || t === "clock") inputs.push(item);
      else if (t === "output") outputs.push(item);
      else mids.push(item);
    }

    const colGap = compact ? 95 : 155;
    const rowGap = compact ? 52 : 94;
    const padX = compact ? 36 : 56;
    const padY = compact ? 28 : 44;

    const cols = [];
    if (inputs.length) cols.push(inputs);
    if (mids.length) cols.push(mids);
    if (outputs.length) cols.push(outputs);
    if (!cols.length) cols.push(elements);

    const children = [];
    const pos = new Map();
    let maxW = 0;
    let maxH = 0;

    cols.forEach((col, ci) => {
      col.sort((a, b) => (Number(a.y) || 0) - (Number(b.y) || 0));
      col.forEach((item, ri) => {
        const sz = nodeSize(item, compact);
        const x = padX + ci * colGap;
        const y = padY + ri * rowGap;
        children.push({ id: item.id, x, y, width: sz.w, height: sz.h });
        pos.set(item.id, { x, y, width: sz.w, height: sz.h });
        maxW = Math.max(maxW, x + sz.w + padX);
        maxH = Math.max(maxH, y + sz.h + padY);
      });
    });

    const edges = [];
    wires.forEach((w, idx) => {
      const a = pos.get(w.from_id);
      const b = pos.get(w.to_id);
      if (!a || !b) return;
      const x1 = a.x + a.width;
      const y1 = a.y + a.height / 2;
      const x2 = b.x;
      const y2 = b.y + b.height / 2;
      const midX = (x1 + x2) / 2;
      edges.push({
        id: `e_${idx}`,
        sources: [w.from_id],
        targets: [w.to_id],
        sections: [
          {
            startPoint: { x: x1, y: y1 },
            bendPoints: [
              { x: midX, y: y1 },
              { x: midX, y: y2 },
            ],
            endPoint: { x: x2, y: y2 },
          },
        ],
      });
    });

    return { width: Math.max(maxW, 300), height: Math.max(maxH, 180), children, edges };
  }

  async function computeElkLayout(elements, wires, compact) {
    if (!elk) return fallbackLayout(elements, wires, compact);

    const idSet = new Set(elements.map((e) => e.id));
    const elkNodes = elements.map((item) => {
      const sz = nodeSize(item, compact);
      const t = (item.type || "box").toLowerCase();
      const layoutOptions = {};
      if (t === "input" || t === "clock") {
        layoutOptions["elk.layered.layering.layerConstraint"] = "FIRST";
      } else if (t === "output") {
        layoutOptions["elk.layered.layering.layerConstraint"] = "LAST";
      }
      return {
        id: item.id,
        width: sz.w,
        height: sz.h,
        layoutOptions,
      };
    });

    const elkEdges = [];
    wires.forEach((w, idx) => {
      if (idSet.has(w.from_id) && idSet.has(w.to_id) && w.from_id !== w.to_id) {
        elkEdges.push({
          id: `e_${idx}`,
          sources: [w.from_id],
          targets: [w.to_id],
        });
      }
    });

    const graph = {
      id: "root",
      layoutOptions: {
        "elk.algorithm": "layered",
        "elk.direction": "RIGHT",
        "elk.edgeRouting": "ORTHOGONAL",
        "elk.layered.spacing.nodeNodeBetweenLayers": compact ? "46" : "76",
        "elk.spacing.nodeNode": compact ? "24" : "42",
        "elk.spacing.edgeNode": compact ? "16" : "26",
        "elk.spacing.edgeEdge": compact ? "10" : "18",
        "elk.layered.nodePlacement.strategy": "NETWORK_SIMPLEX",
        "elk.layered.crossingMinimization.strategy": "LAYER_SWEEP",
        "elk.padding": compact ? "[top=18,left=20,bottom=18,right=20]" : "[top=36,left=36,bottom=32,right=36]",
      },
      children: elkNodes,
      edges: elkEdges,
    };

    try {
      return await elk.layout(graph);
    } catch (_) {
      return fallbackLayout(elements, wires, compact);
    }
  }

  function render(container, schematic, options = {}) {
    if (!container) return;
    const compact = Boolean(options.compact);

    if (!schematic || (!schematic.elements?.length && !schematic.boxes?.length)) {
      drawEmpty(container, compact);
      return;
    }

    const seq = (renderSeq.get(container) || 0) + 1;
    renderSeq.set(container, seq);

    const elements = schematic.elements || [];
    const wires = schematic.wires || [];

    computeElkLayout(elements, wires, compact).then((laidOut) => {
      // Drop stale async layout if a newer render was requested
      if (renderSeq.get(container) !== seq) return;
      drawLaidOutSVG(container, schematic, laidOut, options);
    });
  }

  function drawEmpty(container, compact) {
    const W = compact ? 260 : 680;
    const H = compact ? 150 : 380;
    container.innerHTML = "";
    const svg = el("svg", {
      viewBox: `0 0 ${W} ${H}`,
      class: compact ? "schematic-svg compact" : "schematic-svg",
    });
    svg.appendChild(el("rect", { x: 0, y: 0, width: W, height: H, fill: "#090912", rx: 10 }));
    svg.appendChild(
      el(
        "text",
        {
          x: W / 2,
          y: H / 2,
          "text-anchor": "middle",
          fill: "#7c7e94",
          "font-size": compact ? 11 : 14,
          "font-family": "Inter, -apple-system, sans-serif",
        },
        compact ? "No preview" : "Waiting for circuit drawing..."
      )
    );
    container.appendChild(svg);
  }

  function drawLaidOutSVG(container, schematic, laidOut, options) {
    const compact = Boolean(options.compact);
    const highlightedIds = new Set(options.highlightedIds || []);
    const highlightedLabels = new Set(
      (options.highlightedLabels || []).map((s) => String(s).toLowerCase())
    );

    const W = Math.max(compact ? 260 : 520, Math.ceil(laidOut.width || 600));
    const H = Math.max(compact ? 140 : 300, Math.ceil(laidOut.height || 340));

    container.innerHTML = "";
    const svg = el("svg", {
      viewBox: `0 0 ${W} ${H}`,
      preserveAspectRatio: "xMidYMid meet",
      class: compact ? "schematic-svg compact" : "schematic-svg",
    });

    // Blueprint grid background
    const defs = el("defs");
    const gridId = `grid-${Math.random().toString(36).slice(2, 8)}`;
    const pat = el("pattern", {
      id: gridId,
      width: compact ? 16 : 24,
      height: compact ? 16 : 24,
      patternUnits: "userSpaceOnUse",
    });
    pat.appendChild(
      el("path", {
        d: compact ? "M 16 0 L 0 0 0 16" : "M 24 0 L 0 0 0 24",
        fill: "none",
        stroke: "rgba(167, 139, 250, 0.08)",
        "stroke-width": 1,
      })
    );
    defs.appendChild(pat);
    svg.appendChild(defs);

    svg.appendChild(el("rect", { x: 0, y: 0, width: W, height: H, fill: "#090912", rx: 10 }));
    svg.appendChild(el("rect", { x: 0, y: 0, width: W, height: H, fill: `url(#${gridId})`, rx: 10 }));

    // Map laid-out node rectangles by ID
    const elemById = new Map((schematic.elements || []).map((e) => [e.id, e]));
    const rectById = new Map();
    for (const child of laidOut.children || []) {
      rectById.set(child.id, {
        x: child.x || 0,
        y: child.y || 0,
        w: child.width || 60,
        h: child.height || 48,
      });
    }

    // 1. Draw module definition boxes around their contained laid-out elements
    for (const box of schematic.boxes || []) {
      const contained = (box.contains_ids || []).map((id) => rectById.get(id)).filter(Boolean);
      if (!contained.length) continue;
      const pad = compact ? 10 : 18;
      const minX = Math.min(...contained.map((r) => r.x)) - pad;
      const minY = Math.min(...contained.map((r) => r.y)) - pad;
      const maxX = Math.max(...contained.map((r) => r.x + r.w)) + pad;
      const maxY = Math.max(...contained.map((r) => r.y + r.h)) + pad;
      const stroke = box.uncertain ? "#f59e0b" : box.is_definition ? "#a855f7" : "#38bdf8";

      svg.appendChild(
        el("rect", {
          x: minX,
          y: minY,
          width: maxX - minX,
          height: maxY - minY,
          rx: 10,
          fill: box.is_definition ? "rgba(168, 85, 247, 0.08)" : "rgba(56, 189, 248, 0.06)",
          stroke,
          "stroke-width": compact ? 1.4 : 2,
          "stroke-dasharray": "6 4",
        })
      );
      if (box.name) {
        svg.appendChild(
          el(
            "text",
            {
              x: minX + 8,
              y: Math.max(14, minY - 6),
              fill: stroke,
              "font-size": compact ? 9 : 12,
              "font-weight": "700",
              "font-family": "ui-monospace, monospace",
            },
            box.is_definition ? `[MOD] ${box.name}` : box.name
          )
        );
      }
    }

    // 2. Draw clean ELK-routed orthogonal wires
    const wires = schematic.wires || [];
    const wireByEdgeId = new Map();
    let eIdx = 0;
    const idSet = new Set((schematic.elements || []).map((e) => e.id));
    wires.forEach((w, idx) => {
      if (idSet.has(w.from_id) && idSet.has(w.to_id) && w.from_id !== w.to_id) {
        wireByEdgeId.set(`e_${idx}`, w);
        eIdx++;
      }
    });

    const wireGroup = el("g", { class: "schematic-wires" });
    for (const edge of laidOut.edges || []) {
      const w = wireByEdgeId.get(edge.id) || {};
      const isFlagged =
        (w.label && highlightedLabels.has(String(w.label).toLowerCase())) ||
        highlightedIds.has(`${w.from_id}->${w.to_id}`);
      const stroke = isFlagged ? "#ef4444" : w.uncertain ? "#f59e0b" : "#38bdf8";

      for (const sec of edge.sections || []) {
        const pts = [sec.startPoint, ...(sec.bendPoints || []), sec.endPoint].filter(Boolean);
        if (pts.length < 2) continue;

        const dStr = pts.map((p, i) => `${i === 0 ? "M" : "L"} ${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(" ");
        wireGroup.appendChild(
          el("path", {
            d: dStr,
            fill: "none",
            stroke,
            "stroke-width": isFlagged ? 3.2 : compact ? 1.4 : 2.2,
            "stroke-dasharray": w.uncertain ? "5 4" : null,
            "stroke-linejoin": "round",
            "stroke-linecap": "round",
          })
        );

        const pStart = pts[0];
        const pEnd = pts[pts.length - 1];
        wireGroup.appendChild(el("circle", { cx: pStart.x, cy: pStart.y, r: compact ? 2 : 3.2, fill: stroke }));
        wireGroup.appendChild(el("circle", { cx: pEnd.x, cy: pEnd.y, r: compact ? 2 : 3.2, fill: stroke }));

        // Place wire label cleanly on the longest segment with a dark pill backdrop
        if (w.label && !compact) {
          let bestLen = -1;
          let bestMid = { x: (pStart.x + pEnd.x) / 2, y: (pStart.y + pEnd.y) / 2 };
          for (let i = 0; i < pts.length - 1; i++) {
            const dx = pts[i + 1].x - pts[i].x;
            const dy = pts[i + 1].y - pts[i].y;
            const len = Math.hypot(dx, dy);
            if (len > bestLen) {
              bestLen = len;
              bestMid = { x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2 };
            }
          }
          const lbl = String(w.label);
          const pillW = lbl.length * 6.5 + 10;
          wireGroup.appendChild(
            el("rect", {
              x: bestMid.x - pillW / 2,
              y: bestMid.y - 16,
              width: pillW,
              height: 15,
              rx: 4,
              fill: "#0b1220",
              stroke: "rgba(56,189,248,0.28)",
              "stroke-width": 1,
            })
          );
          wireGroup.appendChild(
            el(
              "text",
              {
                x: bestMid.x,
                y: bestMid.y - 5,
                "text-anchor": "middle",
                fill: isFlagged ? "#fca5a5" : "#cbd5e1",
                "font-size": 10,
                "font-weight": "600",
                "font-family": "ui-monospace, monospace",
              },
              lbl
            )
          );
        }
      }
    }
    svg.appendChild(wireGroup);

    // 3. Draw laid-out elements (inputs, gates, outputs, modules)
    const elemGroup = el("g", { class: "schematic-elements" });
    for (const child of laidOut.children || []) {
      const item = elemById.get(child.id);
      if (!item) continue;
      const cx = (child.x || 0) + (child.width || 60) / 2;
      const cy = (child.y || 0) + (child.height || 48) / 2;

      const isFlagged =
        highlightedIds.has(item.id) ||
        (item.label && highlightedLabels.has(String(item.label).toLowerCase()));

      elemGroup.appendChild(drawElementSymbol(item, cx, cy, child.width, child.height, { compact, isFlagged }));
    }
    svg.appendChild(elemGroup);

    // Title watermark top-left
    if (!compact && schematic.circuit_title) {
      svg.appendChild(
        el(
          "text",
          {
            x: 12,
            y: 20,
            fill: "#94a3b8",
            "font-size": 12,
            "font-weight": "700",
            "font-family": "ui-monospace, monospace",
          },
          schematic.circuit_title
        )
      );
    }

    container.appendChild(svg);
  }

  function drawElementSymbol(item, cx, cy, w, h, { compact, isFlagged }) {
    const g = el("g", { transform: `translate(${cx}, ${cy})`, "data-element-id": item.id });
    const s = compact ? 0.62 : 1.0;
    const stroke = isFlagged ? "#ef4444" : item.uncertain ? "#f59e0b" : "#e2e8f0";
    const fill = isFlagged
      ? "rgba(239, 68, 68, 0.22)"
      : item.uncertain
      ? "rgba(245, 158, 11, 0.14)"
      : "#111c2e";
    const dash = item.uncertain ? "4 3" : null;
    const sw = isFlagged ? 2.8 : 2;
    const t = (item.type || "box").toLowerCase();

    if (isFlagged) {
      g.appendChild(
        el("rect", {
          x: -w / 2 - 5,
          y: -h / 2 - 5,
          width: w + 10,
          height: h + 10,
          rx: 10,
          fill: "rgba(239, 68, 68, 0.14)",
          stroke: "#ef4444",
          "stroke-width": 1.8,
          "stroke-dasharray": "4 3",
        })
      );
    }

    if (t === "input" || t === "clock") {
      const hw = w / 2 - 2;
      const hh = h / 2 - 2;
      g.appendChild(
        el("polygon", {
          points: `${-hw},${-hh} ${hw - 10 * s},${-hh} ${hw},0 ${hw - 10 * s},${hh} ${-hw},${hh}`,
          fill: t === "clock" ? "#1e1b4b" : "#0c2238",
          stroke: isFlagged ? "#ef4444" : item.uncertain ? "#f59e0b" : "#38bdf8",
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      g.appendChild(
        el(
          "text",
          {
            x: -4 * s,
            y: 4 * s,
            "text-anchor": "middle",
            fill: "#f8fafc",
            "font-size": 11.5 * s,
            "font-weight": "700",
            "font-family": "ui-monospace, monospace",
          },
          item.label || (t === "clock" ? "CLK" : "IN")
        )
      );
    } else if (t === "output") {
      const hw = w / 2 - 2;
      const hh = h / 2 - 2;
      g.appendChild(
        el("polygon", {
          points: `${-hw},0 ${-hw + 10 * s},${-hh} ${hw},${-hh} ${hw},${hh} ${-hw + 10 * s},${hh}`,
          fill: "#052e16",
          stroke: isFlagged ? "#ef4444" : item.uncertain ? "#f59e0b" : "#22c55e",
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      g.appendChild(
        el(
          "text",
          {
            x: 4 * s,
            y: 4 * s,
            "text-anchor": "middle",
            fill: "#dcfce7",
            "font-size": 11.5 * s,
            "font-weight": "700",
            "font-family": "ui-monospace, monospace",
          },
          item.label || "OUT"
        )
      );
    } else if (t === "and" || t === "nand") {
      const gy = -6 * s;
      g.appendChild(
        el("path", {
          d: `M ${-22 * s} ${gy - 18 * s} L 0 ${gy - 18 * s} A ${18 * s} ${18 * s} 0 0 1 0 ${gy + 18 * s} L ${-22 * s} ${gy + 18 * s} Z`,
          fill,
          stroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      if (t === "nand") {
        g.appendChild(el("circle", { cx: 22 * s, cy: gy, r: 4 * s, fill: "#070c15", stroke, "stroke-width": sw }));
      }
      addGateLabel(g, item.label || t.toUpperCase(), s, compact, h / 2 - 4);
    } else if (t === "or" || t === "nor" || t === "xor" || t === "xnor") {
      const gy = -6 * s;
      g.appendChild(
        el("path", {
          d: `M ${-22 * s} ${gy - 18 * s} Q ${-12 * s} ${gy} ${-22 * s} ${gy + 18 * s} L ${-4 * s} ${gy + 18 * s} Q ${14 * s} ${gy + 16 * s} ${22 * s} ${gy} Q ${14 * s} ${gy - 16 * s} ${-4 * s} ${gy - 18 * s} Z`,
          fill,
          stroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      if (t === "xor" || t === "xnor") {
        g.appendChild(
          el("path", {
            d: `M ${-28 * s} ${gy - 17 * s} Q ${-18 * s} ${gy} ${-28 * s} ${gy + 17 * s}`,
            fill: "none",
            stroke,
            "stroke-width": sw,
          })
        );
      }
      if (t === "nor" || t === "xnor") {
        g.appendChild(el("circle", { cx: 26 * s, cy: gy, r: 4 * s, fill: "#070c15", stroke, "stroke-width": sw }));
      }
      addGateLabel(g, item.label || t.toUpperCase(), s, compact, h / 2 - 4);
    } else if (t === "not") {
      const gy = -6 * s;
      g.appendChild(
        el("polygon", {
          points: `${-20 * s},${gy - 16 * s} ${16 * s},${gy} ${-20 * s},${gy + 16 * s}`,
          fill,
          stroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      g.appendChild(el("circle", { cx: 20 * s, cy: gy, r: 4 * s, fill: "#070c15", stroke, "stroke-width": sw }));
      addGateLabel(g, item.label || "NOT", s, compact, h / 2 - 4);
    } else if (t === "dff") {
      g.appendChild(
        el("rect", {
          x: -w / 2 + 4,
          y: -h / 2 + 4,
          width: w - 8,
          height: h - 8,
          rx: 5,
          fill,
          stroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      g.appendChild(
        el("polyline", {
          points: `${-w / 2 + 4},${h / 2 - 18} ${-w / 2 + 12},${h / 2 - 13} ${-w / 2 + 4},${h / 2 - 8}`,
          fill: "none",
          stroke,
          "stroke-width": 1.6,
        })
      );
      g.appendChild(
        el(
          "text",
          { x: 0, y: 4 * s, "text-anchor": "middle", fill: "#f8fafc", "font-size": 11 * s, "font-weight": "700", "font-family": "ui-monospace, monospace" },
          item.label || "DFF"
        )
      );
    } else if (t === "mux") {
      g.appendChild(
        el("polygon", {
          points: `${-w / 2 + 4},${-h / 2 + 4} ${w / 2 - 4},${-h / 2 + 14} ${w / 2 - 4},${h / 2 - 14} ${-w / 2 + 4},${h / 2 - 4}`,
          fill,
          stroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      g.appendChild(
        el(
          "text",
          { x: 0, y: 4 * s, "text-anchor": "middle", fill: "#f8fafc", "font-size": 10.5 * s, "font-weight": "700", "font-family": "ui-monospace, monospace" },
          item.label || "MUX"
        )
      );
    } else if (t === "module_instance") {
      const modStroke = isFlagged ? "#ef4444" : item.uncertain ? "#f59e0b" : "#a855f7";
      g.appendChild(
        el("rect", {
          x: -w / 2 + 2,
          y: -h / 2 + 2,
          width: w - 4,
          height: h - 4,
          rx: 7,
          fill: "rgba(168, 85, 247, 0.16)",
          stroke: modStroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      g.appendChild(
        el(
          "text",
          { x: 0, y: compact ? 3 : -3, "text-anchor": "middle", fill: "#e9d5ff", "font-size": 11.5 * s, "font-weight": "800", "font-family": "ui-monospace, monospace" },
          item.module_name || item.label || "MOD"
        )
      );
      if (!compact) {
        g.appendChild(
          el("text", { x: 0, y: 14, "text-anchor": "middle", fill: "#c084fc", "font-size": 8.5, "font-family": "ui-monospace, monospace" }, "MODULE")
        );
      }
    } else {
      g.appendChild(
        el("rect", {
          x: -w / 2 + 3,
          y: -h / 2 + 3,
          width: w - 6,
          height: h - 6,
          rx: 6,
          fill,
          stroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      g.appendChild(
        el(
          "text",
          { x: 0, y: 4 * s, "text-anchor": "middle", fill: "#f8fafc", "font-size": 10.5 * s, "font-weight": "700", "font-family": "ui-monospace, monospace" },
          item.label || t.toUpperCase()
        )
      );
    }

    if (item.uncertain && !compact) {
      g.appendChild(el("circle", { cx: w / 2 - 4, cy: -h / 2 + 6, r: 8, fill: "#f59e0b" }));
      g.appendChild(
        el("text", { x: w / 2 - 4, y: -h / 2 + 10, "text-anchor": "middle", fill: "#0b0f17", "font-size": 11, "font-weight": "900" }, "?")
      );
    }

    return g;
  }

  function addGateLabel(g, text, s, compact, yPos) {
    if (compact) return;
    g.appendChild(
      el(
        "text",
        {
          x: 0,
          y: yPos,
          "text-anchor": "middle",
          fill: "#cbd5e1",
          "font-size": 10.5,
          "font-weight": "700",
          "font-family": "ui-monospace, monospace",
        },
        text
      )
    );
  }

  return { render };
})();
