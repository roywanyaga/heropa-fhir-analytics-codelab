---
title: Overview
---

# Overview

```js
import {bigNumber, groupedBars, monthLine, stackedMonths} from "./components/charts.js";

const kpis = await FileAttachment("data/kpis.csv").csv({typed: true});
const genderAge = await FileAttachment("data/gender_age.csv").csv({typed: true});
const visits = await FileAttachment("data/visits_month.csv").csv({typed: true});
const enrolments = await FileAttachment("data/enrolments_month.csv").csv({typed: true});
```

<div class="kpis">${kpis.map((k) => bigNumber(k.metric, k.value))}</div>

<div class="grid grid-cols-2">
  <div class="card">${resize((width) => groupedBars(genderAge, {x: "age_group", y: "patients", fill: "gender", title: "Patients by age group and gender", width}))}</div>
  <div class="card">${resize((width) => monthLine(visits, {y: "visits", title: "Visits per month", width}))}</div>
</div>

<div class="card">${resize((width) => stackedMonths(enrolments, {y: "enrolments", z: "programme", title: "Programme enrolments per month", width}))}</div>

<p class="note">Each number is read from the flat tables that FHIR Data Pipes writes to the analytics database. The queries are in <code>src/data</code>. Change a ViewDefinition, run the pipeline and run <code>refresh</code> to see the numbers move.</p>
