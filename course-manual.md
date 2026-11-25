![Open Health Stack Software Foundation](images/ohs-logo.png)

# Analytics on FHIR: the hands-on steps

You are in the Editor, and the lab is running. Steps 1 and 2 were in Heropa. These steps start with the data on the FHIR server and run to the end. This guide shows one step at a time. Click **Next** when you are ready.

### Find your way round

The Editor has these areas.

| Area | Where | What it is for |
|---|---|---|
| Terminal | Top left | For typing commands. Open another with Ctrl and the backtick key. |
| Pipeline log | Bottom left | What the data load, the pipeline and the dashboard build report |
| Guide | Right | This guide. It shows one step at a time. Use **Back** and **Next**, or the list at the top. |
| Explorer | Far left | The files |

The files you will meet.

| Path | What it holds |
|---|---|
| `pipeline/config/views/` | The ViewDefinitions. One JSON file for each FHIR resource type. The pipeline reads these. |
| `pipeline/views-extra/` | Three more ViewDefinitions that are not switched on |
| `dashboard/src/data/` | The data loaders. Each one is a SQL query that prints a CSV. |
| `dashboard/src/index.md` and `immunization.md` | The two dashboard pages |
| `dashboard/src/components/charts.js` | Chart helpers shared by the pages |
| `data/generate.py` | The synthetic data generator |

Come back to the lab after a break, or when a tab stops loading: start the VM in Heropa if it is stopped, reload the tabs, and if they do not load run `./lab-init.sh` again in `~/analytics-codelab`. It is safe at any time and your changes are kept. `./lab-init.sh --info` prints the addresses and the password without changing anything.

## 3. Look at the data on the FHIR server

A FHIR server stores each record as a resource: a nested JSON document with a type, such as Patient or Encounter. Applications read it with the FHIR search API, which is just web addresses. The lab opens the server to reading from your browser. Everything here is read only.

The addresses below all start with the address of your lab. The quickest way to use them is to click **FHIR server** at the bottom of the Editor, and then change the end of the address in the browser bar.

1. **Count the patients.** The first tab you opened already shows it. The `total` is the number of Patient resources.

   ```
   /fhir/Patient?_summary=count
   ```

2. **See the first three patients.** `_count` sets how many resources come back.

   ```
   /fhir/Patient?_count=3
   ```

   Each entry is one Patient. Find `gender`, `birthDate` and `name`. Note the `id` of the first one.

3. **Open one patient.** Put the id you noted at the end.

   ```
   /fhir/Patient/<the id>
   ```

4. **Search.** Everything after the question mark is a search parameter. Try these one at a time, each as its own address.

   Count only the female patients.

   ```
   /fhir/Patient?gender=female&_summary=count
   ```

   List five patients born in 2022 or later.

   ```
   /fhir/Patient?birthdate=ge2022-01-01&_count=5
   ```

   Look at two encounters, which are visits.

   ```
   /fhir/Encounter?_count=2
   ```

   Count the vaccine doses.

   ```
   /fhir/Immunization?_summary=count
   ```

5. **Find the Sengmany family.** Somsak is a newborn in the SMART Trust demonstrator. This search returns him together with the vaccine doses that point at him.

   ```
   /fhir/Patient?name=Somsak&_revinclude=Immunization:patient
   ```

6. **Count from the terminal.** Switch to the Editor and open the Terminal. The lab sets `FHIR_URL` for you.

   ```
   curl -s "$FHIR_URL/Patient?_summary=count" | jq .total
   ```

   Then the encounters.

   ```
   curl -s "$FHIR_URL/Encounter?_summary=count" | jq .total
   ```

This is the shape of data a FHIR server holds: deeply nested, one resource at a time. It is good for an app that shows one patient. It is hard to count with. That is what the next step is for.

### The dashboard is empty so far

Click **Dashboard** at the bottom of the Editor. The page says there is no data in the analytics database yet. The data is on the FHIR server, but nothing has moved it into the flat tables the dashboard reads. In the Terminal, compare the two.

```
pipeline-status
```

The FHIR server column has numbers and the flat table column says `none`. Keep the Dashboard tab open. You will watch it fill.

## 4. What the pipeline does

FHIR Data Pipes is a set of pipelines that turn nested FHIR resources into flat tables, so that ordinary SQL and dashboard tools can use them. It has three parts you will meet.

*   **The pipeline** reads the resources from the FHIR server and writes the tables.
*   **The controller** starts the pipeline, either on a schedule or when you press a button, and keeps a list of the runs. The Pipelines tab is the controller.
*   **ViewDefinitions** say which fields become which columns. They are FHIR resources too, written to the SQL on FHIR standard, so you change what a table holds by editing a JSON file and not by writing code.

![A nested Patient resource with two names becomes two rows of a flat table](images/viewdefinition.svg)

### Look at a ViewDefinition

Open `pipeline/config/views/patient_flat_view.json` in the Editor.

*   `"resource": "Patient"` says which resource type the view reads.
*   `"name": "patient_flat"` is the name of the table the pipeline makes.
*   Each entry in a `column` list is a table column. The `path` is a FHIRPath expression into the resource, and the `name` is the column.
*   A `forEachOrNull` makes one row for each item in a list, here each name. A patient with two names gets two rows, which is why the dashboard counts distinct ids.

The lab has one view for each of 13 resource types. They are listed in `pipeline/config/application.yaml`.

### Run the pipeline from the Pipelines tab

1. Click **Pipelines** at the bottom of the Editor.
2. Click **Run Full**. A full run reads all the resources and builds the tables from scratch. **Run Incremental** reads only what changed since the last run, which you will use later.
3. The run takes a few minutes. Follow it in the Pipelines tab, where the latest result appears under the list of snapshots, and in the Terminal.

   ```
   pipeline-status
   ```

   Run it again every half minute. The flat table column fills in, one resource type after another, until it matches the FHIR server column.

### Or run it from the terminal

The Terminal can start the same run and follow it for you.

```
run-pipeline
```

### Look at the tables

List the tables.

```
psql -c "\dt"
```

The connection settings are already in your terminal. Notice the `\dt` with a backslash. Then count the patients by gender.

```
psql -c "SELECT gender, count(DISTINCT id) FROM patient_flat GROUP BY gender"
```

## 5. Watch the dashboard fill

Switch to the Dashboard tab. You do not have to do anything. About 30 seconds after the flat tables change, the lab rebuilds the dashboard, and the tab reloads by itself. The page now shows patients, households, visits and vaccine doses, three charts, and a bar chart of the rows in each flat table. The Immunization page shows the vaccine doses.

If you do not want to wait, click **Refresh dashboard** at the bottom of the Editor, or type `refresh` in the Terminal.

### How the dashboard reads the tables

Observable Framework builds a static site. Each file in `dashboard/src/data` that ends in `.csv.sh` is a data loader. When the site is built, the loader runs a SQL query and prints a CSV, and the page reads it with `FileAttachment`.

1. Open `dashboard/src/data/gender_age.csv.sh`. It is a SQL query over `patient_flat` that groups patients by gender and age group.
2. Open `dashboard/src/index.md`. The first block loads each CSV. The lines below it draw them with the helpers in `components/charts.js`.

### Change a query

1. In `gender_age.csv.sh`, make three small changes so that the second group becomes ages 5 to 17 and the third starts at 18.
   *   `< 15` becomes `< 18`
   *   `'5-14'` becomes `'5-17'`
   *   `'15-24'` becomes `'18-24'`
2. Open `dashboard/src/index.md` and change `"5-14", "15-24"` in the `order` list to `"5-17", "18-24"`.
3. Save both files. The Pipeline log shows the build and then `BUILD OK`.
4. Switch to the Dashboard tab. It reloads, and the chart uses the new groups.

Saving a file in `dashboard/src` rebuilds the dashboard at once. A change in the database does not, because the dashboard only reads the tables when it is built. The lab watches the tables for you and rebuilds when they change.

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

3. Save the file. Nothing changes yet, because the pipeline has not run again.
4. Run a full pipeline from the Pipelines tab, or type `run-pipeline` in the Terminal.
5. Watch the Dashboard tab. The patient number drops and the gender chart has one gender. The Patient bar in the rows chart gets shorter.
6. Put it back. First restore the shipped views.

   ```
   reset-views
   ```

7. Then run the pipeline again.

   ```
   run-pipeline
   ```

If the pipeline fails after your change, read the Pipeline log and the Pipelines tab. The most common cause is a missing comma or a bracket in the JSON. `reset-views` puts every view back as the lab shipped it.

## 7. Add data and run the pipeline again

1. Add about 50 more patients to the FHIR server.

   ```
   generate-data --patients 50 --seed 7 --no-demo-family
   ```

2. Open the FHIR server tab and reload the count. It has grown. Then compare the two sides in the Terminal.

   ```
   pipeline-status
   ```

   The FHIR server now holds more patients than the flat tables. The pipeline has not seen them yet.

3. Run only what changed. Click **Run Incremental** in the Pipelines tab, or type this.

   ```
   run-pipeline --incremental
   ```

4. Watch the Dashboard tab. The numbers grow after about 30 seconds.

You can also add one resource by hand, with the same request a real app makes.

```
curl -X POST "$FHIR_URL/Patient" -H "Content-Type: application/fhir+json" \
  -d '{"resourceType":"Patient","gender":"female","birthDate":"2024-03-02","name":[{"family":"TEST","given":["Lab"]}]}'
```

The patient has none of the location tags the other patients carry, so the tables count it but the village based queries do not.

## 8. Congratulations!

You looked at FHIR data on a server, ran it through a pipeline into flat tables, watched a dashboard fill, changed a ViewDefinition and a query, and brought new data through.

### Next steps

*   Switch on the three views in `pipeline/views-extra`. Copy one into `pipeline/config/views`, add its resource type to `resourceList` in `pipeline/config/application.yaml`, and restart the controller with `docker restart an-pipeline` from the VM terminal.
*   Write a new loader for another table, such as `observation_flat`, and a chart for it on a new page.
*   Read the indicator queries in `data/indicators.sql`. They show how the OHS Player reference dashboards join the flat tables.

## Troubleshooting

| What you see | What to do |
|---|---|
| The Dashboard says there is no data yet | The pipeline has not run. Click **Run Full** in the Pipelines tab, or type `run-pipeline`. |
| The FHIR server tab shows a count of 0 | The data is still loading. Wait a minute and watch the Pipeline log. |
| The Dashboard did not change after the pipeline finished | Wait 30 seconds, or click **Refresh dashboard**. The Pipeline log says which data the last build used. |
| `refresh` says the build failed | Read the lines above `BUILD FAILED` in the Pipeline log. A loader's SQL error is printed there. |
| The pipeline run stays on running | A full run takes a few minutes. Follow it in the Pipelines tab. |
| `pipeline-status` shows `none` in the flat table column | The pipeline has not run, or the view for that resource failed. Check the Pipelines tab. |
| The Pipelines tab does not load | Your network may block port 8443. Try another network, or ask your instructor. |
| The tabs stopped loading | Run `./lab-init.sh` again in `~/analytics-codelab`. |
