// Small chart helpers, so the pages stay short and every chart looks the same.
// Colours are one validated set, used in the same order everywhere.
import * as Plot from "npm:@observablehq/plot";

export const PALETTE = ["#4269d0", "#efb118", "#3ca951", "#ff725c", "#6cc5b0", "#a463f2"];

export function bigNumber(label, value) {
  const el = document.createElement("div");
  el.className = "card kpi";
  el.innerHTML = `<h2>${label}</h2><span class="big">${Number(value).toLocaleString()}</span>`;
  return el;
}

export function monthLine(rows, {x = "month", y, title, width} = {}) {
  return Plot.plot({
    title, width, marginLeft: 50,
    x: {label: null, tickRotate: -45},
    y: {label: null, grid: true},
    marks: [Plot.lineY(rows, {x, y, stroke: PALETTE[0], strokeWidth: 2}), Plot.dot(rows, {x, y, fill: PALETTE[0]})]
  });
}

export function stackedMonths(rows, {x = "month", y, z, title, width} = {}) {
  return Plot.plot({
    title, width, marginLeft: 50,
    x: {label: null, tickRotate: -45},
    y: {label: null, grid: true},
    color: {range: PALETTE, legend: true},
    marks: [Plot.barY(rows, {x, y, fill: z, tip: true})]
  });
}

export function groupedBars(rows, {x, y, fill, title, width} = {}) {
  return Plot.plot({
    title, width, marginLeft: 50,
    x: {label: null},
    y: {label: null, grid: true},
    color: {range: PALETTE, legend: true},
    marks: [Plot.barY(rows, {x, y, fill, tip: true})]
  });
}
