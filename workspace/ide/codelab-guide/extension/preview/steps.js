// Shows the rendered manual one step at a time, with Back and Next buttons.
//
// A step is a second level heading and everything under it, up to the next
// one. The title and the lines above the first heading belong to the first
// step. This script runs inside the Markdown preview, where the extension
// registers it, and runs again each time the preview redraws.
//
// Nothing in the page is moved or wrapped. Each element only gets a class
// that hides it when its step is not the one on screen, so the preview can
// redraw the page as it always does.

(function () {
  const STEP_KEY = 'codelab-guide-step';
  const ALL_KEY = 'codelab-guide-all';
  const HIDDEN = 'codelab-step-hidden';
  const UI = 'codelab-step-ui';

  let current = Number(read(STEP_KEY, '0')) || 0;
  let showAll = read(ALL_KEY, '') === '1';
  let sections = [];

  // The browser may refuse storage inside the preview. The guide then starts
  // at the first step after a reload, and works the same otherwise.
  function read(key, fallback) {
    try {
      const value = window.localStorage.getItem(key);
      return value === null ? fallback : value;
    } catch (ignored) {
      return fallback;
    }
  }

  function write(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch (ignored) {
      // Nothing to do. The choice lasts until the next reload.
    }
  }

  function container() {
    const first = document.querySelector('h2');
    return first ? first.parentElement : null;
  }

  // Groups the elements of the page by the heading they sit under.
  function collect() {
    sections = [];
    const root = container();
    if (!root) return;
    let lead = [];
    for (const element of Array.from(root.children)) {
      if (element.classList.contains(UI)) continue;
      if (element.tagName === 'H2') {
        sections.push({ title: element.textContent.trim(), elements: lead.concat([element]) });
        lead = [];
      } else if (sections.length === 0) {
        lead.push(element);
      } else {
        sections[sections.length - 1].elements.push(element);
      }
    }
  }

  function button(label, title, onClick) {
    const element = document.createElement('button');
    element.type = 'button';
    element.textContent = label;
    element.title = title;
    element.addEventListener('click', onClick);
    return element;
  }

  // The bar at the top of the guide, and the pair of buttons under the text.
  function buildUi() {
    for (const old of document.querySelectorAll('.' + UI)) old.remove();

    const bar = document.createElement('div');
    bar.className = UI + ' codelab-step-bar';
    const back = button('Back', 'Go to the previous step', () => go(current - 1));
    back.className = 'codelab-step-back';
    const next = button('Next', 'Go to the next step', () => go(current + 1));
    next.className = 'codelab-step-next';
    const select = document.createElement('select');
    select.title = 'Jump to a step';
    sections.forEach((section, index) => {
      const option = document.createElement('option');
      option.value = String(index);
      option.textContent = section.title;
      select.appendChild(option);
    });
    select.addEventListener('change', () => go(Number(select.value)));
    const count = document.createElement('span');
    count.className = 'codelab-step-count';
    const all = button('', 'Switch between one step and the whole guide', () => {
      showAll = !showAll;
      write(ALL_KEY, showAll ? '1' : '');
      apply(true);
    });
    all.className = 'codelab-step-all';
    bar.append(back, select, count, next, all);
    document.body.appendChild(bar);

    const foot = document.createElement('div');
    foot.className = UI + ' codelab-step-foot';
    const footBack = button('Back', 'Go to the previous step', () => go(current - 1));
    footBack.className = 'codelab-step-back';
    const footNext = button('Next', 'Go to the next step', () => go(current + 1));
    footNext.className = 'codelab-step-next';
    foot.append(footBack, footNext);
    document.body.appendChild(foot);
  }

  function apply(toTop) {
    if (sections.length < 2) return;
    current = Math.min(Math.max(current, 0), sections.length - 1);
    sections.forEach((section, index) => {
      const hide = !showAll && index !== current;
      for (const element of section.elements) element.classList.toggle(HIDDEN, hide);
    });
    document.body.classList.add('codelab-stepped');
    document.body.classList.toggle('codelab-stepped-all', showAll);
    const select = document.querySelector('.codelab-step-bar select');
    if (select) select.value = String(current);
    const count = document.querySelector('.codelab-step-count');
    if (count) count.textContent = showAll ? 'All steps' : (current + 1) + ' of ' + sections.length;
    const all = document.querySelector('.codelab-step-all');
    if (all) all.textContent = showAll ? 'One step' : 'Show all';
    for (const back of document.querySelectorAll('.codelab-step-back')) {
      back.disabled = showAll || current === 0;
    }
    for (const next of document.querySelectorAll('.codelab-step-next')) {
      next.disabled = showAll || current === sections.length - 1;
    }
    if (toTop) {
      if (showAll) {
        const heading = sections[current].elements.find((element) => element.tagName === 'H2');
        if (heading) heading.scrollIntoView();
        window.scrollBy(0, -60);
      } else {
        window.scrollTo(0, 0);
      }
    }
  }

  function go(index) {
    current = index;
    write(STEP_KEY, String(current));
    apply(true);
  }

  // Finds the step that holds an element, such as the target of a link.
  function sectionOf(target) {
    return sections.findIndex((section) =>
      section.elements.some((element) => element === target || element.contains(target)));
  }

  // A link to a heading in another step first has to bring that step on
  // screen. The preview's own handling of the link would find it hidden.
  function onClick(event) {
    const link = event.target.closest ? event.target.closest('a[href]') : null;
    if (!link || link.closest('.' + UI)) return;
    const href = link.getAttribute('href') || '';
    const hash = href.indexOf('#');
    if (hash < 0) return;
    let id = href.slice(hash + 1);
    try {
      id = decodeURIComponent(id);
    } catch (ignored) {
      // Keep the id as written.
    }
    const target = id ? document.getElementById(id) : null;
    if (!target) return;
    const index = sectionOf(target);
    if (index < 0) return;
    event.preventDefault();
    event.stopPropagation();
    current = index;
    write(STEP_KEY, String(current));
    apply(false);
    target.scrollIntoView();
    window.scrollBy(0, -60);
  }

  function refresh() {
    collect();
    if (sections.length < 2) return;
    buildUi();
    apply(false);
  }

  // When the page opens, the preview scrolls to the line it showed last time.
  // With one step on screen that line may be hidden, and the view would land
  // in the empty space under the step. So the step starts at its top, unless
  // the reader has already begun to scroll.
  let touched = false;
  function toTopOnOpen() {
    if (!touched && !showAll && sections.length > 1) window.scrollTo(0, 0);
  }
  for (const name of ['wheel', 'keydown', 'mousedown', 'touchstart']) {
    window.addEventListener(name, () => { touched = true; }, { capture: true, passive: true });
  }

  refresh();
  window.addEventListener('vscode.markdown.updateContent', refresh);
  window.addEventListener('load', () => {
    refresh();
    toTopOnOpen();
  });
  for (const delay of [150, 600, 1500]) setTimeout(toTopOnOpen, delay);
  document.addEventListener('click', onClick, true);
})();
