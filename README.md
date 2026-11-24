# FHIR analytics codelab on Heropa

This repository runs an analytics codelab on a headless Heropa VM. Learners need only a browser. They follow `course-manual.md`. This guide is for the Heropa administrator who builds and maintains the course.

It follows the layout of the other Heropa codelab repositories (`heropa-data-capture-codelab`, `heropa-fhir-engine-codelab`). `lab-init.sh`, `provision-heropa.sh`, the nginx front and the editor extension come from them. The workspace, the compose file, the data generator and the dashboard are new.

## What a learner gets

A learner follows data from a FHIR server, through FHIR Data Pipes, into Postgres, and onto a dashboard built with Observable Framework. They run the pipeline, change a ViewDefinition, change a dashboard query, add data, and see each change arrive.

There is no Spark and no Parquet view layer. The pipeline flattens the ViewDefinitions straight into Postgres.

## How it works

| Container | What it does |
|---|---|
| `an-postgres` | One Postgres with two databases, `hapi_fhir` and `analytics` |
| `an-hapi` | The HAPI FHIR server the synthetic data is loaded into |
| `an-pipeline` | The FHIR Data Pipes controller, from the published image. It is not built here and the fhir-data-pipes source is not cloned. |
| `an-workspace` | code-server, Node with Observable Framework, the lab commands and the generator |
| `an-nginx` | The only published service. It terminates HTTPS. |

| Address | What it is |
|---|---|
| `/` | Start page |
| `/ide/` | The editor |
| `/dashboard/` | The dashboard, built after every save by a watcher |
| `/fhir/` | The FHIR server, read only |
| `:8443` | The Controller UI, on a port of its own, because its pages use links from the root |

The dashboard is a static build, not the Observable preview server, so it works under a path and needs no websocket. A watcher rebuilds it when a file in `dashboard/src` is saved. A change in the database does not trigger it. The learner runs `refresh`.

### The lab commands (in `workspace/bin`)

| Command | What it does |
|---|---|
| `generate-data` | Loads synthetic data into the FHIR server. It adds, and never deletes. |
| `run-pipeline` | Starts a pipeline run and waits for the tables to catch up |
| `pipeline-status` | FHIR server counts beside flat table counts |
| `refresh` | Rebuilds the dashboard from the tables |
| `reset-views` | Restores the shipped ViewDefinitions |
| `lab-seed` | Runs once at first start. Loads the data, runs the pipeline, builds the dashboard. |

### The data

`workspace/lab/data/generate.py` comes from `ohs-player-analytics/test-data/generate.py`. It adds `--villages`, `--seed` and a `--no-demo-family` switch. The Sengmany household of the SMART Trust demonstrator is written by hand into the generator from `people.fsh` and `j1` to `j3`, so SUSHI is not needed. The ids are fixed, so loading twice does not duplicate them.

The ViewDefinitions in `pipeline/config/views` are the ones from `ohs-player-analytics`. They cover more resource types than the ones shipped with fhir-data-pipes. Three of them (Procedure, MedicationRequest, DiagnosticReport) are in `pipeline/views-extra` because the generator makes no data for them.

## Setting up the template

1. Use an Ubuntu 24.04 VM with 4 vCPU, 16 GB memory and 40 GB storage. In **Edit network**, allocate a permanent public IP and add inbound TCP 80, 443 and 8443 from `0.0.0.0/0`. Port 80 is for the Let's Encrypt check.
2. Put this repository on the VM and provision it.

   ```bash
   git clone https://github.com/roywanyaga/heropa-fhir-analytics-codelab ~/analytics-codelab
   cd ~/analytics-codelab
   sudo ./provision-heropa.sh
   newgrp docker
   ./lab-init.sh
   ```

3. Wait until the Pipeline log in the editor says `The lab is ready`. `lab-seed` has then loaded the data, run the pipeline and built the dashboard.
4. Walk the manual once.
5. Run `./lab-init.sh --clean`, which keeps the data volumes, then save the environment as a template. The template ships with the data loaded.

## Not yet checked on a VM

Nothing here has been run. These are the things to check first.

*   `run-pipeline` posts to `/run?runMode=FULL` on the controller. Check it against the controller version, or copy the request from the Controller UI's network tab.
*   `generateParquetFiles` is still true in `pipeline/config/application.yaml`. Try it false.
*   The controller image is `:latest`. Pin it to a digest after the first good run.
*   `npm install` runs in the workspace image build. Commit the `package-lock.json` it makes and switch to `npm ci`.
*   Whether the Controller UI works under a path prefix. It gets port 8443 for now. A path under `/pipes/` would remove the extra inbound rule.
*   The table names. The dashboard loaders expect `patient_flat`, `group_flat`, `encounter_flat`, `condition_flat` and `immunization_flat` in the `analytics` database, as in `ohs-player-analytics`.
*   Memory. HAPI, the controller, Postgres and a build together need about 8 GB. The 16 GB VM leaves room for the editor sessions.
*   The ViewDefinitions use the long StructureDefinition URL as `resourceType`, as in the repository they came from. The pipeline ran with it there, so it is left alone.
*   `heropa-html/` is made by `python3 tools/manual-to-html.py`. Run it after the manual is final.
