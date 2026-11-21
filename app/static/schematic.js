/* Pure SVG Digital Schematic Renderer (normal drawing code, no image generation).
 * Renders structured schematic JSON (elements, boxes, wires) roughly matching the
 * spatial layout on paper, with crisp IEEE/ANSI gate shapes, orthogonal wire routing,
 * uncertain-part amber dashed styling, and optional issue-flag highlights.
 */

window.SchematicRenderer = (function () {
  const SVG_NS = "http://www.w3.org/2000/svg";

  function el(tag, attrs = {}, text = null) {
    const node = document.createElementNS(SVG_NS, tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v !== null && v !== undefined) node.setAttribute(k, String(v));
    }
    if (text !== null && text !== undefined) node.textContent = String(text);
    return node;
  }

  function clamp(v, lo, hi) {
    return Math.max(lo, Math.min(hi, v));
  }

  function render(container, schematic, options = {}) {
    if (!container) return;
    const compact = Boolean(options.compact);
    const W = compact ? 260 : 680;
    const H = compact ? 150 : 400;
    const padX = compact ? 24 : 52;
    const padY = compact ? 20 : 38;

    const highlightedIds = new Set(options.highlightedIds || []);
    const highlightedLabels = new Set(
      (options.highlightedLabels || []).map((s) => String(s).toLowerCase())
    );

    container.innerHTML = "";

    const svg = el("svg", {
      viewBox: `0 0 ${W} ${H}`,
      class: compact ? "schematic-svg compact" : "schematic-svg",
    });

    // Background + subtle blueprint grid
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
        stroke: "rgba(56, 189, 248, 0.08)",
        "stroke-width": 1,
      })
    );
    defs.appendChild(pat);
    svg.appendChild(defs);

    svg.appendChild(el("rect", { x: 0, y: 0, width: W, height: H, fill: "#070c15", rx: 10 }));
    svg.appendChild(el("rect", { x: 0, y: 0, width: W, height: H, fill: `url(#${gridId})`, rx: 10 }));

    if (!schematic || (!schematic.elements?.length && !schematic.boxes?.length)) {
      svg.appendChild(
        el(
          "text",
          {
            x: W / 2,
            y: H / 2,
            "text-anchor": "middle",
            fill: "#64748b",
            "font-size": compact ? 11 : 15,
            "font-family": "ui-monospace, monospace",
          },
          compact ? "No preview" : "Waiting for clear drawing on camera..."
        )
      );
      container.appendChild(svg);
      return;
    }

    const toX = (nx) => padX + (clamp(Number(nx) || 50, 2, 98) / 100) * (W - padX * 2);
    const toY = (ny) => padY + (clamp(Number(ny) || 50, 2, 98) / 100) * (H - padY * 2);

    // 1. Draw bounding boxes (e.g. module definitions) behind wires & gates
    const boxes = schematic.boxes || [];
    for (const box of boxes) {
      const bx = toX(box.x);
      const by = toY(box.y);
      const bw = Math.max(compact ? 40 : 80, (clamp(Number(box.width) || 30, 8, 95) / 100) * (W - padX * 2));
      const bh = Math.max(compact ? 30 : 60, (clamp(Number(box.height) || 30, 8, 95) / 100) * (H - padY * 2));
      const stroke = box.uncertain ? "#f59e0b" : box.is_definition ? "#a855f7" : "#38bdf8";

      svg.appendChild(
        el("rect", {
          x: bx,
          y: by,
          width: Math.min(bw, W - bx - 8),
          height: Math.min(bh, H - by - 8),
          rx: 8,
          fill: box.is_definition ? "rgba(168, 85, 247, 0.08)" : "rgba(56, 189, 248, 0.06)",
          stroke,
          "stroke-width": compact ? 1.4 : 2,
          "stroke-dasharray": box.is_definition || box.uncertain ? "6 4" : null,
        })
      );
      if (box.name) {
        svg.appendChild(
          el(
            "text",
            {
              x: bx + 8,
              y: Math.max(14, by - 5),
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

    // Index element coordinates for wire routing
    const posMap = new Map();
    const elements = schematic.elements || [];
    for (const item of elements) {
      posMap.set(item.id, {
        x: toX(item.x),
        y: toY(item.y),
        item,
      });
    }

    // 2. Draw orthogonal wires
    const wires = schematic.wires || [];
    const wireGroup = el("g", { class: "schematic-wires" });
    for (const w of wires) {
      const a = posMap.get(w.from_id);
      const b = posMap.get(w.to_id);
      if (!a || !b) continue;

      const isFlagged =
        (w.label && highlightedLabels.has(w.label.toLowerCase())) ||
        highlightedIds.has(`${w.from_id}->${w.to_id}`);

      const stroke = isFlagged ? "#ef4444" : w.uncertain ? "#f59e0b" : "#38bdf8";
      const x1 = a.x + (compact ? 14 : 26);
      const y1 = a.y;
      const x2 = b.x - (compact ? 14 : 26);
      const y2 = b.y;
      const midX = x1 <= x2 ? (x1 + x2) / 2 : x1 + (compact ? 10 : 18);

      let pathD;
      if (x1 <= x2) {
        pathD = `M ${x1} ${y1} L ${midX} ${y1} L ${midX} ${y2} L ${x2} ${y2}`;
      } else {
        // Feedback loop routing (e.g. latch / FSM)
        const loopY = Math.min(y1, y2) - (compact ? 18 : 34);
        pathD = `M ${x1} ${y1} L ${midX} ${y1} L ${midX} ${loopY} L ${x2 - 14} ${loopY} L ${x2 - 14} ${y2} L ${x2} ${y2}`;
      }

      wireGroup.appendChild(
        el("path", {
          d: pathD,
          fill: "none",
          stroke,
          "stroke-width": isFlagged ? 3.2 : compact ? 1.3 : 2.1,
          "stroke-dasharray": w.uncertain ? "5 4" : null,
          "stroke-linejoin": "round",
        })
      );

      // Endpoint dots
      wireGroup.appendChild(el("circle", { cx: x1, cy: y1, r: compact ? 2 : 3, fill: stroke }));
      wireGroup.appendChild(el("circle", { cx: x2, cy: y2, r: compact ? 2 : 3, fill: stroke }));

      if (w.label && !compact) {
        wireGroup.appendChild(
          el(
            "text",
            {
              x: (x1 + x2) / 2,
              y: Math.min(y1, y2) - 5,
              "text-anchor": "middle",
              fill: isFlagged ? "#fca5a5" : "#94a3b8",
              "font-size": 10,
              "font-family": "ui-monospace, monospace",
            },
            w.label
          )
        );
      }
    }
    svg.appendChild(wireGroup);

    // 3. Draw elements (gates, inputs, outputs, DFF, MUX, module instances)
    const elemGroup = el("g", { class: "schematic-elements" });
    for (const item of elements) {
      const p = posMap.get(item.id);
      if (!p) continue;

      const isFlagged =
        highlightedIds.has(item.id) ||
        (item.label && highlightedLabels.has(item.label.toLowerCase()));

      const g = drawElementSymbol(item, p.x, p.y, { compact, isFlagged });
      elemGroup.appendChild(g);
    }
    svg.appendChild(elemGroup);

    // Title watermark in top-left of full schematic
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

  function drawElementSymbol(item, cx, cy, { compact, isFlagged }) {
    const g = el("g", { transform: `translate(${cx}, ${cy})`, "data-element-id": item.id });
    const s = compact ? 0.58 : 1.0;
    const stroke = isFlagged ? "#ef4444" : item.uncertain ? "#f59e0b" : "#e2e8f0";
    const fill = isFlagged
      ? "rgba(239, 68, 68, 0.22)"
      : item.uncertain
      ? "rgba(245, 158, 11, 0.14)"
      : "#111c2e";
    const dash = item.uncertain ? "4 3" : null;
    const sw = isFlagged ? 2.8 : 2;

    if (isFlagged) {
      g.appendChild(
        el("circle", {
          cx: 0,
          cy: 0,
          r: 34 * s,
          fill: "rgba(239, 68, 68, 0.16)",
          stroke: "#ef4444",
          "stroke-width": 1.6,
          "stroke-dasharray": "4 3",
          class: "issue-halo",
        })
      );
    }

    const t = (item.type || "box").toLowerCase();

    if (t === "input" || t === "clock") {
      g.appendChild(
        el("polygon", {
          points: `${-26 * s},${-12 * s} ${14 * s},${-12 * s} ${26 * s},0 ${14 * s},${12 * s} ${-26 * s},${12 * s}`,
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
            x: -3 * s,
            y: 4 * s,
            "text-anchor": "middle",
            fill: "#f8fafc",
            "font-size": 11 * s,
            "font-weight": "700",
            "font-family": "ui-monospace, monospace",
          },
          item.label || (t === "clock" ? "CLK" : "IN")
        )
      );
    } else if (t === "output") {
      g.appendChild(
        el("polygon", {
          points: `${-24 * s},0 ${-12 * s},${-12 * s} ${26 * s},${-12 * s} ${26 * s},${12 * s} ${-12 * s},${12 * s}`,
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
            "font-size": 11 * s,
            "font-weight": "700",
            "font-family": "ui-monospace, monospace",
          },
          item.label || "OUT"
        )
      );
    } else if (t === "and" || t === "nand") {
      g.appendChild(
        el("path", {
          d: `M ${-22 * s} ${-18 * s} L ${0} ${-18 * s} A ${18 * s} ${18 * s} 0 0 1 ${0} ${18 * s} L ${-22 * s} ${18 * s} Z`,
          fill,
          stroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      if (t === "nand") {
        g.appendChild(el("circle", { cx: 22 * s, cy: 0, r: 4 * s, fill: "#070c15", stroke, "stroke-width": sw }));
      }
      addGateLabel(g, item.label || t.toUpperCase(), s, compact);
    } else if (t === "or" || t === "nor" || t === "xor" || t === "xnor") {
      g.appendChild(
        el("path", {
          d: `M ${-22 * s} ${-18 * s} Q ${-12 * s} 0 ${-22 * s} ${18 * s} L ${-4 * s} ${18 * s} Q ${14 * s} ${16 * s} ${22 * s} 0 Q ${14 * s} ${-16 * s} ${-4 * s} ${-18 * s} Z`,
          fill,
          stroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      if (t === "xor" || t === "xnor") {
        g.appendChild(
          el("path", {
            d: `M ${-28 * s} ${-17 * s} Q ${-18 * s} 0 ${-28 * s} ${17 * s}`,
            fill: "none",
            stroke,
            "stroke-width": sw,
          })
        );
      }
      if (t === "nor" || t === "xnor") {
        g.appendChild(el("circle", { cx: 26 * s, cy: 0, r: 4 * s, fill: "#070c15", stroke, "stroke-width": sw }));
      }
      addGateLabel(g, item.label || t.toUpperCase(), s, compact);
    } else if (t === "not") {
      g.appendChild(
        el("polygon", {
          points: `${-20 * s},${-16 * s} ${16 * s},0 ${-20 * s},${16 * s}`,
          fill,
          stroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      g.appendChild(el("circle", { cx: 20 * s, cy: 0, r: 4 * s, fill: "#070c15", stroke, "stroke-width": sw }));
      addGateLabel(g, item.label || "NOT", s, compact);
    } else if (t === "dff") {
      g.appendChild(
        el("rect", {
          x: -22 * s,
          y: -22 * s,
          width: 44 * s,
          height: 44 * s,
          rx: 4,
          fill,
          stroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      // Clock triangle
      g.appendChild(
        el("polyline", {
          points: `${-22 * s},${10 * s} ${-14 * s},${14 * s} ${-22 * s},${18 * s}`,
          fill: "none",
          stroke,
          "stroke-width": 1.6,
        })
      );
      g.appendChild(
        el("text", { x: 0, y: 3 * s, "text-anchor": "middle", fill: "#f8fafc", "font-size": 11 * s, "font-weight": "700", "font-family": "ui-monospace, monospace" }, item.label || "DFF")
      );
    } else if (t === "mux") {
      g.appendChild(
        el("polygon", {
          points: `${-20 * s},${-22 * s} ${20 * s},${-12 * s} ${20 * s},${12 * s} ${-20 * s},${22 * s}`,
          fill,
          stroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      g.appendChild(
        el("text", { x: 0, y: 4 * s, "text-anchor": "middle", fill: "#f8fafc", "font-size": 10 * s, "font-weight": "700", "font-family": "ui-monospace, monospace" }, item.label || "MUX")
      );
    } else if (t === "module_instance") {
      const modStroke = isFlagged ? "#ef4444" : item.uncertain ? "#f59e0b" : "#a855f7";
      g.appendChild(
        el("rect", {
          x: -36 * s,
          y: -22 * s,
          width: 72 * s,
          height: 44 * s,
          rx: 6,
          fill: "rgba(168, 85, 247, 0.16)",
          stroke: modStroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      g.appendChild(
        el("text", { x: 0, y: -3 * s, "text-anchor": "middle", fill: "#e9d5ff", "font-size": 11 * s, "font-weight": "800", "font-family": "ui-monospace, monospace" }, item.module_name || item.label || "MOD")
      );
      if (!compact) {
        g.appendChild(
          el("text", { x: 0, y: 12 * s, "text-anchor": "middle", fill: "#c084fc", "font-size": 8.5, "font-family": "ui-monospace, monospace" }, "MODULE")
        );
      }
    } else {
      // Generic box / label
      g.appendChild(
        el("rect", {
          x: -28 * s,
          y: -16 * s,
          width: 56 * s,
          height: 32 * s,
          rx: 5,
          fill,
          stroke,
          "stroke-width": sw,
          "stroke-dasharray": dash,
        })
      );
      g.appendChild(
        el("text", { x: 0, y: 4 * s, "text-anchor": "middle", fill: "#f8fafc", "font-size": 10 * s, "font-weight": "700", "font-family": "ui-monospace, monospace" }, item.label || t.toUpperCase())
      );
    }

    if (item.uncertain && !compact) {
      g.appendChild(el("circle", { cx: 22, cy: -20, r: 8, fill: "#f59e0b" }));
      g.appendChild(
        el("text", { x: 22, y: -16, "text-anchor": "middle", fill: "#0b0f17", "font-size": 11, "font-weight": "900" }, "?")
      );
    }

    return g;
  }

  function addGateLabel(g, text, s, compact) {
    if (compact) return;
    g.appendChild(
      el(
        "text",
        {
          x: 0,
          y: 31 * s,
          "text-anchor": "middle",
          fill: "#cbd5e1",
          "font-size": 10.5,
          "font-weight": "600",
          "font-family": "ui-monospace, monospace",
        },
        text
      )
    );
  }

  return { render };
})();
