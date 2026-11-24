// Adds a Copy button to every code block in the rendered manual.
//
// The Markdown preview that ships with the editor has no such button. This
// script runs inside the preview, where the extension registers it. It runs
// again each time the preview redraws, and skips blocks that have a button.

(function () {
  const COPY = 'Copy';
  const DONE = 'Copied';

  // The clipboard API needs a secure page and a click, both of which hold
  // here. The older command is the fallback for a browser that refuses.
  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (error) {
      const area = document.createElement('textarea');
      area.value = text;
      area.style.position = 'fixed';
      area.style.opacity = '0';
      document.body.appendChild(area);
      area.select();
      let ok = false;
      try {
        ok = document.execCommand('copy');
      } catch (ignored) {
        ok = false;
      }
      area.remove();
      return ok;
    }
  }

  function addButtons() {
    for (const pre of document.querySelectorAll('pre')) {
      const code = pre.querySelector('code');
      if (!code || pre.querySelector('.codelab-copy')) continue;
      // Blocks marked as text hold sample output, such as example addresses,
      // which nobody should paste anywhere.
      if (code.classList.contains('language-text')) continue;
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'codelab-copy';
      button.textContent = COPY;
      button.title = 'Copy this code';
      button.addEventListener('click', async (event) => {
        event.preventDefault();
        event.stopPropagation();
        // A trailing line break would add an empty line where the code is pasted.
        const ok = await copyText(code.textContent.replace(/\n$/, ''));
        button.textContent = ok ? DONE : 'Select and press Ctrl+C';
        button.classList.toggle('codelab-copied', ok);
        setTimeout(() => {
          button.textContent = COPY;
          button.classList.remove('codelab-copied');
        }, 1800);
      });
      pre.classList.add('codelab-has-copy');
      pre.appendChild(button);
    }
  }

  addButtons();
  window.addEventListener('vscode.markdown.updateContent', addButtons);
  window.addEventListener('load', addButtons);
})();
