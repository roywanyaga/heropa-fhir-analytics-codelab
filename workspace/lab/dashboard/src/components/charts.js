// Chart helpers, so the pages stay short and every chart looks the same.
// The colours are the first six slots of one validated categorical palette,
// always used in this order. The pale ones (aqua, yellow, pink) fall below 3:1
// contrast on the white card, so every chart with more than one series has a
// legend, bars carry hover tips, and the data is also shown as a table.
import * as Plot from "npm:@observablehq/plot";

export const PALETTE = ["#625cab", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300"];
const INK = "#4c5456";

const base = {
  style: {fontFamily: "inherit", fontSize: "12px", color: INK, background: "transparent"},
  marginTop: 14, marginRight: 14, marginBottom: 34, marginLeft: 46,
  height: 280
};

// A colour for each name, kept the same for the same name wherever it appears.
export function colours(names) {
  return {domain: names, range: names.map((_, i) => PALETTE[i % PALETTE.length])};
}

export function bigNumber(label, value, accent) {
  const el = document.createElement("div");
  el.className = "kpi";
  if (accent) el.style.setProperty("--accent", accent);
  el.innerHTML = `<p class="label">${label}</p><span class="big">${Number(value).toLocaleString()}</span>`;
  return el;
}

// A card with a heading, a one line hint and a chart or table inside.
export function card(title, hint, body) {
  const el = document.createElement("div");
  el.className = "card";
  el.innerHTML = `<h2>${title}</h2><p class="hint">${hint ?? ""}</p>`;
  el.append(body);
  return el;
}

export function monthLine(rows, {x = "month", y, width} = {}) {
  return Plot.plot({
    ...base, width,
    x: {label: null, tickRotate: -45},
    y: {label: null, grid: true, nice: true},
    marks: [
      Plot.areaY(rows, {x, y, fill: PALETTE[0], fillOpacity: 0.12}),
      Plot.lineY(rows, {x, y, stroke: PALETTE[0], strokeWidth: 2, curve: "monotone-x"}),
      Plot.dot(rows, {x, y, fill: PALETTE[0], stroke: "#fff", strokeWidth: 2, r: 4}),
      Plot.tip(rows, Plot.pointerX({x, y})),
      Plot.ruleY([0])
    ]
  });
}

// Bars for each month, stacked by a category.
export function stackedMonths(rows, {x = "month", y, z, width} = {}) {
  const names = [...new Set(rows.map((d) => d[z]))];
  return Plot.plot({
    ...base, width,
    x: {label: null, tickRotate: -45},
    y: {label: null, grid: true, nice: true},
    color: {...colours(names), legend: true},
    marks: [
      Plot.barY(rows, {x, y, fill: z, rx: 3, insetLeft: 1, insetRight: 1, stroke: "#fff", strokeWidth: 1.5,
        tip: {format: {fill: true, x: true}}}),
      Plot.ruleY([0])
    ]
  });
}

// Bars side by side for each group, one bar per category.
export function groupedBars(rows, {x, y, fill, order, width} = {}) {
  const names = [...new Set(rows.map((d) => d[fill]))];
  return Plot.plot({
    ...base, width,
    marginLeft: 46,
    fx: {label: null, padding: 0.2, domain: order},
    x: {axis: null},
    y: {label: null, grid: true, nice: true},
    color: {...colours(names), legend: true},
    marks: [
      Plot.barY(rows, {fx: x, x: fill, y, fill, rx: 3, tip: {format: {fill: true, fx: true}}}),
      Plot.ruleY([0])
    ]
  });
}

// One bar for each name, longest first, with the number at the end of the bar.
export function rankedBars(rows, {label, value, width, colour = PALETTE[0]} = {}) {
  const sorted = [...rows].sort((a, b) => b[value] - a[value]);
  return Plot.plot({
    ...base, width, height: Math.max(120, 36 * sorted.length + 40),
    marginLeft: 100, marginRight: 50,
    x: {label: null, grid: true, nice: true},
    y: {label: null, domain: sorted.map((d) => d[label]), padding: 0.35},
    marks: [
      Plot.barX(sorted, {y: label, x: value, fill: colour, rx: 3, tip: true}),
      Plot.text(sorted, {y: label, x: value, text: (d) => Number(d[value]).toLocaleString(), dx: 6, textAnchor: "start", fill: "#0b0b0b"}),
      Plot.ruleX([0])
    ]
  });
}
