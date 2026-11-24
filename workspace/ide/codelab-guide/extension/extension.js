// Lays the editor out for the analytics codelab.
//
//   left, top      the dashboard code, the ViewDefinitions and the data loaders
//   left, bottom   the pipeline log, with a terminal in a tab next to it
//   right          the course manual, rendered, at full height
//
// VS Code has no setting that opens files or pages when it starts, so this
// small extension does it. The manual uses the Markdown preview that ships
// with the editor. The build log and the output are web views holding the
// lab's /buildlog/ and /output/ pages. They sit in the editor area, which
// leaves the manual its full height.
//
// The app is not shown inside the editor, because a fourth pane left too
// little room for each. The App button in the status bar opens it in a
// browser tab of its own. Other buttons there bring back a pane that was
// closed.
//
// The lab can also run in reduced mode, which lab-init.sh picks when it could
// not get a certificate that browsers trust. Browsers then refuse every web
// view in the editor, and the rendered manual, the build log and the output
// are all web views. In that mode the manual opens as plain text, and the
// build log and the output open as pages in browser tabs.

const vscode = require('vscode');
const fs = require('fs');
const { execFile } = require('child_process');

const GUIDE = process.env.CODELAB_GUIDE || '/opt/codelab/guide/course-manual.md';
const APP_FILE = (process.env.CODELAB_DIR || '') + '/dashboard/src/index.md';
const LAB_URL = (process.env.LAB_URL || '').replace(/\/+$/, '');
const REDUCED = process.env.LAB_MODE === 'reduced';
const GUIDE_EDITOR = 'vscode.markdown.preview.editor';
const BUILD = { view: 'codelab.build', title: 'Pipeline log', path: '/buildlog/' };
// Shows what the app prints. The app runs in another browser tab and saves
// its output in the browser's storage, where this page finds it.
const OUTPUT = { view: 'codelab.output', title: 'Output', path: '/output/' };
// An earlier version showed the app in a pane. A browser may still hold that
// tab in its saved layout, so it is closed when the editor restores it.
const OLD_APP_VIEW = 'codelab.app';
const TERMINAL = 'Terminal';

// The three panes, in the order VS Code numbers them.
const COLUMN = { code: 1, build: 2, guide: 3 };
const LAYOUT = {
  orientation: 0,
  groups: [{ size: 0.6, groups: [{ size: 0.66 }, { size: 0.34 }] }, { size: 0.4 }],
};

function anyTab(test) {
  return vscode.window.tabGroups.all.some((group) => group.tabs.some((tab) => test(tab.input)));
}
// True when the pane is already open, for example restored after a reload.
const guideIsOpen = () =>
  anyTab(
    (input) =>
      (input instanceof vscode.TabInputCustom && input.viewType === GUIDE_EDITOR) ||
      (input instanceof vscode.TabInputWebview && /markdown\.preview/.test(input.viewType)) ||
      (REDUCED && input instanceof vscode.TabInputText && input.uri.fsPath === GUIDE),
  );
const pageIsOpen = (page) =>
  anyTab((input) => input instanceof vscode.TabInputWebview && input.viewType.endsWith(page.view));
const terminalIsOpen = () => vscode.window.terminals.length > 0;

function pageHtml(page) {
  const nonce = Math.random().toString(36).slice(2) + Date.now().toString(36);
  // The small script passes on one kind of message from the framed page, the
  // one that says new output arrived, so the tab can come to the front.
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; frame-src ${LAB_URL}; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
  <style>html, body, iframe { margin: 0; padding: 0; width: 100%; height: 100%; border: 0; display: block; } body { overflow: hidden; }</style>
</head>
<body>
<iframe src="${LAB_URL}${page.path}" title="${page.title}" allow="clipboard-write"></iframe>
<script nonce="${nonce}">
  const editor = acquireVsCodeApi();
  window.addEventListener('message', (event) => {
    if (event.origin === ${JSON.stringify(new URL(LAB_URL || 'http://localhost').origin)} && event.data && event.data.type === 'codelab-output') {
      editor.postMessage({ type: 'codelab-output' });
    }
  });
</script>
</body>
</html>`;
}

function fillPage(panel, page) {
  panel.webview.options = { enableScripts: true };
  panel.webview.html = pageHtml(page);
  // New output brings its tab to the front without taking the keyboard.
  panel.webview.onDidReceiveMessage((message) => {
    if (message && message.type === 'codelab-output') panel.reveal(panel.viewColumn, true);
  });
}

function openPage(page) {
  const panel = vscode.window.createWebviewPanel(
    page.view,
    page.title,
    { viewColumn: COLUMN.build, preserveFocus: true },
    { enableScripts: true, retainContextWhenHidden: true },
  );
  fillPage(panel, page);
  return panel;
}

// Opens whichever of the wanted panes is missing and leaves the keyboard in
// the code.
async function arrange(want) {
  const needGuide = want.guide && !guideIsOpen() && fs.existsSync(GUIDE);
  const needBuild = !REDUCED && want.build && !pageIsOpen(BUILD) && LAB_URL !== '';
  const needOutput = !REDUCED && want.output && !pageIsOpen(OUTPUT) && LAB_URL !== '';
  const needTerminal = want.terminal && !terminalIsOpen();
  if (!needGuide && !needBuild && !needOutput && !needTerminal) return;

  if (!vscode.window.activeTextEditor && fs.existsSync(APP_FILE)) {
    await vscode.window.showTextDocument(vscode.Uri.file(APP_FILE), { viewColumn: COLUMN.code, preview: false });
  }
  await vscode.commands.executeCommand('vscode.setEditorLayout', LAYOUT);

  // Tabs line up in the order they are made, which is build log, output,
  // then terminal.
  let buildPanel;
  if (needBuild) {
    buildPanel = openPage(BUILD);
  }
  if (needOutput) {
    openPage(OUTPUT);
  }
  if (needTerminal) {
    vscode.window.createTerminal({ name: TERMINAL, location: { viewColumn: COLUMN.build, preserveFocus: true } });
  }
  if (needGuide && REDUCED) {
    await vscode.window.showTextDocument(vscode.Uri.file(GUIDE), {
      viewColumn: COLUMN.guide,
      preserveFocus: true,
      preview: false,
    });
  } else if (needGuide) {
    await vscode.commands.executeCommand('vscode.openWith', vscode.Uri.file(GUIDE), GUIDE_EDITOR, {
      viewColumn: COLUMN.guide,
      preserveFocus: true,
    });
  }
  if (buildPanel && (needTerminal || needOutput)) {
    // The tabs made after the build log cover it, and the terminal takes a
    // moment to appear. The build log is the tab a learner should see first.
    await new Promise((resolve) => setTimeout(resolve, 2500));
    buildPanel.reveal(COLUMN.build, true);
  }
  await vscode.commands.executeCommand('workbench.action.focusFirstEditorGroup');
}

// In reduced mode a pane's button opens the same page in a browser tab.
function showPage(page, want) {
  if (!REDUCED) return arrange(want);
  if (LAB_URL === '') {
    vscode.window.showWarningMessage('The lab address is not known. Start the lab with lab-init.sh.');
    return undefined;
  }
  return vscode.env.openExternal(vscode.Uri.parse(LAB_URL + page.path));
}

// Opens the app in a browser tab of its own. The page reloads the app after
// each successful build and shows what the app prints.
function openApp() {
  if (LAB_URL === '') {
    vscode.window.showWarningMessage('The lab address is not known. Start the lab with lab-init.sh.');
    return;
  }
  vscode.env.openExternal(vscode.Uri.parse(LAB_URL + '/preview/'));
}

// Saves every open file and starts a build. A save starts one anyway, so this
// is for the times nothing changed, or a learner wants to be sure.
async function buildNow() {
  await vscode.workspace.saveAll(false);
  execFile('/usr/local/bin/build-dashboard', { env: process.env }, (error, stdout, stderr) => {
    if (error) {
      vscode.window.showErrorMessage('The dashboard build did not run. ' + (stderr || error.message));
      return;
    }
    vscode.window.showInformationMessage('The dashboard was rebuilt.');
    if (!REDUCED) arrange({ build: true });
  });
}

// Starts a full pipeline run. The Pipelines tab of the browser shows it.
async function runPipeline() {
  execFile('/usr/local/bin/run-pipeline', ['--no-wait'], { env: process.env }, (error, stdout, stderr) => {
    if (error) {
      vscode.window.showErrorMessage('The pipeline did not start. ' + (stderr || error.message));
      return;
    }
    vscode.window.showInformationMessage('The pipeline run started. Follow it in the Pipelines tab, then click Refresh dashboard.');
  });
}

function openPipelines() {
  const url = process.env.LAB_PIPES_URL || '';
  if (url === '') {
    vscode.window.showWarningMessage('The Pipelines address is not known. Start the lab with lab-init.sh.');
    return;
  }
  vscode.env.openExternal(vscode.Uri.parse(url));
}

// The FHIR server is read only from the browser, so a learner can look at the
// data with a plain address.
function openFhir() {
  if (LAB_URL === '') {
    vscode.window.showWarningMessage('The lab address is not known. Start the lab with lab-init.sh.');
    return;
  }
  vscode.env.openExternal(vscode.Uri.parse(LAB_URL + '/fhir/Patient?_summary=count'));
}

function statusButton(context, text, tooltip, command, priority) {
  const button = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, priority);
  button.text = text;
  button.tooltip = tooltip;
  button.command = command;
  button.show();
  context.subscriptions.push(button);
}

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand('codelab.showGuide', () => arrange({ guide: true })),
    vscode.commands.registerCommand('codelab.showBuild', () => showPage(BUILD, { build: true })),
    vscode.commands.registerCommand('codelab.showAll', () => arrange({ guide: true, build: true, terminal: true })),
    vscode.commands.registerCommand('codelab.openApp', openApp),
    vscode.commands.registerCommand('codelab.runPipeline', runPipeline),
    vscode.commands.registerCommand('codelab.openPipelines', openPipelines),
    vscode.commands.registerCommand('codelab.openFhir', openFhir),
    vscode.commands.registerCommand('codelab.buildNow', buildNow),
    // Without these the editor would bring the two tabs back empty after a
    // reload.
    ...[BUILD, OUTPUT].map((page) =>
      vscode.window.registerWebviewPanelSerializer(page.view, {
        async deserializeWebviewPanel(panel) {
          // A pane restored from a full mode session would only show an error.
          if (REDUCED) panel.dispose();
          else fillPage(panel, page);
        },
      }),
    ),
    vscode.window.registerWebviewPanelSerializer(OLD_APP_VIEW, {
      async deserializeWebviewPanel(panel) {
        panel.dispose();
      },
    }),
  );
  statusButton(context, '$(database) FHIR server', 'Open the FHIR server in a new browser tab', 'codelab.openFhir', 105);
  statusButton(context, '$(server-process) Pipelines', 'Open the FHIR Data Pipes controller in a new browser tab', 'codelab.openPipelines', 104);
  statusButton(context, '$(graph) Dashboard', 'Open the dashboard in a new browser tab', 'codelab.openApp', 103);
  statusButton(context, '$(play) Run pipeline', 'Start a full pipeline run', 'codelab.runPipeline', 102.5);
  statusButton(context, '$(refresh) Refresh dashboard', 'Rebuild the dashboard from the analytics database', 'codelab.buildNow', 102.2);
  statusButton(context, '$(book) Guide', 'Show the codelab guide', 'codelab.showGuide', 102);
  const where = REDUCED ? ' in a new browser tab' : '';
  statusButton(context, '$(tools) Pipeline log', 'Show the pipeline log' + where, 'codelab.showBuild', 101);

  arrange({ guide: true, build: true, terminal: true });

  if (REDUCED) {
    vscode.window.showWarningMessage(
      'This lab is in reduced mode, because it has no certificate that browsers trust. ' +
        'The Pipeline log button opens a browser tab, and the guide shows as plain text. ' +
        'Your code, the pipeline and the dashboard work as usual.',
    );
  }
}

module.exports = { activate, deactivate() {} };
