---
title: Immunization
---

# Immunization

```js
import {stackedMonths} from "./components/charts.js";

const vaccines = await FileAttachment("data/vaccines.csv").csv({typed: true});
const totals = d3.rollups(vaccines, (v) => d3.sum(v, (d) => d.doses), (d) => d.vaccine)
  .map(([vaccine, doses]) => ({vaccine, doses}))
  .sort((a, b) => b.doses - a.doses);
```

<div class="card">${resize((width) => stackedMonths(vaccines, {y: "doses", z: "vaccine", title: "Vaccine doses per month", width}))}</div>

<div class="card">${Inputs.table(totals)}</div>

<p class="note">The Sengmany family from the SMART Trust demonstrator is in this data. Somsak's two birth doses were given in Taifafeki. His six week doses were given in Onesa.</p>
