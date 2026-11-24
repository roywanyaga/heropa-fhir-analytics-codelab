---
title: Immunization
---

```js
import {card, stackedMonths, rankedBars} from "./components/charts.js";

const vaccines = await FileAttachment("data/vaccines.csv").csv({typed: true});
const built = (await FileAttachment("data/built.csv").csv())[0].built;
const totals = d3.rollups(vaccines, (v) => d3.sum(v, (d) => d.doses), (d) => d.vaccine)
  .map(([vaccine, doses]) => ({vaccine, doses}))
  .sort((a, b) => b.doses - a.doses);
```

<div class="top">
  <div>
    <h1>Immunization</h1>
    <p class="sub">Vaccine doses recorded as Immunization resources</p>
  </div>
  <nav class="tabs"><a href="./">Overview</a><a class="on" href="./immunization">Immunization</a></nav>
</div>

<p class="fresh">Built ${built}</p>

${vaccines.length === 0 ? html`<div class="empty"><strong>No doses in the analytics database yet</strong><p>Run the pipeline and this page fills in.</p></div>` : ""}

<div class="grid grid-cols-2">
  ${card("Doses per month", "Stacked by vaccine", resize((width) => stackedMonths(vaccines, {y: "doses", z: "vaccine", width})))}
  ${card("Doses by vaccine", "All months together", resize((width) => rankedBars(totals, {label: "vaccine", value: "doses", width})))}
</div>

<div class="card"><h2>The same numbers as a table</h2><p class="hint">Sort by clicking a column</p>${Inputs.table(totals, {layout: "auto"})}</div>

<p class="note">The Sengmany family from the SMART Trust demonstrator is in this data. Somsak's two birth doses were given in Taifafeki, and his six week doses in Onesa.</p>
