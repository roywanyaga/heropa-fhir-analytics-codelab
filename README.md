# FHIR analytics codelab on Heropa

This repository runs an analytics codelab on a headless Heropa VM. Learners need only a browser. They follow the steps in Heropa (`heropa-intro.md`) and then `course-manual.md`, which the Editor shows one step at a time. This guide is for the Heropa administrator who builds and maintains the course.

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

## Runbook: build the course in Heropa

Do these in order. Each command is on its own, so run them one at a time. The names are the ones used for the first course; change them if you like, but keep them consistent.

### 1. Create the build template and environment

Set the network on a template first, as the data capture codelab does. When it was set on the environment instead, the saved template showed no public IP, and the console of every course copy dropped as Heropa assigned one at launch.

1. In Heropa open **Templates** and click **Add**. Name it `FHIR Analytics build`, pick the region, and click **Create**.
2. On its **Resources** tab click **Add Resource** and add the Ubuntu 24.04 VM image.
3. Edit the VM.
   * Instance type: `t3.large` (2 vCPU, 8 GB memory, 10 VLU an hour). This is what the first course used and it ran the lab.
   * Storage: 20 GB. This is the most the account allowed. A bigger disk is better if you can have it, because the images take about 7 GB, the workspace build needs the same again while it runs, and the data grows. **The size cannot be changed once the final template is saved.**
   * Connection type: SSH. Username `ubuntu`.
4. Open the row action menu of the VM and choose **Edit network**. Tick **Allocate a permanent public IP address**. Add inbound TCP rules for 80, 443 and 8443 from `0.0.0.0/0`. Port 80 is for the Let's Encrypt check. Leave outbound traffic allowed.
5. Launch an environment from this template, name it `FHIR Analytics Draft`, and open its terminal.

### 2. Put the lab on the VM

Clone the repository.

```bash
git clone https://github.com/roywanyaga/heropa-fhir-analytics-codelab ~/analytics-codelab
```

Go into it.

```bash
cd ~/analytics-codelab
```

Provision the VM. This installs Docker, adds a 2 GB swap file that survives a reboot, pulls the images and builds the workspace image. It takes several minutes.

```bash
sudo ./provision-heropa.sh
```

Pick up the new `docker` group in this shell.

```bash
newgrp docker
```

Start the lab.

```bash
./lab-init.sh
```

The swap file is 2 GB on purpose. An 8 GB file filled the 19 GB disk of the first test VM and the workspace build failed with `no space left on device`. Check swap and disk after provisioning.

```bash
swapon --show
```

```bash
df -h /
```

`/etc/fstab` should hold the line `/swapfile none swap sw 0 0`.

```bash
grep swapfile /etc/fstab
```

### 3. Check the lab

1. Wait for the Pipeline log in the Editor to say `The lab is ready. The FHIR server holds the data.` The data load adds about 300 patients and builds the dashboard empty. It does not run the pipeline, because the learner does.
2. Open the four addresses that `lab-init.sh` printed: Editor, FHIR server, Pipelines, Dashboard.
3. The Editor should open with a Terminal at the top left, the Pipeline log under it, and the guide at the right showing one step at a time. No file should be open.
4. Walk the guide from step 3 to the end, including **Run Full** in the Pipelines tab. The Dashboard should fill about 30 seconds after the flat tables settle.

### 4. Put the lab back in its starting state

Remove the data volumes and load fresh data with an empty dashboard.

```bash
./lab-init.sh --reset
```

Wait for the Pipeline log to say `The lab is ready` again. Then stop the containers and keep the data volumes.

```bash
./lab-init.sh --clean
```

The template then holds the FHIR data and empty flat tables. Stop the environment in Heropa if Heropa asks for it.

### 5. Save the template

1. In the environment, open **Action** and choose **Save as template**. Name it `FHIR Analytics`. When it is Available, open it and check its VM shows a public IP and not N/A. Add a version to the name when you make another one, such as `FHIR Analytics v2`.
2. Wait until the template is **Available**. It takes about 30 minutes. Heropa clones the VM, its disk and its configuration (instance type, storage, network, connection type, credentials and user data). It does not copy the running state.
3. Do not launch the environment that was saved. A copy of it, also named `FHIR Analytics`, may exist after the template is made. It is not used by the course and can be deleted.
4. Stop the `FHIR Analytics Draft` environment so it stops using VLUs.

### 6. Create the content and the course

1. Under **Content**, add a Lab Guide named `Analytics on FHIR`. Paste each file of `heropa-html/sections/` as one section, in order. The sections `01` and `02` are the Heropa steps. `03` onward repeat the steps the learner follows in the Editor.
2. Under **Courses**, add a course.
   * Template: `FHIR Analytics`
   * Policy: `OHS Player`
   * Content: `Analytics on FHIR`
   * Disk: 20 GB
3. Keep the course in Draft until the preview works (next section), then publish it.

Regenerate the HTML after any change to `heropa-intro.md` or `course-manual.md`.

```bash
python3 tools/manual-to-html.py
```

### 7. Test as a learner

1. Open the course from **Courses** and launch it. Heropa makes a fresh environment from the template. It is named after the course.
2. Open its terminal. The first start from a template gets a new public address, so the certificate must be made again.

```bash
cd ~/analytics-codelab
```

```bash
./lab-init.sh
```

3. Open the Editor, the FHIR server, Pipelines and Dashboard, and check each loads.
4. Click **Run Full**, and check the Dashboard fills.
5. Stop the environment, start it again, and check the lab and the data are still there. This is the Day 1 to Day 2 case.

### 8. Publish, then add it to an event

1. Publish the course when the test passes.
2. For a workshop, create an event, add the published courses to it, and enrol the delegates.

### Cost and sizing

* Each running lab costs 10 VLU an hour. The policy suspends an idle VM after 30 minutes and destroys the environment after 35 days.
* 30 delegates for six hours is about 1,800 VLU. Check the monthly allowance first.
* Concurrent VLUs are capped by the tenancy, so 30 labs of 10 VLU need 300 at once.

### Updating the course after a change

Templates do not update in place. Pull the change on the build VM, rebuild, test, then repeat steps 4 and 5 under a new template name, and point the course at it.

```bash
cd ~/analytics-codelab
```

```bash
git pull
```

```bash
docker build -t analytics-codelab-workspace:local workspace
```

```bash
./lab-init.sh --reset
```

### Troubleshooting the build

| What you see | What to do |
|---|---|
| `no space left on device` during the workspace build | Check `df -h /` and `swapon --show`. Keep swap at 2 GB. |
| The course environment says `Disconnected from VM` at once | Its VM was stopped a minute after it started. See the note below. |
| The addresses do not load after a restart | Run `./lab-init.sh` again. It is safe at any time. `./lab-init.sh --info` prints the addresses and password. |
| The Dashboard says the build failed | Read the Pipeline log above `BUILD FAILED`. |

On the first course test the environment made from the course launched with `Success` but its VM showed `Stopped` and the workspace said `Disconnected from VM`, while the build environment started normally. The cause was not found. Try starting the environment from **Environments** instead of the course and give it a few minutes to boot. If it still fails, save a new template from the build VM and, if that fails too, send Heropa support the environment ID and the times.

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
*   `heropa-html/` is made by `python3 tools/manual-to-html.py` from `heropa-intro.md` and `course-manual.md`. Run it after either changes.
*   The stepped guide (`preview/steps.js`, taken from the data capture codelab) and the new layout (Terminal top left, Pipeline log below, no file open at start) were written without a running editor and must be looked at.
*   Launching a learner environment from the template. The first try showed `Disconnected from VM` with the VM stopped.
