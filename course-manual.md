# Analytics on FHIR with FHIR Data Pipes and Observable Framework

This guide takes you through the analytics codelab on the Heropa lab. You change FHIR data and ViewDefinitions in an editor in your browser, run the FHIR Data Pipes pipeline, and watch a dashboard built with Observable Framework change. You install nothing.

It follows the same path as the published [SQL on FHIR analytics tutorial](https://ohs-foundation.github.io/ohs-docs/tutorials-and-codelabs/sql-on-fhir-analytics/), with the dashboard written in Observable Framework in place of Superset. This guide covers the lab only.

The synthetic data is made by a generator taken from the OHS Player analytics repository. It also contains the Sengmany family from the [SMART Trust demonstrator](https://github.com/litlfred/smart-trust-demo), a fictional family whose child has vaccine doses recorded in two countries.

## 1. Before you begin

### What you'll build

You will follow FHIR data from a FHIR server, through a pipeline, into flat database tables, and onto a dashboard. Along the way you change a ViewDefinition and a data query, add more data, and see each change reach the dashboard.

```
FHIR server (HAPI) --> FHIR Data Pipes --> flat tables (Postgres) --> dashboard (Observable Framework)
                        ViewDefinitions                              SQL data loaders
```

### What you'll learn

*   What a ViewDefinition is and how it turns a FHIR resource into a table
*   How to run the pipeline from the Controller UI and from the terminal
*   How an Observable Framework dashboard reads those tables with data loaders
*   How to change a ViewDefinition and see the effect on the dashboard
*   How to add data to the FHIR server and bring it through the pipeline

### What you'll need

A recent version of Chrome, Edge, Firefox or Safari, and a keyboard. You do not need to know JavaScript. Each change is given in full, with the file to open and where to put it. A little SQL helps.

## 2. Get set up

### Start your lab

1. Open the terminal of your lab VM in Heropa.
2. Start the lab.

   ```
   cd ~/analytics-codelab
   ./lab-init.sh
   ```

3. Wait about a minute. The command ends with a summary like the one below. The addresses and the password in the example are placeholders and do not work. Use the ones your own terminal prints.

   ```
   The lab is ready. Open these in the browser on your own computer.

     Editor            https://203-0-113-10.sslip.io/ide/
     Editor password   4827
     Dashboard         https://203-0-113-10.sslip.io/dashboard/
     Pipelines         https://203-0-113-10.sslip.io:8443/
     FHIR server       https://203-0-113-10.sslip.io/fhir/metadata
   ```

### Open the three tabs

You work in three browser tabs. Put them side by side if you have room.

| Tab | What it is for |
|---|---|
| Editor | The ViewDefinitions, the dashboard code, a terminal and this guide. Enter the editor password when it asks. |
| Dashboard | The dashboard. Click **Open dashboard** at the bottom of the Editor to open it. It reloads after each build. |
| Pipelines | The FHIR Data Pipes Controller. Click **Open pipelines** at the bottom of the Editor. |

The Editor has these areas.

| Area | Where | What it is for |
|---|---|---|
| Explorer | Far left | The files |
| Code | Top centre | The file you are changing |
| Pipeline log | Bottom centre | What the pipeline and the dashboard build report |
| Terminal | Bottom centre, next to the Pipeline log | For typing commands |
| Guide | Right | This guide |

The bar at the bottom has buttons for **Open dashboard**, **Open pipelines**, **Run pipeline**, **Refresh dashboard**, **Guide** and **Pipeline log**.

### Find your addresses again

Come back here after a break, or when a tab stops loading. Start the VM in Heropa if it is stopped, reload the tabs, and if they do not load run `./lab-init.sh` again in `~/analytics-codelab`. It is safe at any time and your changes are kept. `./lab-init.sh --info` prints the addresses and the password without changing anything.

### The files

| Path | What it holds |
|---|---|
| `pipeline/config/views/` | The ViewDefinitions. One JSON file for each FHIR resource type. The pipeline reads these. |
| `pipeline/views-extra/` | Three more ViewDefinitions that are not switched on |
| `dashboard/src/data/` | The data loaders. Each one is a SQL query that prints a CSV. |
| `dashboard/src/index.md` and `immunization.md` | The two dashboard pages |
| `dashboard/src/components/charts.js` | Chart helpers shared by the pages |
| `dashboard/sample/` | Sample data the dashboard uses until the pipeline has filled the tables |
| `data/generate.py` | The synthetic data generator |

## 3. Look at the data

The lab starts with synthetic data already loaded into the FHIR server and already run through the pipeline.

1. Open the Dashboard tab. You should see the number of patients, households, visits and vaccine doses, and three charts.
2. In the Editor terminal, compare the FHIR server with the flat tables.

   ```
   pipeline-status
   ```

   Both columns should show the same numbers. The flat table counts are of distinct ids, because a table row is repeated when a resource has several codings.

3. Look at one resource on the FHIR server. Open this address in a new tab, with your own name in place of the example.

   ```
   https://203-0-113-10.sslip.io/fhir/Patient/trustdemo-somsak
   ```

   This is Somsak SENGMANY, the newborn at the centre of the SMART Trust demonstrator. His household, his parents and his four vaccine doses are in the data too. Open `/fhir/Immunization?patient=trustdemo-somsak` to see them.

## 4. Run the pipeline

The pipeline reads every resource of the types it is set up for, applies each ViewDefinition, and writes a table for each one.

### Look at a ViewDefinition

Open `pipeline/config/views/patient_flat_view.json` in the Editor. Each entry in a `column` list is a table column. It has a FHIRPath `path` into the resource and a `name`. The first lines read the resource key, the gender and the birth date. A `forEachOrNull` makes a row for each name or each general practitioner, which is why a patient with two names appears twice in the table.

### Run it from the Pipelines tab

1. Open the Pipelines tab.
2. Click the button to run the full pipeline. Wait until the run is listed as finished.
3. In the Editor terminal run `pipeline-status`. The flat table column matches the FHIR server column.

### Run it from the terminal

```
run-pipeline
```

It starts a full run and follows it until the tables hold what the FHIR server holds. It does the same as the Pipelines tab.

### Look at the tables

```
psql -c "\dt"
psql -c "SELECT gender, count(DISTINCT id) FROM patient_flat GROUP BY gender"
```

The connection settings are already in your terminal.

## 5. How the dashboard reads the tables

Observable Framework builds a static site. Each file in `dashboard/src/data` that ends in `.csv.sh` is a data loader. When the site is built, the loader runs, and the page reads its output with `FileAttachment`.

1. Open `dashboard/src/data/gender_age.csv.sh`. It is a SQL query over `patient_flat` that groups patients by gender and age group.
2. Open `dashboard/src/index.md`. The first block loads each loader's CSV. The next lines draw them with the chart helpers.

### Change a query

1. In `gender_age.csv.sh`, change the age group boundary from `15` to `18` in the line that makes the `5-14` group, and rename the group `5-17`.
2. Save the file. The Pipeline log shows the build and then `BUILD OK`.
3. Switch to the Dashboard tab. It reloads, and the chart uses the new groups.

Saving a loader rebuilds the dashboard by itself. A change in the database does not, because the dashboard only reads the tables when it is built. That is why the next sections end with `refresh`.

## 6. Change a ViewDefinition

A ViewDefinition decides which resources become rows and which fields become columns. You will change the Patient view so that it keeps only female patients, and watch the dashboard follow.

1. Open `pipeline/config/views/patient_flat_view.json`.
2. Add a `where` list after the `"resource": "Patient"` line. The line before it ends in a comma, so keep the commas right.

   ```json
   "resource": "Patient",
   "where": [
     { "path": "gender = 'female'" }
   ],
   ```

3. Save the file. Nothing changes yet, because the pipeline has not run.
4. Run the pipeline and then rebuild the dashboard.

   ```
   run-pipeline
   refresh
   ```

5. Switch to the Dashboard tab. The patient number has dropped and the gender chart has only one gender.
6. Put it back.

   ```
   reset-views
   run-pipeline
   refresh
   ```

If the pipeline fails after your change, read the Pipeline log and the Pipelines tab. The most common cause is a missing comma or a bracket in the JSON. `reset-views` puts every view back as the lab shipped it.

## 7. Add data and run the pipeline again

1. Add about 50 more patients to the FHIR server.

   ```
   generate-data --patients 50 --seed 7 --no-demo-family
   ```

2. Compare the two sides.

   ```
   pipeline-status
   ```

   The FHIR server now holds more patients than the flat tables. The pipeline has not seen them yet.

3. Run only what changed.

   ```
   run-pipeline --incremental
   refresh
   ```

4. Look at the Dashboard tab. The numbers have grown.

You can also add one resource by hand, with the same request a real app makes.

```
curl -X POST "$FHIR_URL/Patient" -H "Content-Type: application/fhir+json" \
  -d '{"resourceType":"Patient","gender":"female","birthDate":"2024-03-02","name":[{"family":"TEST","given":["Lab"]}]}'
```

The patient has none of the location tags the other patients carry, so the tables count it but the village based queries do not.

## 8. Congratulations!

You followed FHIR data from a server to a dashboard, changed a ViewDefinition and a query, and brought new data through the pipeline.

### Next steps

*   Switch on the three views in `pipeline/views-extra`. Copy one into `pipeline/config/views`, add its resource type to `resourceList` in `pipeline/config/application.yaml`, and restart the controller with `docker restart an-pipeline` from the VM terminal.
*   Write a new loader for another table, such as `observation_flat`, and a chart for it on a new page.
*   Read the indicator queries in `data/indicators.sql`. They show how the OHS Player reference dashboards join the flat tables.

## Troubleshooting

| What you see | What to do |
|---|---|
| The Dashboard tab shows sample data | The pipeline has not filled the tables yet. Run `run-pipeline`, then `refresh`. The Pipeline log says which data the last build used. |
| `refresh` says the build failed | Read the lines above `BUILD FAILED` in the Pipeline log. A loader's SQL error is printed there. |
| The pipeline run stays on running | A full run on this lab takes a few minutes. Follow it in the Pipelines tab. |
| `pipeline-status` shows `none` in the flat table column | The pipeline has not run, or the view for that resource failed. Check the Pipelines tab. |
| The Pipelines tab does not load | Your network may block port 8443. Try another network, or ask your instructor. |
| The tabs stopped loading | Run `./lab-init.sh` again in `~/analytics-codelab`. |
