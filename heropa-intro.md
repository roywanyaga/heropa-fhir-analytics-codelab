![Open Health Stack Software Foundation](images/ohs-logo.png)

# Analytics on FHIR with FHIR Data Pipes and Observable Framework

This guide takes you through the analytics codelab on the Heropa lab. You look at FHIR data on a FHIR server, run the FHIR Data Pipes pipeline, and watch a dashboard built with Observable Framework fill with numbers. Then you change a ViewDefinition and add more data, and watch the dashboard follow. You install nothing.

It follows the same path as the published [SQL on FHIR analytics tutorial](https://ohs-foundation.github.io/ohs-docs/tutorials-and-codelabs/sql-on-fhir-analytics/), with the dashboard written in Observable Framework in place of Superset. This guide covers the lab only.

The synthetic data is made by a generator taken from the OHS Player analytics repository. It also contains the Sengmany family from the [SMART Trust demonstrator](https://github.com/litlfred/smart-trust-demo), a fictional family whose child has vaccine doses recorded in two countries.

## 1. Before you begin

### What you'll build

You will follow FHIR data from a FHIR server, through a pipeline, into flat database tables, and onto a dashboard. You work in four browser tabs, and they are used in this order: the Editor, the FHIR server, the Pipelines tab and the Dashboard.

![The data flows from the FHIR server through FHIR Data Pipes into flat tables and on to the dashboard](images/pipeline-flow.svg)

### What you'll learn

*   How to read data from a FHIR server with plain addresses and the FHIR search API
*   What FHIR Data Pipes does, and what a ViewDefinition is
*   How to run the pipeline from the Controller UI and from the terminal
*   How an Observable Framework dashboard reads the flat tables with data loaders
*   How to change a ViewDefinition and a query and see the dashboard change
*   How to add data to the FHIR server and bring it through the pipeline

### What you'll need

A recent version of Chrome, Edge, Firefox or Safari, and a keyboard. You do not need to know JavaScript. Each change is given in full, with the file to open and where to put it. A little SQL helps.

## 2. Get set up

### Start your lab

1. Open the terminal of your lab VM in Heropa.
2. Go to the lab folder.

   ```
   cd ~/analytics-codelab
   ```

3. Start the lab.

   ```
   ./lab-init.sh
   ```

4. Wait about two minutes. The command ends with a summary like the one below. **The addresses and the password in this example are placeholders and do not work.** Use the ones your own terminal prints.

   ```
   The lab is ready. Open these in the browser on your own computer.

     Editor            https://203-0-113-10.sslip.io/ide/
     Editor password   4827
     FHIR server       https://203-0-113-10.sslip.io/fhir/Patient?_summary=count
     Pipelines         https://203-0-113-10.sslip.io:8443/
     Dashboard         https://203-0-113-10.sslip.io/dashboard/
   ```

   The numbers in the middle of each address, here `203-0-113-10`, are the public address of your own lab. Yours is different.

5. The lab loads its synthetic data into the FHIR server in the background while the Editor starts. It takes about a minute. The Pipeline log in the Editor says when it is done.

### Open the four tabs

Open the Editor first, enter the password, and keep it open. The buttons at the bottom of the Editor open the other three in new browser tabs, so you never have to type an address.

| Tab | What it is for | How to open it |
|---|---|---|
| 1. Editor | The ViewDefinitions, the dashboard code, a terminal and this guide | The Editor address from the summary |
| 2. FHIR server | The data as FHIR resources | **FHIR server** at the bottom of the Editor |
| 3. Pipelines | The FHIR Data Pipes controller, where you run the pipeline | **Pipelines** at the bottom of the Editor |
| 4. Dashboard | The Observable Framework dashboard | **Dashboard** at the bottom of the Editor |

The Editor opens with the Terminal on the left, the Pipeline log under it, and this guide on the right, one step at a time. From here on the guide is inside the Editor. Step 3 starts there.

### Find your addresses again

Come back here after a break, or when a tab stops loading. Start the VM in Heropa if it is stopped, reload the tabs, and if they do not load run `./lab-init.sh` again in `~/analytics-codelab`. It is safe at any time and your changes are kept. `./lab-init.sh --info` prints the addresses and the password without changing anything.

