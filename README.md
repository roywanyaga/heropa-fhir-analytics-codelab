# FHIR analytics codelab on Heropa

This repository runs an analytics codelab on a headless Heropa VM. Learners need only a browser. They follow `course-manual.md`. This guide is for the Heropa administrator who builds and maintains the course.

It follows the layout of the other Heropa codelab repositories (`heropa-data-capture-codelab`, `heropa-fhir-engine-codelab`). `lab-init.sh`, `provision-heropa.sh`, the nginx front and the editor extension come from them. The workspace, the compose file, the data generator and the dashboard are new.

## What a learner gets

A learner follows data from a FHIR server, through FHIR Data Pipes, into Postgres, and onto a dashboard built with Observable Framework. They read the data on the FHIR server, run the pipeline themselves, watch the dashboard fill, change a ViewDefinition, change a dashboard query, add data, and see each change arrive. They use four browser tabs, in this order: Editor, FHIR server, Pipelines, Dashboard.

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

The dashboard is a static build, not the Observable preview server, so it works under a path and needs no websocket. Two watchers rebuild it. `codelab-watch` rebuilds when a file in `dashboard/src` is saved. `data-watch` polls the row counts of six flat tables every 15 seconds and rebuilds once they have stopped changing, so a learner sees the numbers move about 30 seconds after a pipeline run without a click. `refresh` does it at once.

Before the pipeline has run, the dashboard is built in an empty state (`LAB_SAMPLE=empty`, from `dashboard/sample/empty`), which shows zeros and a message that says to run the pipeline. `LAB_SAMPLE=1` builds from made up numbers in `dashboard/sample`, for working on the pages without a database.

### The lab commands (in `workspace/bin`)

| Command | What it does |
|---|---|
| `generate-data` | Loads synthetic data into the FHIR server. It adds, and never deletes. |
| `run-pipeline` | Starts a pipeline run and waits for the tables to catch up |
| `pipeline-status` | FHIR server counts beside flat table counts |
| `refresh` | Rebuilds the dashboard from the tables now |
| `reset-views` | Restores the shipped ViewDefinitions |
| `lab-seed` | Runs once at first start. Loads about 300 patients and builds the empty dashboard. It does not run the pipeline. |
| `data-watch` | Rebuilds the dashboard when the flat tables change |

### The data

`workspace/lab/data/generate.py` comes from `ohs-player-analytics/test-data/generate.py`. It adds `--villages`, `--seed` and a `--no-demo-family` switch. The Sengmany household of the SMART Trust demonstrator is written by hand into the generator from `people.fsh` and `j1` to `j3`, so SUSHI is not needed. The ids are fixed, so loading twice does not duplicate them.

The ViewDefinitions in `pipeline/config/views` are the ones from `ohs-player-analytics`. They cover more resource types than the ones shipped with fhir-data-pipes. Three of them (Procedure, MedicationRequest, DiagnosticReport) are in `pipeline/views-extra` because the generator makes no data for them.

## Setting up the template

1. Use an Ubuntu 24.04 VM with 4 vCPU, 16 GB memory and 40 GB storage. The first test ran on 2 vCPU, 7.6 GB and 19 GB, which is the smallest that works: the images take about 7 GB, the workspace build needs the same again while it runs, and the lab data grows. Disk size cannot be changed once the template is saved, so choose it now. In **Edit network**, allocate a permanent public IP and add inbound TCP 80, 443 and 8443 from `0.0.0.0/0`. Port 80 is for the Let's Encrypt check.
2. Put this repository on the VM and provision it.

   ```bash
   git clone https://github.com/roywanyaga/heropa-fhir-analytics-codelab ~/analytics-codelab
   cd ~/analytics-codelab
   sudo ./provision-heropa.sh
   newgrp docker
   ./lab-init.sh
   ```

   `provision-heropa.sh` installs Docker, adds a 2 GB swap file that survives a reboot (`/etc/fstab`), pulls the images and builds the workspace image. Do not make the swap file larger than 2 GB on a small disk. An 8 GB file filled the 19 GB disk of the first test VM and the image build failed with `no space left on device`. Check with `swapon --show` and `df -h /`.
3. Wait until the Pipeline log in the editor says `The lab is ready. The FHIR server holds the data.` `lab-seed` has then loaded the data and built the empty dashboard. It does not run the pipeline, because the learner does.
4. Walk the manual once, including the pipeline run. Then put the lab back in its starting state with `./lab-init.sh --reset`, which removes the data volumes and loads fresh data with an empty dashboard.
5. When the Pipeline log says `The lab is ready` again, run `./lab-init.sh --clean`, which keeps the data volumes, then save the environment as a template. The template ships with the FHIR data loaded and the flat tables empty.

## Not yet checked on a VM

Verified on a VM (2 vCPU, 7.6 GB, 19 GB disk): provisioning, the workspace image build, `lab-init.sh`, all five containers healthy, the Editor, the Controller UI on 8443, the data load, a full pipeline run into Postgres (flat tables matched the FHIR server), and the dashboard build. The rest of this list is still to check.

*   `run-pipeline` posts to `/run?runMode=FULL` on the controller. Check it, and `--incremental`, against the controller version, or copy the request from the Controller UI's network tab.
*   That an edited ViewDefinition takes effect on the next Run Full, and that a `where` line really drops the rows (manual section 6).
*   That the Sengmany family is on the server (`/fhir/Patient?name=Somsak&_revinclude=Immunization:patient`).
*   The new dashboard pages and charts, the empty state, and the `data-watch` rebuild. They were written without a build tool and must be looked at.
*   That the two diagrams show inside the Heropa course, where they are embedded as data addresses. If Heropa strips them, upload PNG copies and use those.
*   `generateParquetFiles` is still true in `pipeline/config/application.yaml`. Try it false.
*   The controller image is `:latest`. Pin it to a digest after the first good run.
*   `npm install` runs in the workspace image build. Commit the `package-lock.json` it makes and switch to `npm ci`.
*   Whether the Controller UI works under a path prefix. It gets port 8443 for now. A path under `/pipes/` would remove the extra inbound rule.
*   The table names. The dashboard loaders expect `patient_flat`, `group_flat`, `encounter_flat`, `condition_flat` and `immunization_flat` in the `analytics` database, as in `ohs-player-analytics`.
*   Memory. HAPI, the controller, Postgres and a build together need about 8 GB. The 16 GB VM leaves room for the editor sessions.
*   The ViewDefinitions use the long StructureDefinition URL as `resourceType`, as in the repository they came from. The pipeline ran with it there, so it is left alone.
*   `heropa-html/` is made by `python3 tools/manual-to-html.py`. Run it after the manual is final.
